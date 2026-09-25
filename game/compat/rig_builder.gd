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

    _add_bounds(solver, truck)
    _add_wheels(solver, truck)
    _add_steering(solver, truck)
    _configure_engine(solver, truck)
    solver.set_gravity(GRAVITY)
    solver.set_air_drag(AIR_DRAG, true)
    return {"error": "", "solver": solver, "masses": masses}


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
