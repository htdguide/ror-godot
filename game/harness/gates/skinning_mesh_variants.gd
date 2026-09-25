extends GateBase
## Finds which mesh property stops Godot applying bone transforms.
##
## A single-bone points mesh skins correctly; the vehicle's parts — indexed triangles with
## UVs and a few hundred bones — are drawn as though the bones were never there. This walks
## one toward the other a property at a time, so the answer is a named property rather
## than a guess.
##
## Each variant is drawn with a bone transform that displaces it by a known amount. If
## skinning is applied the geometry appears at instance * bone * centre; if it is not, it
## appears at instance * centre. Those are far apart on screen, so the two cases cannot be
## confused.

## How far the marker channel must lead the others. Absolute thresholds break as soon as
## a tonemapper is in the pipeline: an unshaded ALBEDO is still tonemapped, so a pure blue
## marker no longer lands near (0, 0, 1) on screen. Hue dominance survives that.
const MARKER_DOMINANCE: float = 0.08
const PRESET: String = "diag_topdown"
const BONE_OFFSET: Vector3 = Vector3(2.5, 0.0, 0.0)
const QUAD_HALF: float = 0.35
const SETTLE_FRAMES: int = 3
const MATCH_TOLERANCE_PX: float = 25.0
const AABB_EXTENT: float = 500.0
## A bone index well past the first, to test whether a large skeleton behaves differently
## from a single-bone one.
const MANY_BONES: int = 292
const HIGH_BONE_INDEX: int = 250

const VARIANTS: Array[String] = [
    "points_1bone",
    "triangles_1bone",
    "triangles_indexed_1bone",
    "triangles_indexed_uv_1bone",
    "triangles_indexed_uv_custom0_1bone",
    "triangles_indexed_uv_manybones",
    # The vehicle's parts sit under a root that carries the frame, so their own transform
    # is identity while their global transform is not. Nothing above tests that.
    "parented_rotated",
    # Bone indices beyond 255, in case the index width changes with skeleton size.
    "triangles_indexed_uv_bone291",
]


static func meta() -> Dictionary:
    return {
        "name": "skinning_mesh_variants",
        "proves": "which mesh properties allow Godot to apply bone transforms, and which do not",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "every variant renders at instance * bone * centre, within %.0f px" % MATCH_TOLERANCE_PX,
        "why": (
            "the vehicle's parts are drawn as if unskinned while a one-vertex rig skins"
            + " correctly. Changing one mesh property at a time turns that into a named"
            + " cause instead of a suspicion."
        ),
        "budget_s": 180.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)

    var report: PackedStringArray = PackedStringArray()
    var unskinned: PackedStringArray = PackedStringArray()
    for variant: String in VARIANTS:
        var outcome: Dictionary = await _test(harness, variant)
        report.append("%s: %s" % [variant, outcome["detail"]])
        if not bool(outcome["skinned"]):
            unskinned.append(variant)

    if unskinned.size() > 0:
        return fail(
            "bone transforms are not applied for: %s (%s)"
            % [", ".join(unskinned), ", ".join(report)],
            unskinned.size()
        )
    return ok("every variant skins (%s)" % ", ".join(report), 0)


