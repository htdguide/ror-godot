extends GateBase
## Finds the point where real vehicle data stops being skinned.
##
## The class skins synthetic data under the vehicle's own frame, and every mesh property
## works in isolation, yet all seventeen real parts draw as though unskinned. The only
## remaining difference is the data: thousands of vertices and hundreds of triads instead
## of a handful. This takes the real body mesh and feeds progressively more of it through
## the same class, comparing silhouettes of an object kept fully in frame.
##
## Silhouettes, and fully in frame, both on purpose: comparing a centroid of visible pixels
## against a projection of all geometry is only valid when nothing is cut off, and getting
## that wrong has already produced two false results in this investigation.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const MESH: String = "S10bodyshort.mesh"
const PRESET: String = "diag_topdown"
const YAW_DEGREES: float = 90.0
const ACTOR_ORIGIN: Vector3 = Vector3(-0.85, 0.18, -0.36)
const FRACTIONS: Array[float] = [0.01, 0.05, 0.25, 0.5, 1.0]
const SETTLE_FRAMES: int = 3
const TOLERANCE_PX: float = 30.0


static func meta() -> Dictionary:
    return {
        "name": "skinned_scale_bisect",
        "proves": "how much real vehicle geometry can be skinned under a frame before it stops working",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "drawn silhouette within %.0f px of the projected geometry at every size" % TOLERANCE_PX,
        "why": (
            "everything else is eliminated: composition, rotation, mesh properties and the"
            + " class itself. If real data fails where synthetic data of the same shape"
            + " succeeds, the size at which it starts failing is the remaining clue."
        ),
        "budget_s": 180.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)

    var truck: TruckParser = TruckParser.new()
    var parse_error: String = truck.parse_file(mod_dir.path_join(TRUCK))
    if parse_error != "":
        return fail(parse_error)
    var entry: Dictionary = {}
    for candidate: Dictionary in truck.flexbodies:
        if (candidate["mesh"] as String) == MESH:
            entry = candidate
    if entry.is_empty():
        return fail("%s declares no flexbody for %s" % [TRUCK, MESH])

    var reader: RefCounted = ClassDB.instantiate("OgreMeshReader") as RefCounted
    var result: Dictionary = reader.read_file(mod_dir.path_join(MESH))
    if (result.get("error", "") as String) != "":
        return fail(result["error"] as String)
    var placement: Transform3D = FlexbodyBinder.placement(truck.nodes, entry)
    var all_vertices: PackedVector3Array = PackedVector3Array()
    var all_indices: PackedInt32Array = PackedInt32Array()
    var all_uvs: PackedVector2Array = PackedVector2Array()
    for submesh: Dictionary in result["submeshes"] as Array:
        var offset: int = all_vertices.size()
        var positions: PackedVector3Array = submesh["positions"] as PackedVector3Array
        for vertex: Vector3 in positions:
            all_vertices.append(placement * vertex)
        for index: int in submesh["indices"] as PackedInt32Array:
            all_indices.append(index + offset)
        # The builder supplies UVs, so this test does too: it is the last property that
        # differs between this passing case and the failing vehicle.
        var submesh_uvs: PackedVector2Array = submesh["uvs"] as PackedVector2Array
        for i: int in positions.size():
            all_uvs.append(submesh_uvs[i] if i < submesh_uvs.size() else Vector2.ZERO)

    var actor: Transform3D = Transform3D(Basis(Vector3.UP, deg_to_rad(YAW_DEGREES)), ACTOR_ORIGIN)
    var report: PackedStringArray = PackedStringArray()
    var first_failure: String = ""
    for fraction: float in FRACTIONS:
        var outcome: Dictionary = await _test_fraction(
            harness, truck, entry, actor, all_vertices, all_indices, all_uvs, fraction
        )
        report.append("%d%%: %s" % [int(fraction * 100.0), outcome["detail"]])
        if not bool(outcome["ok"]) and first_failure == "":
            first_failure = "%d%%" % int(fraction * 100.0)

    if first_failure != "":
        return fail(
            "real geometry stops being skinned at %s of the mesh (%s)"
            % [first_failure, ", ".join(report)],
            first_failure
        )
    return ok("real geometry skins at every size (%s)" % ", ".join(report), 0)


