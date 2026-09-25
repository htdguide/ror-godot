extends GateBase
## ADR 0002 on a real vehicle: does Godot's GPU skinning reproduce FlexBody deformation
## on the hero truck's own body mesh, under poses it will actually see?
##
## The spike proved the identity on a synthetic lattice built to be awkward. This proves
## it on 1860 vertices of a community mesh, bound to the mod's own node rig by upstream's
## own rules, which is the case that has to hold for the bridge to be real.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const MESH: String = "S10bodyshort.mesh"
const PRESET: String = "hero_3q"
const THRESHOLD_MM: float = 1.0
const SETTLE_FRAMES: int = 3
const SABOTAGE_MM: float = 5.0
const MIN_COVERAGE: float = 0.005
## Height above the ground plane to stand the body at, in metres.
const GROUND_CLEARANCE_M: float = 0.4
const SAMPLE_STRIDE: int = 2
## Deformations a truck body really sees: suspension travel, chassis twist over a rut,
## and a hard landing. Amplitudes are larger than reality so the identity is tested where
## it is most likely to break.
const POSES: Array[String] = ["rest", "heave", "twist", "pitch", "crush"]


static func meta() -> Dictionary:
    return {
        "name": "vehicle_skinning",
        "proves": "GPU skinning reproduces FlexBody deformation on a real vehicle mesh within the error threshold",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "max vertex error < %.1f mm in every pose" % THRESHOLD_MM,
        "why": (
            "the synthetic spike proved the algebra survives Godot's pipeline; this"
            + " proves it survives a real mod's geometry, bound by upstream's own"
            + " nearest-node rules rather than a lattice chosen to be well behaved."
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
    # This gate reads numbers back out of pixels, so nothing else may write to the frame:
    # linear tonemapping, black background, no ground.
    harness.use_measurement_environment()

    var truck: TruckParser = TruckParser.new()
    var parse_error: String = truck.parse_file(mod_dir.path_join(TRUCK))
    if parse_error != "":
        return fail(parse_error)

    var entry: Dictionary = _entry_for(truck, MESH)
    if entry.is_empty():
        return fail("%s declares no flexbody for %s" % [TRUCK, MESH])
    var geometry: Dictionary = _geometry(mod_dir, entry, truck)
    if geometry.has("error"):
        return fail(geometry["error"] as String)

    # Before any rendering: at rest the binding must reproduce the mesh exactly. This is
    # pure arithmetic, so a failure here is the binding rather than the GPU, and the
    # distinction is worth one cheap check.
    var round_trip: Dictionary = _binding_round_trip(
        truck.nodes, entry["forset"] as PackedInt32Array,
        geometry["vertices"] as PackedVector3Array
    )
    if float(round_trip["max_mm"]) > THRESHOLD_MM:
        return fail(
            "binding does not round-trip at rest: max %.3f mm over %d vertices (%d triads,"
            % [float(round_trip["max_mm"]), int(round_trip["vertices"]), int(round_trip["triads"])]
            + " %d fell back to node 0). The GPU is not involved." % int(round_trip["fallbacks"]),
            round_trip["max_mm"]
        )

    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = load("res://shaders/flex_error.gdshader") as Shader
    material.set_shader_parameter("threshold_mm", THRESHOLD_MM)

    var skinned: SkinnedFlexbody = SkinnedFlexbody.new()
    var build_error: String = skinned.build(
        harness.world, truck.nodes, entry["forset"] as PackedInt32Array,
        geometry["vertices"] as PackedVector3Array, geometry["indices"] as PackedInt32Array,
        material
    )
    if build_error != "":
        return fail(build_error)
    # Sit the body on the camera's subject point, clear of the ground plane. Centring on
    # the centroid alone buries half of it below the floor, where it renders as a few
    # specks poking through and the coverage check reads almost nothing. Both the skinned
    # result and the reference are in model space, so the instance transform cannot
    # affect the measured error.
    skinned.mesh_instance.position = _standing_offset(geometry["vertices"] as PackedVector3Array)

    var worst_mm: float = 0.0
    var worst_pose: String = "rest"
    for pose: String in POSES:
        var posed: PackedVector3Array = _deform_nodes(pose, truck.nodes)
        skinned.set_pose(posed)
        skinned.set_reference(
            posed, geometry["vertices"] as PackedVector3Array,
            geometry["indices"] as PackedInt32Array
        )
        await harness.advance_frames(SETTLE_FRAMES, "static", "pose_" + pose)
        var shot: Dictionary = await harness.capture_shot("vehicle_skinning/" + pose, "static", 1)
        if shot["error"] != "":
            return fail(shot["error"] as String)
        var measured: Dictionary = _measure(shot["png"] as String)
        if float(measured["coverage"]) < MIN_COVERAGE:
            return fail(
                "pose '%s': only %.3f%% of the frame has geometry; the measurement is"
                % [pose, float(measured["coverage"]) * 100.0]
                + " meaningless. Artifact: %s" % shot["png"]
            )
        if int(measured["over_pixels"]) > 0:
            return fail(
                "pose '%s': %d pixels over %.1f mm; artifact: %s"
                % [pose, int(measured["over_pixels"]), THRESHOLD_MM, shot["png"]],
                measured["max_mm"]
            )
        worst_mm = maxf(worst_mm, float(measured["max_mm"]))
        if float(measured["max_mm"]) >= worst_mm:
            worst_pose = pose

    var control: String = await _negative_control(harness, skinned, truck.nodes)
    skinned.free_resources()
    if control != "":
        return fail(control)
    return ok(
        "%d vertices on %d bones: max error %.4f mm over %d poses (worst '%s')"
        % [skinned.vertex_count, skinned.triads.size(), worst_mm, POSES.size(), worst_pose],
        worst_mm
    )


## Binds at rest and deforms straight back, which must return the original vertices.
func _binding_round_trip(
    nodes: PackedVector3Array, forset: PackedInt32Array, vertices: PackedVector3Array
) -> Dictionary:
    var binding: Dictionary = FlexbodyBinder.bind(nodes, forset, vertices)
    var triads: Array[Vector3i] = binding["triads"] as Array[Vector3i]
    var rebuilt: PackedVector3Array = FlexbodyBinder.reference_positions(nodes, binding, triads)
    var worst: float = 0.0
    for i: int in vertices.size():
        worst = maxf(worst, (rebuilt[i] - vertices[i]).length())
    var fallbacks: int = 0
    for triad: Vector3i in triads:
        if triad.z == FlexbodyBinder.FALLBACK_NODE:
            fallbacks += 1
    return {
        "max_mm": worst * 1000.0,
        "vertices": vertices.size(),
        "triads": triads.size(),
        "fallbacks": fallbacks,
    }


## Offset that centres the mesh horizontally and lifts it clear of the ground.
func _standing_offset(vertices: PackedVector3Array) -> Vector3:
    if vertices.is_empty():
        return Vector3.ZERO
    var box: AABB = AABB(vertices[0], Vector3.ZERO)
    for vertex: Vector3 in vertices:
        box = box.expand(vertex)
    var centre: Vector3 = box.position + box.size * 0.5
    return Vector3(-centre.x, -box.position.y + GROUND_CLEARANCE_M, -centre.z)


func _entry_for(truck: TruckParser, mesh_name: String) -> Dictionary:
    for entry: Dictionary in truck.flexbodies:
        if (entry["mesh"] as String) == mesh_name:
            return entry
    return {}


func _geometry(mod_dir: String, entry: Dictionary, truck: TruckParser) -> Dictionary:
    var reader: RefCounted = ClassDB.instantiate("OgreMeshReader") as RefCounted
    if reader == null:
        return {"error": "OgreMeshReader is not registered"}
    var result: Dictionary = reader.read_file(mod_dir.path_join(entry["mesh"] as String))
    if (result.get("error", "") as String) != "":
        return {"error": result["error"] as String}
    var transform: Transform3D = FlexbodyBinder.placement(truck.nodes, entry)
    var vertices: PackedVector3Array = PackedVector3Array()
    var indices: PackedInt32Array = PackedInt32Array()
    for submesh: Dictionary in result["submeshes"] as Array:
        var offset: int = vertices.size()
        for vertex: Vector3 in submesh["positions"] as PackedVector3Array:
            vertices.append(transform * vertex)
        for index: int in submesh["indices"] as PackedInt32Array:
            indices.append(index + offset)
    if vertices.is_empty():
        return {"error": "%s has no geometry" % entry["mesh"]}
    return {"vertices": vertices, "indices": indices}


## Node displacements a truck body actually sees, exaggerated.
func _deform_nodes(pose: String, rest: PackedVector3Array) -> PackedVector3Array:
    var out: PackedVector3Array = PackedVector3Array()
    out.resize(rest.size())
    for i: int in rest.size():
        var p: Vector3 = rest[i]
        match pose:
            "heave":
                out[i] = p + Vector3(0.0, 0.12, 0.0)
            "twist":
                var angle: float = p.z * 0.12
                out[i] = Vector3(
                    p.x * cos(angle) - p.y * sin(angle), p.x * sin(angle) + p.y * cos(angle), p.z
                )
            "pitch":
                out[i] = p + Vector3(0.0, p.z * 0.09, 0.0)
            "crush":
                out[i] = Vector3(p.x * 1.08, p.y * 0.82, p.z * 1.03)
            _:
                out[i] = p
    return out


func _negative_control(harness: Node, skinned: SkinnedFlexbody, nodes: PackedVector3Array) -> String:
    skinned.set_pose(nodes)
    var broken: Array[Transform3D] = FlexbodyBinder.bone_transforms(nodes, skinned.triads)
    var first: Transform3D = broken[0]
    first.origin += Vector3(SABOTAGE_MM / 1000.0, 0.0, 0.0)
    RenderingServer.skeleton_bone_set_transform(
        skinned.skeleton_rid, 0, first * skinned.bind_inverse[0]
    )
    await harness.advance_frames(SETTLE_FRAMES, "static", "negative_control")
    var shot: Dictionary = await harness.capture_shot("vehicle_skinning/control", "static", 1)
    if shot["error"] != "":
        return shot["error"] as String
    var measured: Dictionary = _measure(shot["png"] as String)
    if int(measured["over_pixels"]) == 0:
        return (
            "negative control failed: a deliberate %.1f mm bone error went undetected,"
            % SABOTAGE_MM
            + " so the measurement proves nothing. Artifact: %s" % shot["png"]
        )
    return ""


func _measure(png_path: String) -> Dictionary:
    var image: Image = Image.load_from_file(png_path)
    if image == null:
        return {"max_mm": 0.0, "over_pixels": 0, "coverage": 0.0}
    image.srgb_to_linear()
    var size: Vector2i = image.get_size()
    var max_ratio: float = 0.0
    var over: int = 0
    var covered: int = 0
    var sampled: int = 0
    for y: int in range(0, size.y, SAMPLE_STRIDE):
        for x: int in range(0, size.x, SAMPLE_STRIDE):
            var pixel: Color = image.get_pixel(x, y)
            sampled += 1
            if pixel.r > 0.5:
                over += 1
            if pixel.b > 0.5:
                covered += 1
            max_ratio = maxf(max_ratio, pixel.g)
    return {
        "max_mm": max_ratio * THRESHOLD_MM,
        "over_pixels": over,
        "coverage": float(covered) / float(maxi(sampled, 1)),
    }
