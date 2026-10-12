class_name RigBuilder
extends RefCounted
## Turns a parsed vehicle into a configured solver.
##
## One place, because everything that needs a running rig needs the same setup and the
## setup is not obvious: masses come from four different rules, tread nodes are exempt from
## most of them, a wheel's drive and brake flags live in its own row, and a steering ram is
## a beam that has to be handed to the solver twice — once as structure and once as an
## actuator. Spread across the callers, one of them always ends up with a rig that is
## subtly not the one the others are testing.

## The cab options that make a triangle one other actors collide with. See `_add_collision_cabs`.
const COLLISION_CAB_OPTIONS: PackedStringArray = ["c", "p", "u", "D", "F", "S"]

## Upstream's SimConstants defaults, for a rig whose beam defaults say nothing.
const DEFAULT_SPRING: float = 9000000.0
const DEFAULT_DAMP: float = 12000.0
const GRAVITY: Vector3 = Vector3(0.0, -9.81, 0.0)
## Upstream's DEFAULT_DRAG: per-node viscous drag against still air, quadratic in speed.
##
## Upstream uses this for every rig that does not declare a `fusedrag` section, and a single
## fuselage drag vector for those that do. The hero truck declares one, so its aerodynamics
## are not yet upstream's — see docs/PLAN.md. Per-node drag is the general case and the one
## worth having first; the fuselage model is a named gap rather than a forgotten one.
const AIR_DRAG: float = 0.05


## Builds the solver for `truck`. `drop_height_m` lifts the rig so its lowest node starts
## that far above the ground; pass 0 to leave it where the file puts it.
## Returns {"error": String, "solver": RefCounted, "masses": PackedFloat32Array}.
static func build(truck: TruckParser, drop_height_m: float = 0.0) -> Dictionary:
    var solver: RefCounted = ClassDB.instantiate("RorSolver") as RefCounted
    if solver == null:
        return {"error": "RorSolver is not registered: the GDExtension did not load", "solver": null}
    if truck.beams.is_empty():
        return {"error": "'%s' has no beams" % truck.name, "solver": null}

    var masses: PackedFloat32Array = NodeMasses.distribute(truck)
    var lift: Vector3 = Vector3.ZERO
    if drop_height_m != 0.0:
        var lowest: float = INF
        for node: Vector3 in truck.nodes:
            lowest = minf(lowest, node.y)
        lift = Vector3(0.0, drop_height_m - lowest, 0.0)
    for i: int in truck.nodes.size():
        solver.add_node(truck.nodes[i] + lift, masses[i])
        if i < truck.node_friction.size():
            solver.set_node_friction(i, truck.node_friction[i])
    for i: int in range(0, truck.beams.size(), 2):
        var beam: int = i / 2
        var spring: float = (
            truck.beam_spring[beam] if beam < truck.beam_spring.size() else DEFAULT_SPRING
        )
        var damp: float = truck.beam_damp[beam] if beam < truck.beam_damp.size() else DEFAULT_DAMP
        solver.add_beam(truck.beams[i], truck.beams[i + 1], 0.0, spring, damp)
        # What bends it and what breaks it, from the defaults in force where the row was written.
        if beam < truck.beam_deform.size():
            solver.set_beam_limits(
                beam, truck.beam_deform[beam], truck.beam_strength[beam],
                truck.beam_plastic[beam],
                beam >= truck.beam_deformable.size() or truck.beam_deformable[beam] != 0
            )
        if beam < truck.beam_table.detacher.size() and truck.beam_table.detacher[beam] != 0:
            solver.set_beam_detacher_group(beam, truck.beam_table.detacher[beam])

    # A strut's hub runs along a rail rather than sitting on a point. Handed over after the beams
    # because the rail is made of nodes the beams have already placed. See `SlideNodeRows`.
    for slide: Dictionary in truck.slide_nodes:
        solver.add_slide_node(
            slide["node"] as int, slide["rail"] as PackedInt32Array,
            slide["spring"] as float, slide["break_force"] as float,
            slide["tolerance"] as float
        )

    # Which nodes a collision triangle is built on: upstream will not break the last beams
    # holding one, because a hole in the cab is worse than a beam that should have snapped.
    for node: int in truck.submeshes.cab_triangles:
        solver.set_node_cab(node, true)
    _add_collision_cabs(solver, truck)

    _add_bounds(solver, truck)
    # Upstream's named inertia curves, which command keys and hydros may ask for.
    if not truck.commands.is_empty() or not truck.hydros.is_empty():
        InertiaModels.hand_to(solver)
    _add_commands(solver, truck)
    _add_wheels(solver, truck)
    for detacher: Dictionary in truck.beam_table.wheel_detachers:
        solver.add_wheel_detacher(detacher["wheel"] as int, detacher["group"] as int)
    _add_steering(solver, truck)
    _configure_engine(solver, truck)
    solver.set_gravity(GRAVITY)
    _add_drag(solver, truck)
    truck.links.build(solver, truck.nodes.size())
    # The rig as built, kept so `place` can put a damaged one back this way. Taken last, after
    # the bounds and the limits have set every strength the file asks for: a snapshot taken
    # earlier would "repair" a rig to a weaker state than it was ever driven in.
    solver.snapshot_undamaged()
    return {"error": "", "solver": solver, "masses": masses}


