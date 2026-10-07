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
                truck.beam_plastic[beam]
            )

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

    _add_bounds(solver, truck)
    _add_wheels(solver, truck)
    _add_steering(solver, truck)
    _configure_engine(solver, truck)
    solver.set_gravity(GRAVITY)
    _add_drag(solver, truck)
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
    var lowest: float = INF
    for node: Vector3 in truck.nodes:
        lowest = minf(lowest, (upright * node).y)
    # **The ground is the higher of the heightfield and whatever the caller says it stands on.**
    # This used to be the heightfield alone, so `origin.y` was read for x and z and thrown away
    # for height — which was harmless while a terrain's objects were barely solid, and is not
    # now. Port Starling's start sits on a quay pad whose top is 0.32 m above the dirt: placed at
    # the dirt the rig began inside the pad, its suspension fully compressed, and shot into the
    # air on every reset. Reported from a window in those words.
    var ground: float = maxf(solver.ground_height_at(origin), origin.y)
    for i: int in truck.nodes.size():
        var placed: Vector3 = upright * truck.nodes[i]
        solver.set_node_position(
            i,
            Vector3(
                origin.x + placed.x,
                ground + clearance + placed.y - lowest,
                origin.z + placed.z
            )
        )
        solver.set_node_velocity(i, Vector3.ZERO)
    for beam: int in solver.beam_count():
        solver.set_beam_rest_length(beam, solver.get_beam_reference_length(beam))
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


static func _add_wheels(solver: RefCounted, truck: TruckParser) -> void:
    for wheel: Dictionary in truck.wheels:
        if (wheel["tread_count"] as int) <= 0:
            continue
        solver.add_wheel(
            wheel["node1"] as int,
            wheel["node2"] as int,
            wheel["first_tread"] as int,
            wheel["tread_count"] as int,
            wheel["arm_node"] as int,
            wheel["tire_radius"] as float,
            wheel["propulsed"] as int,
            wheel["braked"] as int
        )
    solver.set_has_axles(truck.has_axles)
    solver.set_brake_forces(
        truck.drivetrain["brake_force"] as float,
        truck.drivetrain["parking_brake_force"] as float
    )


static func _add_steering(solver: RefCounted, truck: TruckParser) -> void:
    for hydro: Dictionary in truck.hydros:
        solver.add_hydro(hydro["beam"] as int, hydro["factor"] as float)


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
