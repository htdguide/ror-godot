extends GateBase
## The vehicle's parts must sit where its rig says they sit.
##
## This exists because the eye cannot tell a correctly assembled truck from one whose
## parts share a consistent error, and a whole-vehicle transform mistake looks exactly
## like that. It is also what makes it safe to change how the vehicle is placed: the frame
## can move between the root, the bones and the wheel transforms, and this still holds.
##
## The check is deliberately relative. Vectors from a body vertex to each wheel centre are
## compared against the same vectors computed from the rig's own node positions, so the
## result is independent of where the vehicle is put for the camera, and a rotation
## applied to only part of the vehicle shows up immediately.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const PRESET: String = "diag_topdown"
## Radius, in pixels, searched around a projected position for the vehicle's own colour.
## Generous enough to absorb projection rounding and a point's own size, far tighter than
## the distances a misplaced part travels.
const PIXEL_SEARCH_RADIUS: int = 14
## Millimetres for part vertices. Wheels are checked against their axle midpoint through
## the geometry that is actually drawn, and a rim mesh is not perfectly centred on its
## axle, so wheels get their own looser bound: this is about catching a part in the wrong
## place, not about modelling accuracy.
const TOLERANCE_MM: float = 1.0
const WHEEL_TOLERANCE_MM: float = 120.0
const SAMPLE_VERTICES: int = 16


