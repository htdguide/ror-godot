extends GateBase
## Establishes, by measurement, how Godot composes an instance transform with a
## server-attached skeleton's bone transform.
##
## This exists because inference from assembled vehicle renders gave a contradiction: the
## configuration that should compose to a no-op did not, and a configuration that should
## be wrong by 90 degrees rendered correctly. Guessing at engine semantics from complex
## scenes is how a wrong convention gets baked in, so the question is asked with one
## vertex, one bone and one instance, where only one answer can fit.
##
## The candidates, for a vertex P, bone transform B and instance transform I:
##   world = I * B * P   the documented composition
##   world = B * P       instance transform ignored for skinned meshes
##   world = I * P       bone transform ignored
##
## The instance transform here is a translation, which leaves the order of I and B
## indistinguishable. Rotating it would separate them, but a rotated instance transform
## makes the skinned point vanish from the frame entirely, which is the open problem
## recorded in docs/architecture/bridge.md rather than something for this gate to chase.

## How far the marker channel must lead the others. Absolute thresholds break as soon as
## a tonemapper is in the pipeline: an unshaded ALBEDO is still tonemapped, so a pure blue
## marker no longer lands near (0, 0, 1) on screen. Hue dominance survives that.
const MARKER_DOMINANCE: float = 0.08
const PRESET: String = "diag_origin"
const POINT: Vector3 = Vector3(0.0, 1.0, 0.0)
const BONE_OFFSET: Vector3 = Vector3(1.5, 0.0, 0.0)
const INSTANCE_OFFSET: Vector3 = Vector3(0.0, 0.0, 2.0)
## Translation only. Adding a 90 degree yaw here makes the skinned point vanish from the
## frame entirely — see docs/architecture/bridge.md, which is the open lead on the vehicle
## frame. This gate establishes the composition; it is not the place to chase that.
const INSTANCE_YAW_DEGREES: float = 0.0
const SETTLE_FRAMES: int = 3
const POINT_SIZE: float = 9.0
## Screen-space agreement required, in pixels. The candidates are metres apart, so they
## project hundreds of pixels apart and this only has to exclude blur and point size.
const MATCH_TOLERANCE_PX: float = 12.0


static func meta() -> Dictionary:
    return {
        "name": "skinning_transform_semantics",
        "proves": "how Godot composes instance and bone transforms for a server-attached skeleton",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "rendered point within %.0f px of exactly one candidate composition" % MATCH_TOLERANCE_PX,
        "why": (
            "the vehicle render disagreed with the documented composition, and inferring"
            + " engine semantics from a complex scene is how a wrong convention gets"
            + " baked in. One vertex, one bone and one instance admit only one answer."
        ),
        "budget_s": 60.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)

    var mesh: ArrayMesh = _point_mesh()
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.mesh = mesh
    instance.material_override = _material()
    instance.custom_aabb = AABB(-Vector3.ONE * 50.0, Vector3.ONE * 100.0)
    var instance_transform: Transform3D = Transform3D(
        Basis(Vector3.UP, deg_to_rad(INSTANCE_YAW_DEGREES)), INSTANCE_OFFSET
    )
    instance.transform = instance_transform
    harness.world.add_child(instance)

    var skeleton: RID = RenderingServer.skeleton_create()
    RenderingServer.skeleton_allocate_data(skeleton, 1)
    RenderingServer.skeleton_bone_set_transform(
        skeleton, 0, Transform3D(Basis.IDENTITY, BONE_OFFSET)
    )
    RenderingServer.instance_attach_skeleton(instance.get_instance(), skeleton)

    await harness.advance_frames(SETTLE_FRAMES, "static", "semantics")
    var shot: Dictionary = await harness.capture_shot("skinning_semantics", "static", 1)
    RenderingServer.free_rid(skeleton)
    if shot["error"] != "":
        return fail(shot["error"] as String)

    var rendered: Vector2 = _rendered_centre(shot["png"] as String)
    if rendered.x < 0.0:
        return fail("nothing rendered; artifact: %s" % shot["png"])

    var camera: Camera3D = harness.camera
    var bone: Transform3D = Transform3D(Basis.IDENTITY, BONE_OFFSET)
    var candidates: Dictionary = {
        "instance * bone * point": instance_transform * (bone * POINT),
        "bone * point": bone * POINT,
        "instance * point": instance_transform * POINT,
    }
    var matches: PackedStringArray = PackedStringArray()
    var report: PackedStringArray = PackedStringArray()
    for name: String in candidates.keys():
        var expected: Vector2 = camera.unproject_position(candidates[name] as Vector3)
        var distance: float = rendered.distance_to(expected)
        report.append("%s: %.0f px" % [name, distance])
        if distance <= MATCH_TOLERANCE_PX:
            matches.append(name)

    if matches.size() != 1:
        return fail(
            "rendered point at %s matched %d candidates (%s); artifact: %s"
            % [rendered, matches.size(), ", ".join(report), shot["png"]],
            matches.size()
        )
    return ok("Godot composes as: %s (%s)" % [matches[0], ", ".join(report)], matches[0])


func _point_mesh() -> ArrayMesh:
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([POINT])
    arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0, 0, 0, 0])
    arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1.0, 0.0, 0.0, 0.0])
    var mesh: ArrayMesh = ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
    return mesh


func _material() -> ShaderMaterial:
    var shader: Shader = Shader.new()
    shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
uniform float point_size = 9.0;
void vertex() { POINT_SIZE = point_size; }
void fragment() { ALBEDO = vec3(0.0, 0.0, 1.0); }
"""
    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("point_size", POINT_SIZE)
    return material


## Centroid of the rendered blue pixels, or (-1, -1) if nothing rendered.
func _rendered_centre(png_path: String) -> Vector2:
    var image: Image = Image.load_from_file(png_path)
    if image == null:
        return Vector2(-1.0, -1.0)
    var size: Vector2i = image.get_size()
    var total: Vector2 = Vector2.ZERO
    var count: int = 0
    for y: int in size.y:
        for x: int in size.x:
            var pixel: Color = image.get_pixel(x, y)
            if pixel.b > pixel.r + MARKER_DOMINANCE and pixel.b > pixel.g + MARKER_DOMINANCE:
                total += Vector2(float(x), float(y))
                count += 1
    return Vector2(-1.0, -1.0) if count == 0 else total / float(count)
