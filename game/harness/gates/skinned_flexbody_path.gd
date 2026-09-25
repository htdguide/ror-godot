extends GateBase
## Bisects code path against data for the frame fault.
##
## Every mesh property the vehicle uses skins correctly in isolation
## (`skinning_mesh_variants`), yet the real vehicle draws as though its bones were never
## applied. This puts a synthetic quad through `SkinnedFlexbody` itself — the same class,
## the same calls, in the same order, under a rotated parent standing in for the vehicle
## root — so the answer is one of two things and not a guess:
##
##   it skins      the class is fine and the difference is the real mesh's data
##   it does not   the difference is this class's own sequence

## How far the marker channel must lead the others. Absolute thresholds break as soon as
## a tonemapper is in the pipeline: an unshaded ALBEDO is still tonemapped, so a pure blue
## marker no longer lands near (0, 0, 1) on screen. Hue dominance survives that.
const MARKER_DOMINANCE: float = 0.08
const PRESET: String = "diag_topdown"
const YAW_DEGREES: float = 90.0
const QUAD_HALF: float = 0.6
const ACTOR_ORIGIN: Vector3 = Vector3(-0.85, 0.18, -0.36)
const SETTLE_FRAMES: int = 3
const MATCH_TOLERANCE_PX: float = 25.0


static func meta() -> Dictionary:
    return {
        "name": "skinned_flexbody_path",
        "proves": "SkinnedFlexbody applies its bone transforms when its parent carries a frame",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "geometry renders within %.0f px of its rig position, not its parent's frame" % MATCH_TOLERANCE_PX,
        "why": (
            "the vehicle's meshes draw as if unskinned while every mesh property they use"
            + " skins in isolation. Running synthetic data through the real class"
            + " separates the class's own sequence from the data it is given."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)

    # A node rig around the quad, spread enough that locator triads are well conditioned.
    var nodes: PackedVector3Array = PackedVector3Array([
        Vector3(-1.0, 0.0, -1.0),
        Vector3(1.0, 0.0, -1.0),
        Vector3(-1.0, 0.0, 1.0),
        Vector3(1.0, 0.0, 1.0),
        Vector3(0.0, 1.0, 0.0),
    ])
    var forset: PackedInt32Array = PackedInt32Array([0, 1, 2, 3, 4])
    var vertices: PackedVector3Array = PackedVector3Array([
        Vector3(-QUAD_HALF, 0.5, -QUAD_HALF),
        Vector3(QUAD_HALF, 0.5, -QUAD_HALF),
        Vector3(QUAD_HALF, 0.5, QUAD_HALF),
        Vector3(-QUAD_HALF, 0.5, QUAD_HALF),
    ])
    var indices: PackedInt32Array = PackedInt32Array([0, 1, 2, 0, 2, 3])
    var uvs: PackedVector2Array = PackedVector2Array([
        Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)
    ])

    # The parent stands in for the vehicle root carrying the actor frame.
    # Translated as well as rotated: the vehicle's frame has an origin away from the rig
    # origin, and a zero-translation frame cannot expose a mistake that depends on it.
    var actor: Transform3D = Transform3D(
        Basis(Vector3.UP, deg_to_rad(YAW_DEGREES)), ACTOR_ORIGIN
    )
    var root: Node3D = Node3D.new()
    root.transform = actor
    harness.world.add_child(root)

    var part: SkinnedFlexbody = SkinnedFlexbody.new()
    var build_error: String = part.build(
        root, nodes, forset, vertices, indices, _material(), uvs
    )
    if build_error != "":
        return fail(build_error)
    part.set_pose(nodes, actor, false)

    await harness.advance_frames(SETTLE_FRAMES, "static", "flexbody_path")
    var shot: Dictionary = await harness.capture_shot("skinned_flexbody_path", "static", 1)
    if shot["error"] != "":
        return fail(shot["error"] as String)
    var rendered: Vector2 = _rendered_centre(shot["png"] as String)
    part.free_resources()
    root.queue_free()
    if rendered.x < 0.0:
        return fail("nothing rendered; artifact: %s" % shot["png"])

    var centre: Vector3 = Vector3(0.0, 0.5, 0.0)
    var camera: Camera3D = harness.camera
    var skinned_at: Vector2 = camera.unproject_position(centre)
    var unskinned_at: Vector2 = camera.unproject_position(actor * centre)
    var to_skinned: float = rendered.distance_to(skinned_at)
    var to_unskinned: float = rendered.distance_to(unskinned_at)

    if to_skinned <= MATCH_TOLERANCE_PX:
        return ok(
            "SkinnedFlexbody applies its bones (%.0f px from the rig position): the frame"
            % to_skinned
            + " fault is in the real mesh's data, not this class",
            to_skinned
        )
    if to_unskinned <= MATCH_TOLERANCE_PX:
        return fail(
            "SkinnedFlexbody did not apply its bones: geometry rendered at the parent's"
            + " frame (%.0f px) instead of the rig position (%.0f px). The fault is in"
            % [to_unskinned, to_skinned]
            + " this class's own sequence; artifact: %s" % shot["png"],
            to_unskinned
        )
    return fail(
        "geometry rendered %.0f px from the rig position and %.0f px from the parent frame;"
        % [to_skinned, to_unskinned]
        + " neither explanation fits. Artifact: %s" % shot["png"],
        to_skinned
    )


func _material() -> ShaderMaterial:
    var shader: Shader = Shader.new()
    shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
void fragment() { ALBEDO = vec3(0.0, 0.0, 1.0); }
"""
    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = shader
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
