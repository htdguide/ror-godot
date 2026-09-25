extends GateBase
## Finds where a skinned mesh disappears as its instance transform is rotated, and whether
## culling is the reason.
##
## Wiring the vehicle's frame makes its skinned body vanish while its wheels stay put. The
## frame is a 90 degree yaw plus a translation, and a one-vertex rig shows the same thing:
## with a translated instance the skinned point renders where it should, and with the same
## instance yawed it is gone from the frame entirely. This measures where that starts and
## tests the obvious suspect.

## An empty stage. The first version of this sweep used a preset that keeps the blockout
## scale props, and the "vanishing" was the point passing inside one of the boxes.
## How far the marker channel must lead the others. Absolute thresholds break as soon as
## a tonemapper is in the pipeline: an unshaded ALBEDO is still tonemapped, so a pure blue
## marker no longer lands near (0, 0, 1) on screen. Hue dominance survives that.
const MARKER_DOMINANCE: float = 0.08
const PRESET: String = "diag_topdown"
const POINT: Vector3 = Vector3(0.0, 1.0, 0.0)
const BONE_OFFSET: Vector3 = Vector3(1.5, 0.0, 0.0)
const INSTANCE_OFFSET: Vector3 = Vector3(0.0, 0.0, 2.0)
const YAW_STEPS: Array[float] = [0.0, 30.0, 60.0, 85.0, 90.0, 95.0, 180.0, 270.0]
const SETTLE_FRAMES: int = 3
const POINT_SIZE: float = 9.0
const MATCH_TOLERANCE_PX: float = 14.0
const AABB_EXTENT: float = 500.0


static func meta() -> Dictionary:
    return {
        "name": "skinned_rotation_sweep",
        "proves": "a skinned mesh stays rendered, and in the right place, as its instance transform rotates",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "point found within %.0f px of instance * bone * vertex at every yaw" % MATCH_TOLERANCE_PX,
        "why": (
            "the vehicle's skinned body disappears when its frame is applied, and the"
            + " frame is a yaw plus a translation. One vertex, one bone and one instance"
            + " isolate that from everything else a vehicle brings with it."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)

    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.mesh = _point_mesh()
    instance.material_override = _material()
    instance.custom_aabb = AABB(-Vector3.ONE * AABB_EXTENT, Vector3.ONE * AABB_EXTENT * 2.0)
    harness.world.add_child(instance)

    var skeleton: RID = RenderingServer.skeleton_create()
    RenderingServer.skeleton_allocate_data(skeleton, 1)
    RenderingServer.skeleton_bone_set_transform(
        skeleton, 0, Transform3D(Basis.IDENTITY, BONE_OFFSET)
    )
    RenderingServer.instance_attach_skeleton(instance.get_instance(), skeleton)

    var report: PackedStringArray = PackedStringArray()
    var first_lost: float = -1.0
    var first_wrong: float = -1.0
    for yaw: float in YAW_STEPS:
        var found: Dictionary = await _sample(harness, instance, yaw, "yaw_%d" % int(yaw))
        report.append("%d deg: %s" % [int(yaw), found["detail"]])
        if not bool(found["rendered"]) and first_lost < 0.0:
            first_lost = yaw
        if bool(found["rendered"]) and not bool(found["correct"]) and first_wrong < 0.0:
            first_wrong = yaw

    var culling_note: String = ""
    if first_lost >= 0.0:
        RenderingServer.instance_set_ignore_culling(instance.get_instance(), true)
        var retry: Dictionary = await _sample(
            harness, instance, first_lost, "ignore_culling"
        )
        culling_note = "; with culling ignored at %d deg: %s" % [int(first_lost), retry["detail"]]
        RenderingServer.instance_set_ignore_culling(instance.get_instance(), false)

    RenderingServer.free_rid(skeleton)
    if first_lost >= 0.0:
        return fail(
            "skinned point disappears from %d degrees of instance yaw (%s)%s"
            % [int(first_lost), ", ".join(report), culling_note],
            first_lost
        )
    if first_wrong >= 0.0:
        return fail(
            "skinned point renders in the wrong place from %d degrees of instance yaw (%s)"
            % [int(first_wrong), ", ".join(report)],
            first_wrong
        )
    return ok("skinned point tracks instance * bone * vertex at every yaw (%s)" % ", ".join(report), 0)


func _sample(harness: Node, instance: MeshInstance3D, yaw: float, tag: String) -> Dictionary:
    var transform: Transform3D = Transform3D(
        Basis(Vector3.UP, deg_to_rad(yaw)), INSTANCE_OFFSET
    )
    instance.transform = transform
    await harness.advance_frames(SETTLE_FRAMES, "static", tag)
    var shot: Dictionary = await harness.capture_shot("rotation_sweep/" + tag, "static", 1)
    if shot["error"] != "":
        return {"rendered": false, "correct": false, "detail": shot["error"]}
    var rendered: Vector2 = _rendered_centre(shot["png"] as String)
    if rendered.x < 0.0:
        return {"rendered": false, "correct": false, "detail": "not rendered"}
    var expected: Vector2 = harness.camera.unproject_position(
        transform * (Transform3D(Basis.IDENTITY, BONE_OFFSET) * POINT)
    )
    var distance: float = rendered.distance_to(expected)
    return {
        "rendered": true,
        "correct": distance <= MATCH_TOLERANCE_PX,
        "detail": "%.0f px off" % distance,
    }


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