func _test_fraction(
    harness: Node,
    truck: TruckParser,
    entry: Dictionary,
    actor: Transform3D,
    all_vertices: PackedVector3Array,
    all_indices: PackedInt32Array,
    all_uvs: PackedVector2Array,
    fraction: float
) -> Dictionary:
    var keep: int = maxi(int(float(all_vertices.size()) * fraction), 3)
    var vertices: PackedVector3Array = all_vertices.slice(0, keep)
    var indices: PackedInt32Array = PackedInt32Array()
    for i: int in range(0, all_indices.size(), 3):
        if all_indices[i] < keep and all_indices[i + 1] < keep and all_indices[i + 2] < keep:
            indices.append_array(
                PackedInt32Array([all_indices[i], all_indices[i + 1], all_indices[i + 2]])
            )
    if indices.is_empty():
        return {"ok": true, "detail": "no whole triangles at this size, skipped"}

    var root: Node3D = Node3D.new()
    root.transform = actor
    harness.world.add_child(root)
    var part: SkinnedFlexbody = SkinnedFlexbody.new()
    var error: String = part.build(
        root, truck.nodes, entry["forset"] as PackedInt32Array, vertices, indices,
        _material(), all_uvs.slice(0, keep)
    )
    if error != "":
        root.queue_free()
        return {"ok": false, "detail": "build failed: %s" % error}
    part.set_pose(truck.nodes, actor, false)

    # Keep the whole thing in frame: place it at the camera's subject point.
    var centre: Vector3 = Vector3.ZERO
    for vertex: Vector3 in vertices:
        centre += vertex
    centre /= float(vertices.size())
    root.position -= root.global_transform * (actor.affine_inverse() * centre)

    await harness.advance_frames(SETTLE_FRAMES, "static", "fraction_%d" % int(fraction * 100.0))
    var shot: Dictionary = await harness.capture_shot(
        "scale_bisect/%d" % int(fraction * 100.0), "static", 1
    )
    var outcome: Dictionary = {"ok": false, "detail": "no capture"}
    if shot["error"] == "":
        outcome = _compare(harness, part, vertices, actor, shot["png"] as String)
    part.free_resources()
    root.queue_free()
    return outcome


func _compare(
    harness: Node,
    part: SkinnedFlexbody,
    vertices: PackedVector3Array,
    actor: Transform3D,
    png_path: String
) -> Dictionary:
    var image: Image = Image.load_from_file(png_path)
    if image == null:
        return {"ok": false, "detail": "cannot read capture"}
    var camera: Camera3D = harness.camera
    var root: Node3D = part.mesh_instance.get_parent() as Node3D
    var expected_min: Vector2 = Vector2(INF, INF)
    var expected_max: Vector2 = Vector2(-INF, -INF)
    for vertex: Vector3 in vertices:
        var world: Vector3 = root.global_transform * (actor.affine_inverse() * vertex)
        if camera.is_position_behind(world):
            return {"ok": true, "detail": "behind the camera, skipped"}
        var screen: Vector2 = camera.unproject_position(world)
        expected_min = expected_min.min(screen)
        expected_max = expected_max.max(screen)

    var drawn_min: Vector2 = Vector2(INF, INF)
    var drawn_max: Vector2 = Vector2(-INF, -INF)
    var size: Vector2i = image.get_size()
    for y: int in range(0, size.y, 2):
        for x: int in range(0, size.x, 2):
            var pixel: Color = image.get_pixel(x, y)
            if pixel.b > 0.5 and pixel.r < 0.3 and pixel.g < 0.3:
                drawn_min = drawn_min.min(Vector2(float(x), float(y)))
                drawn_max = drawn_max.max(Vector2(float(x), float(y)))
    if drawn_min.x == INF:
        return {"ok": false, "detail": "nothing drawn"}
    if drawn_min.x <= 2.0 or drawn_min.y <= 2.0 or drawn_max.x >= float(size.x - 3) or drawn_max.y >= float(size.y - 3):
        return {"ok": true, "detail": "touches the frame edge, skipped"}

    var centre_error: float = (
        (drawn_min + drawn_max) * 0.5 - (expected_min + expected_max) * 0.5
    ).length()
    if centre_error > TOLERANCE_PX:
        return {"ok": false, "detail": "drawn %.0f px away" % centre_error}
    return {"ok": true, "detail": "skinned (%.0f px)" % centre_error}


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
