extends GateBase
## A vehicle's differentials are the ones its file names, or upstream's automatic ones when it names
## none, and they behave as their kind: a split axle lets its wheels roll apart in a turn, a locked
## one holds them together.
##
## Upstream's `Actor::CalcDifferentials` hands every driven wheel an equal share of the engine's
## torque and then runs it through differentials: one between each pair of axles, one between each
## axle's two wheels. This project did the equal share and stopped, which is exact for a split
## differential and nothing else; a rig with no `axles` section gets viscous ones upstream, and the
## hero's axles are `d(sl)` — split, switchable to locked — with a locked one built between them.
##
## Two oracles. The build is upstream's `ActorSpawner` rules: the hero's two `axles` rows have to
## make two split wheel differentials and one locked axle differential; a rig naming no axles (the
## '49 Ford, four wheels, two driven) has to get one viscous wheel differential and no axle one.
## The behaviour is geometry: driving the hero round a full-lock circle, a split axle's wheels roll
## freely, so the outer rear wheel's tread has to travel further than the inner one's by the rear
## track times the heading change. Locked, the axle is a torsion spring of 10^6 per metre of tread
## (upstream's rate) that no tyre can wind up past its grip: a wheel's whole share of the rig's
## weight at a friction coefficient of 1, times its radius, is under 3 kN·m, so the two wheels can
## differ by under 3 mm. The bound is 1 cm.
##
## And the lock between the axles binds. Turning, the front axle rolls a longer circle than the rear
## (by sqrt(1 + (wheelbase / radius)^2), some 15% at full lock), and a locked coupling forces the two
## to roll the same: the tyres scrub and the rig runs wide. So the hero's full-lock circle has to
## be wider with the coupling than with it removed. `rig_steers` measures steering with it removed.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const FORD_DIR: String = "assets/mods/49ford"
const FORD: String = "49ford.truck"
const SUBSTEP_HZ: float = 2000.0
const SETTLE_SECONDS: float = 1.0
const ENTRY_SECONDS: float = 2.0
const MEASURE_SECONDS: float = 3.0
const THROTTLE: float = 0.18
const SPLIT_TOLERANCE: float = 0.25
const LOCKED_BOUND_M: float = 0.01
## The hero's rear wheels, by the solver's index: rows 3 and 4 of its `meshwheels2`.
const REAR_LEFT: int = 2
const REAR_RIGHT: int = 3