func _test(harness: Node, variant: String) -> Dictionary:
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.mesh = _mesh_for(variant)
    instance.material_override = _material()
    instance.custom_aabb = AABB(-Vector3.ONE * AABB_EXTENT, Vector3.ONE * AABB_EXTENT * 2.0)
    var parent: Node3D = null
    if variant == "parented_rotated":
        parent = Node3D.new()
        parent.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3.ZERO)
        harness.world.add_child(parent)
        parent.add_child(instance)
    else:
        harness.world.add_child(instance)

    var bone_count: int = 1
    if variant.ends_with("manybones") or variant.ends_with("bone291"):
        bone_count = MANY_BONES
    var skeleton: RID = RenderingServer.skeleton_create()
    RenderingServer.skeleton_allocate_data(skeleton, bone_count)
    for bone: int in bone_count:
        RenderingServer.skeleton_bone_set_transform(
            skeleton, bone, Transform3D(Basis.IDENTITY, BONE_OFFSET)
        )
    RenderingServer.instance_attach_skeleton(instance.get_instance(), skeleton)

    await harness.advance_frames(SETTLE_FRAMES, "static", variant)
    var shot: Dictionary = await harness.capture_shot("mesh_variants/" + variant, "static", 1)
    var rendered: Vector2 = Vector2(-1.0, -1.0)
    if shot["error"] == "":
        rendered = _rendered_centre(shot["png"] as String)
    instance.queue_free()
    if parent != null:
        parent.queue_free()
    RenderingServer.free_rid(skeleton)

    if rendered.x < 0.0:
        return {"skinned": false, "detail": "not rendered"}
    var camera: Camera3D = harness.camera
    # Expected positions go through the instance's own global transform, so the parented
    # case is judged in world space like the rest.
    var to_world: Transform3D = (
        Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3.ZERO)
        if variant == "parented_rotated"
        else Transform3D.IDENTITY
    )
    var skinned_at: Vector2 = camera.unproject_position(to_world * BONE_OFFSET)
    var unskinned_at: Vector2 = camera.unproject_position(to_world * Vector3.ZERO)
    var to_skinned: float = rendered.distance_to(skinned_at)
    var to_unskinned: float = rendered.distance_to(unskinned_at)
    if to_skinned <= MATCH_TOLERANCE_PX:
        return {"skinned": true, "detail": "skinned (%.0f px)" % to_skinned}
    if to_unskinned <= MATCH_TOLERANCE_PX:
        return {"skinned": false, "detail": "NOT skinned (at rest position)"}
    return {
        "skinned": false,
        "detail": "somewhere else (%.0f px from skinned, %.0f from rest)" % [to_skinned, to_unskinned],
    }


## A quad at the origin, built with whatever combination of properties the variant names.
func _mesh_for(variant: String) -> ArrayMesh:
    var mesh: ArrayMesh = ArrayMesh.new()
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    var bone_index: int = 0
    if variant.ends_with("manybones"):
        bone_index = HIGH_BONE_INDEX
    elif variant.ends_with("bone291"):
        bone_index = MANY_BONES - 1

    if variant == "parented_rotated":
        variant = "triangles_indexed_uv_1bone"
    if variant == "points_1bone":
        arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO])
        arrays[Mesh.ARRAY_BONES] = PackedInt32Array([0, 0, 0, 0])
        arrays[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1.0, 0.0, 0.0, 0.0])
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
        return mesh

    var vertices: PackedVector3Array = PackedVector3Array([
        Vector3(-QUAD_HALF, 0.0, -QUAD_HALF),
        Vector3(QUAD_HALF, 0.0, -QUAD_HALF),
        Vector3(QUAD_HALF, 0.0, QUAD_HALF),
        Vector3(-QUAD_HALF, 0.0, QUAD_HALF),
    ])
    var bones: PackedInt32Array = PackedInt32Array()
    var weights: PackedFloat32Array = PackedFloat32Array()
    for i: int in vertices.size():
        bones.append_array(PackedInt32Array([bone_index, 0, 0, 0]))
        weights.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
    arrays[Mesh.ARRAY_BONES] = bones
    arrays[Mesh.ARRAY_WEIGHTS] = weights

    if variant.contains("indexed"):
        arrays[Mesh.ARRAY_VERTEX] = vertices
        arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
    else:
        # Unindexed: six vertices, and the bone arrays must match that length.
        var expanded: PackedVector3Array = PackedVector3Array()
        var expanded_bones: PackedInt32Array = PackedInt32Array()
        var expanded_weights: PackedFloat32Array = PackedFloat32Array()
        for index: int in [0, 1, 2, 0, 2, 3]:
            expanded.append(vertices[index])
            expanded_bones.append_array(PackedInt32Array([bone_index, 0, 0, 0]))
            expanded_weights.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
        arrays[Mesh.ARRAY_VERTEX] = expanded
        arrays[Mesh.ARRAY_BONES] = expanded_bones
        arrays[Mesh.ARRAY_WEIGHTS] = expanded_weights

    var vertex_count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
    if variant.contains("uv"):
        var uvs: PackedVector2Array = PackedVector2Array()
        for i: int in vertex_count:
            uvs.append(Vector2(float(i % 2), float((i / 2) % 2)))
        arrays[Mesh.ARRAY_TEX_UV] = uvs

    var format: int = 0
    if variant.contains("custom0"):
        var custom: PackedFloat32Array = PackedFloat32Array()
        custom.resize(vertex_count * 4)
        arrays[Mesh.ARRAY_CUSTOM0] = custom
        format = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT

    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, format)
    return mesh


func _material() -> ShaderMaterial:
    var shader: Shader = Shader.new()
    shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
void vertex() { POINT_SIZE = 12.0; }
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