## The aerodynamics a rig's own file asks for.
##
## Upstream has two models and picks between them by whether the rig declares a `fusedrag`
## section: a fuselage is dragged as one body, and everything else is dragged node by node with
## the turbulent model. They are not close to each other. The hero truck declares a 0.1 m
## fuselage — a negligible drag — and given the per-node model instead it tops out at 63 km/h in
## fourth gear with the throttle on the floor, which is what a session reported.
static func _add_drag(solver: RefCounted, truck: TruckParser) -> void:
    var width: float = _fuselage_width(truck)
    if width > 0.0:
        var front: int = truck.node_ids.find(truck.drivetrain["fuse_front"] as String)
        if front >= 0:
            solver.set_air_drag(AIR_DRAG, false)
            solver.set_fuselage_drag(front, width, true)
            return
    solver.set_air_drag(AIR_DRAG, true)


## The fuselage's width, stated or worked out. Upstream's autocalc form takes the rig's own
## extent in z and y and multiplies by the stated area coefficient, which makes "width" an area
## — its own name for it — and the drag law squares it either way.
static func _fuselage_width(truck: TruckParser) -> float:
    if not (truck.drivetrain["fuse_autocalc"] as bool):
        return truck.drivetrain["fuse_width"] as float
    if truck.nodes.is_empty():
        return 0.0
    var low: Vector3 = truck.nodes[0]
    var high: Vector3 = truck.nodes[0]
    for node: Vector3 in truck.nodes:
        low = low.min(node)
        high = high.max(node)
    return (high.z - low.z) * (high.y - low.y) * (
        truck.drivetrain["fuse_area_coefficient"] as float
    )


## A convenience for the common case: parse a file and build its solver in one step.
## Returns the same dictionary plus "truck".
static func from_file(mod_dir: String, truck_file: String, drop_height_m: float = 0.0) -> Dictionary:
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_file(mod_dir.path_join(truck_file))
    if error != "":
        return {"error": error, "solver": null, "truck": truck}
    var built: Dictionary = build(truck, drop_height_m)
    built["truck"] = truck
    return built


## Travel limits, before anything reads a beam's length: pre-compression changes it.
## Sets a rig down at `origin`, upright, facing `heading` radians, at rest and undeformed.
##
## Rebuilt from the rest shape rather than moved from wherever it was: a soft-body vehicle
## that has been rolled is bent, and turning the wreck the right way up leaves it a wreck.
## Every actuated beam goes back to its reference length too, or a rig recovered mid-turn
## keeps the steering lock that was baked into its rams.
static func place(
    solver: RefCounted, truck: TruckParser, origin: Vector3, heading: float, clearance: float
) -> void:
    # Undamaged first, and this is the part that was missing. Resetting positions and rest
    # lengths undoes a bend but not a break, so a rig put back on its wheels kept every beam it
    # had snapped and shed its doors and wheels again on the next step. Reported from the window:
    # "after pressing R car is resetting but it is broken, doors and wheels fall of".
    solver.repair()
    var upright: Basis = Basis(Vector3.UP, heading)
    # The rig's lowest node that touches ground: upstream leaves `c` nodes out of a spawn's height,
    # and one hanging below the rest would otherwise hold the whole vehicle up off the ground.
    var lowest: float = INF
    for index: int in truck.nodes.size():
        if truck.no_ground_contact.has(index):
            continue
        lowest = minf(lowest, (upright * truck.nodes[index]).y)
    if lowest == INF:
        lowest = 0.0
    # **The ground is the higher of the heightfield and whatever the caller says it stands on.**
    # This used to be the heightfield alone, so `origin.y` was read for x and z and thrown away
    # for height — which was harmless while a terrain's objects were barely solid, and is not
    # now. Port Starling's start sits on a quay pad whose top is 0.32 m above the dirt: placed at
    # the dirt the rig began inside the pad, its suspension fully compressed, and shot into the
    # air on every reset. Reported from a window in those words.
    var ground: float = maxf(solver.ground_height_at(origin), origin.y)
    # **Relative to the rig's own frame, worked out in GDScript's 64-bit floats.** A world
    # position handed over as a Vector3 is rounded to float32 first — 0.24 mm at La Paz's spawn,
    # 7.8 mm at 100 km — and a rig placed with that much error in every node starts out strained
    # and bends 127 beams settling at 100 km. See PLAN §0.12, per-actor frames.
    solver.set_frame_origin(origin.x, origin.z)
    var frame_x: float = solver.frame_origin_x()
    var frame_z: float = solver.frame_origin_z()
    for i: int in truck.nodes.size():
        var placed: Vector3 = upright * truck.nodes[i]
        solver.set_node_local_position(
            i,
            Vector3(
                origin.x - frame_x + placed.x,
                ground + clearance + placed.y - lowest,
                origin.z - frame_z + placed.z
            )
        )
        solver.set_node_velocity(i, Vector3.ZERO)
    for beam: int in solver.beam_count():
        solver.set_beam_rest_length(beam, solver.get_beam_reference_length(beam))
    # Upstream's `resetSlideNodes`, with the nodes back where they belong.
    solver.reset_slide_nodes()
    solver.set_steer_command(0.0)


