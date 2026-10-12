extends GateBase
## Cruise control is upstream's (gameplay/CruiseControl.cpp), which every vehicle with an engine
## has; a `cruisecontrol` line only sets the lowest speed it will hold and whether it may brake.
##
## Ours had none: 28 corpus files state the line, and no vehicle could hold a speed.
##
## The oracle is upstream's code read rule by rule, on the hero truck on flat ground:
## - switched on, it holds the smoothed wheel speed (`ar_avg_wheel_speed`) of that moment, and with
##   the throttle let go the truck keeps that speed where without it the truck slows;
## - Ctrl+R raises the target by 2^(dt/5) a frame, Ctrl+F lowers it by 0.5^(dt/5), not below the
##   lower limit; Ctrl+Space raises it to the current speed, never lowers it;
## - with `autobrake` it brakes by half the excess over target + 0.5 m/s, at most 1, unless the
##   throttle is held;
## - it lets go on the brake, on the parking brake, below its lower limit, with the
##   engine off, and on a respawn;
## - `CruiseControl min_speed, autobrake` needs both values.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const SUBSTEP: float = 1.0 / 2000.0
const FRAME: float = 1.0 / 60.0
const HOLD_S: float = 8.0
## How close the held speed stays to its target over the hold, and how much a truck left alone
## must have slowed for the hold to mean anything.
const HELD_WITHIN: float = 0.05
const COASTED_AT_LEAST: float = 0.15


