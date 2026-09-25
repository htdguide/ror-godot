extends GateBase
## Steering turns the hubs, and the path the rig follows is the one that geometry predicts.
##
## The oracle is Ackermann steering geometry: a vehicle of wheelbase L whose steered hubs sit
## at angle d follows a circle of radius L/tan(d). The hub angle is measured from the axle
## nodes and the radius from the path the rig actually took, so the two sides of the
## comparison come from different parts of the simulation and the prediction is a textbook
## result rather than a number chosen here.
##
## Ackermann assumes tyres that do not slip sideways and a rig that does not lean, and a
## soft-body truck does both, so the bound is loose. What it is tight about is the part that
## was broken: the hubs must move at all, and the rig must turn the way they point. A hydro
## read as a plain beam holds the steering rack rigid, and a rig that cannot steer looks
## exactly like a rig whose steering is merely slow.
##
## The hub angle is the angle *between the two axles*, not either axle's heading in the
## world. Measured against the world, a rig in a turn shows its whole body's yaw on both
## axles at once: the first version of this gate reported a 64 degree steering lock for what
## the path says was 30.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const SUBSTEP_HZ: float = 10000.0
const SETTLE_SECONDS: float = 1.0
## Long enough for the steering ramp to reach the command and for the rig to settle into the
## turn before the path is measured.
const ENTRY_SECONDS: float = 2.5
const MEASURE_SECONDS: float = 1.5
## Low speed keeps the tyre slip angles small, which is the condition Ackermann is stated
## under. Driving the same test flat out measures tyre behaviour, not geometry.
const THROTTLE: float = 0.18
## The steered hubs must turn by at least this much, or the rams are holding the rack.
const MIN_HUB_ANGLE_DEG: float = 2.0
## Measured turn radius against the Ackermann radius for the measured hub angle.
const RADIUS_TOLERANCE: float = 0.35
## Held straight, the heading must stay put. A soft-body rig wanders a little.
const MAX_STRAIGHT_YAW_DEG: float = 5.0


static func meta() -> Dictionary:
    return {
        "name": "rig_steers",
        "proves": "the steering rams turn the hubs and the rig follows the circle that hub angle implies",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "hubs turn at least %.0f deg; measured turn radius within %.0f%% of L/tan(hub"
            % [MIN_HUB_ANGLE_DEG, RADIUS_TOLERANCE * 100.0]
            + " angle); both lock directions turn the matching way; straight holds within"
            + " %.0f deg" % MAX_STRAIGHT_YAW_DEG
        ),
        "why": (
            "Ackermann geometry predicts the turn radius from the wheelbase and the hub"
            + " angle, both of which are measured from the rig rather than assumed. The"
            + " tolerance is loose because the prediction ignores tyre slip and body roll,"
            + " which a soft-body truck has; the parts that are tight are that the hubs move"
            + " and that the rig turns the way they point, which is what a hydro read as an"
            + " ordinary beam gets wrong."
        ),
        "budget_s": 90.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)

    var straight: Dictionary = _run_turn(mod_dir, 0.0)
    if (straight["error"] as String) != "":
        return fail(straight["error"] as String)
    if absf(straight["yaw_deg"] as float) > MAX_STRAIGHT_YAW_DEG:
        return fail(
            "held straight, the rig's heading moved %.1f deg in %.1f s"
            % [straight["yaw_deg"], MEASURE_SECONDS],
            straight["yaw_deg"]
        )

    var worst: float = 0.0
    var report: PackedStringArray = PackedStringArray()
    var wheelbase: float = straight["wheelbase"] as float
    for command: float in [1.0, -1.0]:
        var turn: Dictionary = _run_turn(mod_dir, command)
        if (turn["error"] as String) != "":
            return fail(turn["error"] as String)
        var hub_deg: float = turn["hub_deg"] as float
        var yaw_deg: float = turn["yaw_deg"] as float
        if absf(hub_deg) < MIN_HUB_ANGLE_DEG:
            return fail(
                "at %+.0f lock the steered hubs turned %.2f deg, under the %.1f deg bound:"
                % [command, hub_deg, MIN_HUB_ANGLE_DEG]
                + " the rams are not moving the rack",
                hub_deg
            )
        # Hub angle and heading change must agree in sign, or the rig is turning the other
        # way from the way its wheels point.
        if signf(hub_deg) != signf(yaw_deg):
            return fail(
                "at %+.0f lock the hubs turned %+.2f deg but the heading moved %+.2f deg:"
                % [command, hub_deg, yaw_deg]
                + " the rig is turning against its own steering",
                hub_deg
            )
        var expected: float = (turn["wheelbase"] as float) / tan(absf(deg_to_rad(hub_deg)))
        var measured: float = turn["radius"] as float
        var relative: float = absf(measured - expected) / expected
        if relative > RADIUS_TOLERANCE:
            return fail(
                "at %+.0f lock the rig turned on a %.2f m radius against the %.2f m Ackermann"
                % [command, measured, expected]
                + " radius for a %.2f deg hub angle, off by %.0f%%"
                % [hub_deg, relative * 100.0],
                relative
            )
        worst = maxf(worst, relative)
        report.append(
            "%+.0f lock: hubs %+.2f deg, heading %+.1f deg, radius %.2f m against %.2f m (%.0f%%)"
            % [command, hub_deg, yaw_deg, measured, expected, relative * 100.0]
        )
    return ok(
        "wheelbase %.2f m; straight held within %.1f deg; %s"
        % [wheelbase, absf(straight["yaw_deg"] as float), "; ".join(report)],
        worst
    )