static func meta() -> Dictionary:
    return {
        "name": "a_differential_shares_torque_by_its_kind",
        "proves": "a vehicle gets the differentials its file names or upstream's automatic ones, a split axle's wheels roll apart by track times heading change in a turn, and a locked axle's stay together",
        "builds_on": ["rig_steers"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "hero 2 split wheel and 1 locked axle differentials, '49 Ford 1 viscous and 0; axles"
            + " locked together turn wider than free; split"
            + " rear wheels differ by track x heading within %.0f%%, locked by under %.0f cm"
            % [SPLIT_TOLERANCE * 100.0, LOCKED_BOUND_M * 100.0]
        ),
        "why": (
            "every axle and the automatic differentials of every rig with none were missing: all"
            + " drive torque was split evenly, so a locked axle could not lock and a rig with no"
            + " axles lacked the viscous coupling upstream gives it."
        ),
        "budget_s": 90.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var built: String = _check_build(mod_dir)
    if built != "":
        return fail(built)

    var split: Dictionary = _turn(mod_dir, false, false)
    if (split["error"] as String) != "":
        return fail(split["error"] as String)
    var locked: Dictionary = _turn(mod_dir, true, false)
    if (locked["error"] as String) != "":
        return fail(locked["error"] as String)
    var expected: float = (split["track"] as float) * absf(split["yaw"] as float)
    var apart: float = absf(split["apart"] as float)
    if absf(apart - expected) > expected * SPLIT_TOLERANCE:
        return fail(
            "split, the rear wheels rolled %.3f m apart in a %.1f deg turn; track %.3f m says %.3f"
            % [apart, rad_to_deg(absf(split["yaw"] as float)), split["track"], expected], apart)
    var held: float = absf(locked["apart"] as float)
    if held > LOCKED_BOUND_M:
        return fail(
            "locked, the rear wheels rolled %.4f m apart in a %.1f deg turn, over %.2f m"
            % [held, rad_to_deg(absf(locked["yaw"] as float)), LOCKED_BOUND_M], held)
    var free: Dictionary = _turn(mod_dir, false, true)
    if (free["error"] as String) != "":
        return fail(free["error"] as String)
    if (split["radius"] as float) <= (free["radius"] as float):
        return fail("with its axles locked together the hero turned on %.2f m, not wider than %.2f m free"
                % [split["radius"], free["radius"]], split["radius"])
    return ok(
        "axles locked together turn %.2f m against %.2f m free; " % [split["radius"], free["radius"]] +
        "hero split rear wheels %.3f m apart against %.3f (track %.3f m, %.1f deg); locked %.4f m"
        % [apart, expected, split["track"], rad_to_deg(absf(split["yaw"] as float)), held]
        + " in %.1f deg" % rad_to_deg(absf(locked["yaw"] as float)),
        held
    )


## The hero's and the '49 Ford's differentials against upstream's build rules. "" when they match.
func _check_build(mod_dir: String) -> String:
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        return rig["error"] as String
    var solver: RefCounted = rig["solver"] as RefCounted
    var hero: String = "%d %s%s, %d %s" % [
        solver.wheel_differential_count(), solver.wheel_differential_type(0),
        solver.wheel_differential_type(1), solver.axle_differential_count(), solver.axle_differential_type(0)]
    if hero != "2 ss, 1 l":
        return "the hero's differentials are %s, not 2 ss, 1 l (two split axles, one locked between)" % hero
    var ford_dir: String = SourceScan.repo_root().path_join(FORD_DIR)
    if not DirAccess.dir_exists_absolute(ford_dir):
        return ""
    var ford: Dictionary = RigBuilder.from_file(ford_dir, FORD, 0.0)
    if (ford["error"] as String) != "":
        return ford["error"] as String
    var other: RefCounted = ford["solver"] as RefCounted
    var got: String = "%d %s, %d" % [
        other.wheel_differential_count(), other.wheel_differential_type(0), other.axle_differential_count()]
    if got != "1 v, 0":
        return "the '49 Ford, naming no axles, has differentials %s, not 1 v, 0 (one viscous)" % got
    return ""


## Drives the hero round a full-lock circle and measures how far its rear wheels' treads rolled
## apart, and on what radius it turned. `free_axles` removes the lock between its axles. Returns
## {error, apart, yaw, track, radius}.
func _turn(mod_dir: String, lock: bool, free_axles: bool) -> Dictionary:
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.02)
    if (rig["error"] as String) != "":
        return {"error": rig["error"]}
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_ground(0.0, true)
    if free_axles:
        solver.clear_axle_differentials()
    if lock:
        solver.toggle_wheel_differentials()
        if solver.wheel_differential_type(1) != "l":
            return {"error": "toggled, the hero's rear axle is %s, not locked" % solver.wheel_differential_type(1)}
    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    for _i: int in int(SETTLE_SECONDS * 60.0):
        solver.step(dt, chunk)
    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(THROTTLE)
    solver.set_steer_command(DriveCfg.steer_command(1.0))
    for _i: int in int(ENTRY_SECONDS * 60.0):
        solver.step(dt, chunk)
    var entry: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
    var start: float = _apart(solver, truck)
    var path: float = 0.0
    var previous: Vector3 = entry.origin
    for _i: int in int(MEASURE_SECONDS * 60.0):
        solver.step(dt, chunk)
        var here: Vector3 = ActorFrame.of(solver.get_positions(), truck.camera_nodes).origin
        path += Vector3(here.x - previous.x, 0.0, here.z - previous.z).length()
        previous = here
    if not is_finite(solver.get_node_position(0).length()):
        return {"error": "the solver diverged in the turn"}
    var exit: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
    var a: Vector3 = -entry.basis.z
    var b: Vector3 = -exit.basis.z
    var yaw: float = wrapf(atan2(b.z, b.x) - atan2(a.z, a.x), -PI, PI)
    return {
        "error": "",
        "apart": _apart(solver, truck) - start,
        "yaw": yaw,
        "radius": path / absf(yaw) if absf(yaw) > 0.0001 else INF,
        "track": _track(solver, truck),
    }


## How much further the rear left tread has rolled than the rear right, metres: the solver keeps
## rotation as tread travel over the row's radius.
func _apart(solver: RefCounted, truck: TruckParser) -> float:
    return solver.get_wheel_rotation(REAR_LEFT) * (truck.wheels[REAR_LEFT]["tire_radius"] as float) \
            - solver.get_wheel_rotation(REAR_RIGHT) * (truck.wheels[REAR_RIGHT]["tire_radius"] as float)


## Distance between the rear wheels' centres, each the middle of its two axle nodes.
func _track(solver: RefCounted, truck: TruckParser) -> float:
    var centres: Array[Vector3] = []
    for index: int in [REAR_LEFT, REAR_RIGHT]:
        var wheel: Dictionary = truck.wheels[index]
        centres.append((solver.get_node_position(wheel["node1"] as int)
                + solver.get_node_position(wheel["node2"] as int)) * 0.5)
    var d: Vector3 = centres[0] - centres[1]
    return Vector3(d.x, 0.0, d.z).length()