## Which way a rig is facing, in radians about the vertical, from its own frame.
static func heading_of(positions: PackedVector3Array, camera_nodes: Dictionary) -> float:
    var forward: Vector3 = -ActorFrame.of(positions, camera_nodes).basis.z
    return atan2(forward.x, forward.z)


static func _add_bounds(solver: RefCounted, truck: TruckParser) -> void:
    for entry: Dictionary in truck.bounded_beams:
        solver.set_beam_bounds(
            entry["beam"] as int,
            entry["bound"] as int,
            entry["short_bound"] as float,
            entry["long_bound"] as float,
            entry["bound_spring"] as float,
            entry["bound_damp"] as float,
            entry["precompression"] as float
        )
        var rates: PackedFloat32Array = entry.get("rates", PackedFloat32Array()) as PackedFloat32Array
        if not rates.is_empty():
            solver.set_beam_shock(entry["beam"] as int, rates, bool(entry.get("soft_bump", false)))


static func _add_wheels(solver: RefCounted, truck: TruckParser) -> void:
    # Each built wheel's axle nodes, by the solver's index for it, for the axles to find it by.
    var axle_nodes: Array[Vector2i] = []
    for wheel: Dictionary in truck.wheels:
        if (wheel["tread_count"] as int) <= 0:
            continue
        var index: int = solver.add_wheel(
            wheel["node1"] as int,
            wheel["node2"] as int,
            wheel["first_tread"] as int,
            wheel["tread_count"] as int,
            wheel["arm_node"] as int,
            wheel["tire_radius"] as float,
            wheel["propulsed"] as int,
            wheel["braked"] as int
        )
        if index >= 0:
            axle_nodes.resize(index + 1)
            axle_nodes[index] = Vector2i(wheel["node1"] as int, wheel["node2"] as int)
    solver.set_has_axles(truck.has_axles)
    _add_differentials(solver, truck, axle_nodes)
    solver.set_brake_forces(
        truck.drivetrain["brake_force"] as float,
        truck.drivetrain["parking_brake_force"] as float
    )
    DriveAidSetup.hand_to(solver, truck)


static func _add_steering(solver: RefCounted, truck: TruckParser) -> void:
    for hydro: Dictionary in truck.hydros:
        var before: int = solver.hydro_count()
        solver.add_hydro(hydro["beam"] as int, hydro["factor"] as float)
        # Upstream's `ProcessHydro` gives each hydro its own inertia, by the commands' rule.
        var inertia: Array = CommandRows.key_inertia(hydro)
        if not inertia.is_empty() and solver.hydro_count() > before:
            solver.set_hydro_inertia(solver.hydro_count() - 1, inertia[0] as float, inertia[1] as float,
                    inertia[2] as String, inertia[3] as String)


static func _configure_engine(solver: RefCounted, truck: TruckParser) -> void:
    var drive: Dictionary = truck.drivetrain
    if not bool(drive["has_engine"]):
        return
    solver.configure_engine(
        drive["min_rpm"] as float,
        drive["max_rpm"] as float,
        drive["torque_nm"] as float,
        drive["diff_ratio"] as float,
        drive["reverse_gear"] as float,
        drive["neutral_gear"] as float,
        drive["gears"] as PackedFloat32Array
    )
    var curve: Dictionary = DriveRows.curve_of(drive)
    solver.set_torque_curve(
        curve["rpm"] as PackedFloat32Array, curve["ratio"] as PackedFloat32Array
    )
    # After the curve, because the engine's clutch default depends on its type and the
    # type arrives with the options.
    solver.set_engine_options(
        drive["inertia"] as float,
        drive["type"] as String,
        drive["clutch_force"] as float,
        drive["clutch_time"] as float,
        drive["shift_time"] as float,
        drive["post_shift_time"] as float,
        drive["idle_rpm"] as float,
        drive["stall_rpm"] as float,
        drive["braking_torque"] as float
    )
    # Upstream's `ProcessEngturbo`, after `engoption` as its spawner orders them.
    if drive.has("turbo"):
        var turbo: Dictionary = drive["turbo"]
        solver.set_turbo(turbo["version"], turbo["inertia_factor"], turbo["count"], turbo["params"])