static func meta() -> Dictionary:
    return {
        "name": "cruise_control_holds_its_speed_as_upstreams",
        "proves": "cruise control holds the speed it was switched on at, adjusts, autobrakes and lets go as upstream's UpdateCruiseControl, and the cruisecontrol line is read as upstream reads it",
        "builds_on": [],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "held within %d%% of target for %.0f s where coasting loses at least %d%%; target steps 2^(dt/5) and 0.5^(dt/5) exact; autobrake (excess - 0.5) x 0.5; every release condition" % [int(HELD_WITHIN * 100.0), HOLD_S, int(COASTED_AT_LEAST * 100.0)],
        "why": "28 corpus files declare cruise control and no vehicle had any.",
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var drive: Dictionary = {}
    if DriveAids.read("cruisecontrol", "CruiseControl 5.5, 1", drive) != "" or drive.get("cruise", {}) != {"lower_limit": 5.5, "can_brake": true}:
        return fail("'CruiseControl 5.5, 1' read as %s" % [drive])
    if DriveAids.read("cruisecontrol", "CruiseControl 5.5", {}) == "":
        return fail("a cruisecontrol line with one value was taken; upstream needs two")
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("line read; skipped the drive: hero asset not present at %s" % MOD_DIR, 0)

    # Held, then coasting: the same start, with and without it.
    var held: Array = _up_to_speed(mod_dir)
    var solver: RorSolver = held[0]
    solver.toggle_cruise_control()
    var target: float = solver.cruise_target_speed()
    if not solver.cruise_control_on() or target != solver.avg_wheel_speed():
        return fail("switched on, it targets %.4f m/s; upstream takes the smoothed wheel speed %.4f" % [target, solver.avg_wheel_speed()])
    var worst: float = 0.0
    for frame: int in int(HOLD_S / FRAME):
        _frame(solver, true)
        if frame > 120:
            worst = maxf(worst, absf(solver.avg_wheel_speed() - target) / target)
    if not solver.cruise_control_on() or worst > HELD_WITHIN:
        return fail("cruising at %.2f m/s it strayed %.1f%% (on: %s)" % [target, worst * 100.0, solver.cruise_control_on()], worst)
    var coast: RorSolver = _up_to_speed(mod_dir)[0]
    var start: float = coast.avg_wheel_speed()
    for frame: int in int(HOLD_S / FRAME):
        _frame(coast, false)
    var lost: float = 1.0 - coast.avg_wheel_speed() / start
    if lost < COASTED_AT_LEAST:
        return fail("left alone the truck lost only %.1f%%; the hold proves nothing" % (lost * 100.0), lost)
    var report: String = "held %.2f m/s within %.1f%% for %.0f s, where coasting lost %.0f%%" % [target, worst * 100.0, HOLD_S, lost * 100.0]

    # The adjusting keys.
    var before: float = solver.cruise_target_speed()
    solver.update_cruise_control(0.1, 0.0, 0.0, true, false, false)
    var raised: float = solver.cruise_target_speed()
    if raised != _f1(before * _f1(pow(2.0, 0.02))):
        return fail("Ctrl+R took the target from %.6f to %.6f; upstream's 2^(dt/5) gives %.6f" % [before, raised, before * pow(2.0, 0.02)])
    solver.set_cruise_control(raised * 0.999, false)
    solver.update_cruise_control(0.1, 0.0, 0.0, false, true, false)
    if solver.cruise_target_speed() != _f1(raised * 0.999):
        return fail("Ctrl+F took the target below the lower limit: %.6f" % solver.cruise_target_speed())
    solver.set_cruise_control(0.0, true)
    solver.update_cruise_control(0.1, 0.0, 0.0, false, false, true)
    if solver.cruise_target_speed() < solver.avg_wheel_speed() or solver.cruise_target_speed() != _f1(raised * 0.999):
        return fail("Ctrl+Space moved a target above the current speed to %.4f" % solver.cruise_target_speed())

    # Autobrake: the target 1.2 m/s under the speed, one Ctrl+F long enough to put it there, so the
    # brake is the excess's half and not its cap.
    solver.toggle_cruise_control()
    solver.toggle_cruise_control()
    var speed: float = solver.avg_wheel_speed()
    solver.update_cruise_control(5.0 * log(speed / (speed - 1.2)) / log(2.0), 0.0, 0.0, false, true, false)
    var excess: float = speed - solver.cruise_target_speed()
    var want: float = minf(excess * 0.5, 1.0)
    if excess <= 0.5 or want >= 1.0 or absf(solver.brake_command() - want) > 1e-6:
        return fail("%.3f m/s over target the brake is %.4f; upstream's autobrake gives %.4f" % [excess, solver.brake_command(), want])
    solver.set_brake(0.0)
    solver.update_cruise_control(0.1, 0.0, 1.0, false, false, false)
    if solver.brake_command() != 0.0:
        return fail("with the throttle held autobrake still braked %.3f" % solver.brake_command())
    report += "; Ctrl+R/F/Space and autobrake as upstream"

    # Letting go.
    var releases: Array = [
        ["the brake", func(s: RorSolver) -> void: s.update_cruise_control(FRAME, 1.0, 0.0, false, false, false)],
        ["the parking brake", func(s: RorSolver) -> void:
            s.set_parking_brake(true)
            s.update_cruise_control(FRAME, 0.0, 0.0, false, false, false)],
        ["the lower limit", func(s: RorSolver) -> void:
            s.set_cruise_control(s.cruise_target_speed() + 1.0, false)
            s.update_cruise_control(FRAME, 0.0, 0.0, false, false, false)],
        ["the engine off", func(s: RorSolver) -> void:
            s.stop_engine()
            s.update_cruise_control(FRAME, 0.0, 0.0, false, false, false)],
    ]
    for release: Array in releases:
        var each: RorSolver = _up_to_speed(mod_dir)[0]
        each.toggle_cruise_control()
        (release[1] as Callable).call(each)
        if each.cruise_control_on():
            return fail("cruise control stayed on through %s" % release[0])
    var respawned: Array = _up_to_speed(mod_dir)
    (respawned[0] as RorSolver).toggle_cruise_control()
    RigBuilder.place(respawned[0], respawned[1], Vector3.ZERO, 0.0, 0.15)
    if (respawned[0] as RorSolver).cruise_control_on():
        return fail("cruise control stayed on through a respawn")
    return ok(report + "; lets go on the brake, parking brake, lower limit, engine off and respawn", worst)


## The hero truck on flat ground, driven up to speed with the throttle and let go: [solver, truck].
func _up_to_speed(mod_dir: String) -> Array:
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    var solver: RorSolver = rig["solver"]
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, rig["truck"], Vector3.ZERO, 0.0, 0.15)
    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(1.0)
    for frame: int in int(6.0 / FRAME):
        solver.step(SUBSTEP, 33)
    solver.set_throttle(0.0)
    return [solver, rig["truck"]]


func _frame(solver: RorSolver, cruising: bool) -> void:
    solver.set_throttle(0.0)
    solver.set_brake(0.0)
    if cruising:
        solver.update_cruise_control(FRAME, 0.0, 0.0, false, false, false)
    solver.step(SUBSTEP, 33)


func _f1(x: float) -> float:
    return PackedFloat32Array([x])[0]