## Drives the rig with `command` held and measures what it did. Returns
## {"error", "hub_deg", "yaw_deg", "radius", "wheelbase"}.
func _run_turn(mod_dir: String, command: float) -> Dictionary:
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.02)
    if (rig["error"] as String) != "":
        return {"error": rig["error"]}
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    if solver.hydro_count() == 0:
        return {"error": "%s declares no hydros: it has no steering to test" % TRUCK}
    if truck.wheels.size() < 4:
        return {"error": "%s has %d wheels, expected 4" % [TRUCK, truck.wheels.size()]}
    solver.set_ground(0.0, true)

    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    for _i: int in int(SETTLE_SECONDS * 60.0):
        solver.step(dt, chunk)
    var rest_angle: float = _steer_angle(solver, truck)
    var wheelbase: float = _wheelbase(solver, truck)

    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(THROTTLE)
    solver.set_steer_command(command)
    for _i: int in int(ENTRY_SECONDS * 60.0):
        solver.step(dt, chunk)
    if not is_finite(solver.get_node_position(0).length()):
        return {"error": "the solver diverged entering a %+.0f lock turn" % command}

    var entry: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
    var hub: float = wrapf(_steer_angle(solver, truck) - rest_angle, -PI, PI)
    var path: float = 0.0
    var previous: Vector3 = entry.origin
    for _i: int in int(MEASURE_SECONDS * 60.0):
        solver.step(dt, chunk)
        var here: Vector3 = ActorFrame.of(solver.get_positions(), truck.camera_nodes).origin
        path += Vector3(here.x - previous.x, 0.0, here.z - previous.z).length()
        previous = here
    var exit: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)

    var yaw: float = _heading_change(entry, exit)
    return {
        "error": "",
        "hub_deg": rad_to_deg(hub),
        "yaw_deg": rad_to_deg(yaw),
        "radius": path / absf(yaw) if absf(yaw) > 0.0001 else INF,
        "wheelbase": wheelbase,
    }


## The angle between the front and rear axles, in radians.
##
## Both axles are measured in the world and then subtracted, which removes the rig's own
## heading: whatever the body is doing, it does it to both axles equally, and what is left
## is the steering. Averaging the two wheels of an axle averages out a single bent hub.
func _steer_angle(solver: RefCounted, truck: TruckParser) -> float:
    return wrapf(_axle_heading(solver, truck, 0, 1) - _axle_heading(solver, truck, 2, 3), -PI, PI)


func _axle_heading(solver: RefCounted, truck: TruckParser, left: int, right: int) -> float:
    var sum: Vector3 = Vector3.ZERO
    for index: int in [left, right]:
        var wheel: Dictionary = truck.wheels[index]
        var a: Vector3 = solver.get_node_position(wheel["node1"] as int)
        var b: Vector3 = solver.get_node_position(wheel["node2"] as int)
        # Both axles point the same way once the axle nodes are ordered, so summing the
        # vectors before taking an angle cannot cancel them.
        sum += Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
    return atan2(sum.z, sum.x)


func _wheelbase(solver: RefCounted, truck: TruckParser) -> float:
    var front: Vector3 = _axle_centre(solver, truck, 0, 1)
    var rear: Vector3 = _axle_centre(solver, truck, 2, 3)
    return Vector3(front.x - rear.x, 0.0, front.z - rear.z).length()


func _axle_centre(solver: RefCounted, truck: TruckParser, left: int, right: int) -> Vector3:
    var sum: Vector3 = Vector3.ZERO
    for index: int in [left, right]:
        var wheel: Dictionary = truck.wheels[index]
        sum += solver.get_node_position(wheel["node1"] as int)
        sum += solver.get_node_position(wheel["node2"] as int)
    return sum / 4.0


## Signed change in the rig's horizontal heading between two frames.
func _heading_change(from: Transform3D, to: Transform3D) -> float:
    var a: Vector3 = -from.basis.z
    var b: Vector3 = -to.basis.z
    return wrapf(atan2(b.z, b.x) - atan2(a.z, a.x), -PI, PI)