static func meta() -> Dictionary:
    return {
        "name": "vehicle_assembly",
        "proves": "every rendered part sits where the vehicle's own rig places it",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "part offsets within %.1f mm, wheel geometry within %.0f mm of its axle" % [TOLERANCE_MM, WHEEL_TOLERANCE_MM],
        "why": (
            "a transform mistake applied to a whole vehicle moves every part together"
            + " and looks perfectly correct. Comparing part offsets against the rig's own"
            + " node offsets is what separates 'assembled' from 'assembled somewhere else'."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


## Paints the whole vehicle one unambiguous colour, so a sampled pixel answers "is the
## vehicle here" without having to tell dark paint from a dark floor tile.
const MARKER_COLOUR: Color = Color(1.0, 0.0, 1.0)


func _paint(vehicle: Node3D, only_wheels: bool) -> void:
    var shader: Shader = Shader.new()
    shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
uniform vec3 marker = vec3(1.0, 0.0, 1.0);
void fragment() { ALBEDO = marker; }
"""
    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter(
        "marker", Vector3(MARKER_COLOUR.r, MARKER_COLOUR.g, MARKER_COLOUR.b)
    )
    for node: Node in _descendants(vehicle):
        var mesh_instance: MeshInstance3D = node as MeshInstance3D
        if mesh_instance == null:
            continue
        var is_wheel: bool = _under_wheel(mesh_instance)
        mesh_instance.visible = is_wheel or not only_wheels
        mesh_instance.material_override = material


func _under_wheel(node: Node) -> bool:
    var walk: Node = node
    while walk != null:
        if str(walk.name).begins_with("Wheel_"):
            return true
        walk = walk.get_parent()
    return false


func _descendants(node: Node) -> Array[Node]:
    var out: Array[Node] = []
    for child: Node in node.get_children():
        out.append(child)
        out.append_array(_descendants(child))
    return out


## Projects each wheel's axle midpoint and requires the vehicle to be rendered there.
func _check_rendered_positions(
    harness: Node,
    vehicle: Node3D,
    truck: TruckParser,
    rig_to_local: Transform3D,
    parts: Array[SkinnedFlexbody]
) -> String:
    _paint(vehicle, true)
    # Centre the wheels under the camera. The transform checks above deliberately place
    # the vehicle somewhere arbitrary to prove they do not depend on it; this pass reads
    # pixels, so anything outside the frame would read as a missing part.
    var centre: Vector3 = Vector3.ZERO
    var count: int = 0
    for wheel: Dictionary in truck.wheels:
        centre += (
            truck.nodes[wheel["node1"] as int] + truck.nodes[wheel["node2"] as int]
        ) * 0.5
        count += 1
    if count > 0:
        centre /= float(count)
        vehicle.position -= vehicle.global_transform * (rig_to_local * centre)

    var shot: Dictionary = await harness.capture_shot("vehicle_assembly", "static", 4)
    if shot["error"] != "":
        return shot["error"] as String
    var image: Image = Image.load_from_file(shot["png"] as String)
    if image == null:
        return "cannot read %s" % shot["png"]

    var camera: Camera3D = harness.camera
    var missing: PackedStringArray = PackedStringArray()
    var index: int = 0
    for child: Node in vehicle.get_children():
        if not str(child.name).begins_with("Wheel_"):
            continue
        var wheel: Dictionary = truck.wheels[index]
        index += 1
        var axle_mid: Vector3 = (
            truck.nodes[wheel["node1"] as int] + truck.nodes[wheel["node2"] as int]
        ) * 0.5
        # Rig coordinates into the world, through the mapping the builder declares.
        var world: Vector3 = vehicle.global_transform * (rig_to_local * axle_mid)
        if camera.is_position_behind(world):
            continue
        if not _marker_near(image, camera.unproject_position(world)):
            missing.append("%s at %s" % [child.name, world])
    if missing.size() > 0:
        return (
            "no vehicle rendered where the rig puts %d of %d wheels (%s); artifact: %s"
            % [missing.size(), index, ", ".join(missing), shot["png"]]
        )

    # Same question of the body. Checking only the wheels would miss the case where the
    # wheels are right and the body is somewhere else, which looks identical in a still.
    _paint(vehicle, false)
    for node: Node in _descendants(vehicle):
        var mesh_instance: MeshInstance3D = node as MeshInstance3D
        if mesh_instance != null:
            mesh_instance.visible = not _under_wheel(mesh_instance)
    var body_shot: Dictionary = await harness.capture_shot("vehicle_assembly_body", "static", 4)
    if body_shot["error"] != "":
        return body_shot["error"] as String
    var body_image: Image = Image.load_from_file(body_shot["png"] as String)
    if body_image == null:
        return "cannot read %s" % body_shot["png"]

    var body_missing: int = 0
    var body_checked: int = 0
    var first_missing: String = ""
    for part: SkinnedFlexbody in parts:
        var step: int = maxi(part.vertex_count / 8, 1)
        for i: int in range(0, part.vertex_count, step):
            var world: Vector3 = vehicle.global_transform * (
                rig_to_local * part.rest_vertices[i]
            )
            if camera.is_position_behind(world):
                continue
            body_checked += 1
            if not _marker_near(body_image, camera.unproject_position(world)):
                body_missing += 1
                if first_missing == "":
                    first_missing = "%s vertex %d at %s" % [part.mesh_instance.name, i, world]
    if body_missing > 0:
        return (
            "no vehicle rendered where the rig puts %d of %d sampled body vertices"
            % [body_missing, body_checked]
            + " (first: %s); artifact: %s" % [first_missing, body_shot["png"]]
        )
    return ""


func _marker_near(image: Image, at: Vector2) -> bool:
    var size: Vector2i = image.get_size()
    for dy: int in range(-PIXEL_SEARCH_RADIUS, PIXEL_SEARCH_RADIUS + 1):
        for dx: int in range(-PIXEL_SEARCH_RADIUS, PIXEL_SEARCH_RADIUS + 1):
            var x: int = int(at.x) + dx
            var y: int = int(at.y) + dy
            if x < 0 or y < 0 or x >= size.x or y >= size.y:
                continue
            var pixel: Color = image.get_pixel(x, y)
            if pixel.r > 0.5 and pixel.b > 0.5 and pixel.g < 0.4:
                return true
    return false


func run(harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)

    var result: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (result.get("error", "") as String) != "":
        return fail(result["error"] as String)
    var vehicle: Node3D = result["root"] as Node3D
    harness.world.add_child(vehicle)
    # Somewhere arbitrary, to prove the check does not depend on where the vehicle is.
    vehicle.position += Vector3(3.0, 1.0, -2.0)

    var truck: TruckParser = result["truck"] as TruckParser
    var parts: Array[SkinnedFlexbody] = result["parts"] as Array[SkinnedFlexbody]
    if parts.is_empty():
        return fail("no skinned parts were built")

    var reference: SkinnedFlexbody = parts[0]
    var reference_world: Vector3 = reference.rendered_position(0)
    var reference_rig: Vector3 = reference.rest_vertices[0]

    var worst_mm: float = 0.0
    var worst_what: String = ""
    var worst_wheel_mm: float = 0.0
    var worst_wheel_what: String = ""

    # Every other part's vertices must keep their rig-space offsets from that reference.
    for part: SkinnedFlexbody in parts:
        var step: int = maxi(part.vertex_count / SAMPLE_VERTICES, 1)
        for i: int in range(0, part.vertex_count, step):
            var rendered_offset: Vector3 = part.rendered_position(i) - reference_world
            var rig_offset: Vector3 = part.rest_vertices[i] - reference_rig
            var error_mm: float = (rendered_offset - rig_offset).length() * 1000.0
            if error_mm > worst_mm:
                worst_mm = error_mm
                worst_what = "%s vertex %d" % [part.mesh_instance.name, i]

    # And every wheel must sit at the midpoint of its own axle nodes.
    var wheel_index: int = 0
    for child: Node in vehicle.get_children():
        if not str(child.name).begins_with("Wheel_"):
            continue
        var wheel: Dictionary = truck.wheels[wheel_index]
        wheel_index += 1
        var axle_mid: Vector3 = (
            truck.nodes[wheel["node1"] as int] + truck.nodes[wheel["node2"] as int]
        ) * 0.5
        var rig_offset: Vector3 = axle_mid - reference_rig
        # The holder's own origin is not enough: the tyre and rim are children carrying
        # their own transforms, and a wheel can have a correctly placed holder whose
        # geometry renders somewhere else entirely. Check what is actually drawn.
        for drawn: Node in child.get_children():
            var mesh_instance: MeshInstance3D = drawn as MeshInstance3D
            if mesh_instance == null or mesh_instance.mesh == null:
                continue
            var world: AABB = mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
            var rendered_offset: Vector3 = world.get_center() - reference_world
            var error_mm: float = (rendered_offset - rig_offset).length() * 1000.0
            if error_mm > worst_wheel_mm:
                worst_wheel_mm = error_mm
                worst_wheel_what = "%s/%s" % [child.name, mesh_instance.name]

    # Everything above compares transforms against transforms, which cannot catch the
    # renderer disagreeing with that model. This reads the rendered image: each wheel's
    # axle midpoint is projected to screen, and the vehicle's own colour must be there.
    var pixel_check: String = await _check_rendered_positions(
        harness, vehicle, truck, result["rig_to_local"] as Transform3D, parts
    )
    if pixel_check != "":
        return fail(pixel_check)

    if worst_wheel_mm > WHEEL_TOLERANCE_MM:
        return fail(
            "%s renders %.0f mm from its axle, over %.0f mm: the wheel geometry is not"
            % [worst_wheel_what, worst_wheel_mm, WHEEL_TOLERANCE_MM]
            + " where its own axle nodes put it",
            worst_wheel_mm
        )
    if worst_mm > TOLERANCE_MM:
        return fail(
            "%s sits %.1f mm from where the rig puts it, over %.1f mm: the vehicle is"
            % [worst_what, worst_mm, TOLERANCE_MM]
            + " assembled, but not where its own rig says",
            worst_mm
        )
    return ok(
        "%d parts within %.3f mm and %d wheels within %.0f mm of their rig positions"
        % [parts.size(), worst_mm, wheel_index, worst_wheel_mm],
        worst_mm
    )