## The cab triangles other vehicles collide with: upstream's `collcabs`, the rows whose options
## say `c` contact, `p` ten times tougher or `u` invulnerable, or their buoyant twins `D`, `F`
## and `S` (ActorSpawner.cpp, the cab section). The rest are drawn and float but are not hit.
static func _add_collision_cabs(solver: RefCounted, truck: TruckParser) -> void:
    var triangles: PackedInt32Array = truck.submeshes.cab_triangles
    var options: PackedStringArray = truck.submeshes.cab_options
    for index: int in options.size():
        var option: String = options[index]
        var collides: bool = false
        for letter: String in COLLISION_CAB_OPTIONS:
            if option.contains(letter):
                collides = true
                break
        if collides:
            solver.add_collision_cab(
                triangles[index * 3], triangles[index * 3 + 1], triangles[index * 3 + 2]
            )
    for node: int in truck.contacters:
        solver.set_node_contact_role(node, true, false)
    for node: int in truck.rim_nodes:
        solver.set_node_contact_role(node, false, true)
    for node: int in truck.no_ground_contact:
        solver.set_node_ground_contact(node, false)
    # Upstream's `nd_tyre_node`: every node a wheel generates except a flexbody wheel's rim, which
    # never collides with its own vehicle. Cinecam nodes are generated too and are not tyres.
    if truck.generated_from >= 0:
        for node: int in range(truck.generated_from, truck.nodes.size()):
            if not truck.rim_nodes.has(node) and not truck.no_ground_contact.has(node):
                solver.set_node_tyre(node)


## The key-driven rams: upstream's `commands`/`commands2`, each row's beam made a ram. The hero's
## doors are four of them, on keys 1 to 4. See `CommandRows` and ror_commands.h.
static func _add_commands(solver: RefCounted, truck: TruckParser) -> void:
    for row: Dictionary in truck.commands:
        solver.add_command(
            row["beam"] as int, row["contract_key"] as int, row["extend_key"] as int,
            row["shorten_rate"] as float, row["lengthen_rate"] as float,
            row["max_contraction"] as float, row["max_extension"] as float,
            row["not_faster"] as bool, row["auto_center"] as bool, row["one_press"] as bool,
            row["one_press_center"] as bool, row["affect_engine"] as float,
            row["needs_engine"] as bool
        )
        # Upstream's option `r`: the ram is a rope, pulling but never pushing.
        if bool(row["rope"]):
            solver.set_beam_bounds(row["beam"] as int, BeamRows.BOUND_ROPE, 0.0, 0.0, 0.0, 0.0, 1.0)
        # Both keys of the row take its inertia, as upstream's `_ProcessKeyInertia` gives them.
        var inertia: Array = CommandRows.key_inertia(row)
        if not inertia.is_empty():
            for key: String in ["contract_key", "extend_key"]:
                solver.set_command_inertia(row[key] as int, inertia[0] as float, inertia[1] as float,
                        inertia[2] as String, inertia[3] as String)


## Upstream's `ProcessAxle`, `ProcessTransferCase` and `ProcessInterAxle`. An axle finds each wheel
## by its two axle nodes, in either order.
static func _add_differentials(solver: RefCounted, truck: TruckParser, axle_nodes: Array[Vector2i]) -> void:
    for row: Dictionary in truck.axles:
        var nodes: Array = row["nodes"] as Array
        # Upstream warns about a wheel it cannot find and keeps the axle on wheel 0, its default, so
        # the axles after it keep their numbers.
        var first: int = maxi(_wheel_on(axle_nodes, nodes[0] as int, nodes[1] as int), 0)
        var second: int = maxi(_wheel_on(axle_nodes, nodes[2] as int, nodes[3] as int), 0)
        solver.add_axle(first, second, row["types"] as String)
    # Upstream spawns the transfer case between the axles and the interaxles: an interaxle between
    # its two axles is then refused.
    for tc: Dictionary in truck.transfer_cases:
        solver.set_transfer_case(tc["a1"] as int, tc["a2"] as int, tc["has_2wd"] as bool,
                tc["has_2wd_lo"] as bool, tc["ratios"] as PackedFloat32Array)
    for row: Dictionary in truck.interaxles:
        solver.add_interaxle(row["a"] as int, row["b"] as int, row["types"] as String)


static func _wheel_on(axle_nodes: Array[Vector2i], a: int, b: int) -> int:
    for i: int in axle_nodes.size():
        if axle_nodes[i] == Vector2i(a, b) or axle_nodes[i] == Vector2i(b, a):
            return i
    return -1


