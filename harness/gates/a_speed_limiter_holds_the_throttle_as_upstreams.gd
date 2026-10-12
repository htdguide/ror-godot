extends GateBase
## A `SpeedLimiter max_speed` line is upstream's speed limiter (`ActorManager::UpdateTruckFeatures`):
## once a frame, in any gear but neutral, the throttle is held to twice what is left of the limit,
## the driven wheels' speed taken as 2% over the road's, and never above the engine's throttle; the
## cruise control's target, raised or matched, is kept under it.
##
## Ours read the line as metadata: 33 corpus files state one, and none was limited.
##
## The oracle is upstream's rule, frame by frame, on the hero truck on flat ground at full throttle.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const LIMIT: float = 10.0
const SUBSTEP: float = 1.0 / 2000.0
const FRAME: float = 1.0 / 60.0
const DRIVE_S: float = 10.0


static func meta() -> Dictionary:
    return {
        "name": "a_speed_limiter_holds_the_throttle_as_upstreams",
        "proves": "the speedlimiter line limits the throttle every frame by upstream's rule and caps the cruise control's target",
        "builds_on": [],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "every frame's throttle exactly clamp((limit - |wheel speed / 1.02|) x 2, 0, engine throttle) in gear and untouched in neutral; the cruise target never over the limit",
        "why": "33 corpus files state a speed limiter and it was read as metadata: none was limited.",
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var truck: TruckParser = TruckParser.new()
    truck.parse_text("t\nglobals\n1000, 0, tracks/semi\nnodes\n0, 0, 0, 0\n1, 1, 0, 0\nSpeedLimiter 10.417\nbeams\n0, 1\nend")
    if truck.drivetrain.get("speed_limit", 0.0) != 10.417 or truck.beams.size() != 2:
        return fail("'SpeedLimiter 10.417' read as %s, and the beams after it as %d values" % [truck.drivetrain.get("speed_limit"), truck.beams.size()])
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("line read; skipped the drive: hero asset not present at %s" % MOD_DIR, 0)

    var limited: RorSolver = _truck(mod_dir)
    limited.set_speed_limiter(LIMIT)
    var fastest: float = 0.0
    for frame: int in int(DRIVE_S / FRAME):
        limited.set_throttle(1.0)
        var speed: float = limited.wheel_speed()
        # Upstream clamps to `getAcc()`, the engine's own throttle, which a shift in progress lowers.
        var asked: float = limited.commanded_throttle()
        limited.update_speed_limiter()
        # In floats, operation by operation, as upstream's rule runs.
        var accl: float = _f1(_f1(LIMIT - absf(_f1(speed / _f1(1.02)))) * 2.0)
        var want: float = clampf(accl, 0.0, asked) if limited.engine_gear() != 0 else asked
        if limited.commanded_throttle() != want:
            return fail("frame %d at %.3f m/s in gear %d: throttle %.6f, upstream's rule gives %.6f" % [
                frame, speed, limited.engine_gear(), limited.commanded_throttle(), want])
        limited.step(SUBSTEP, 33)
        fastest = maxf(fastest, limited.avg_wheel_speed())
    var free: RorSolver = _truck(mod_dir)
    for frame: int in int(DRIVE_S / FRAME):
        free.set_throttle(1.0)
        free.step(SUBSTEP, 33)
    if fastest > LIMIT * 1.1 or free.avg_wheel_speed() < LIMIT * 2.0:
        return fail("limited to %.0f m/s the truck reached %.2f; unlimited %.2f" % [LIMIT, fastest, free.avg_wheel_speed()], fastest)

    # In neutral the limiter leaves the throttle alone, whatever the speed.
    var coasting: RorSolver = _truck(mod_dir)
    coasting.set_gear_selector(0)
    coasting.step(SUBSTEP, 2000)
    coasting.set_speed_limiter(-5.0)
    coasting.set_throttle(1.0)
    coasting.update_speed_limiter()
    if coasting.engine_gear() != 0 or coasting.commanded_throttle() != 1.0:
        return fail("in gear %d the limiter took the throttle to %.3f; upstream leaves neutral alone" % [coasting.engine_gear(), coasting.commanded_throttle()])

    # The cruise control's target, raised by Ctrl+R or matched by Ctrl+Space, stays under it.
    limited.toggle_cruise_control()
    for k: int in 200:
        limited.update_cruise_control(0.1, 0.0, 0.0, true, false, false)
    if limited.cruise_target_speed() > LIMIT:
        return fail("Ctrl+R took the cruise target to %.3f m/s, over the %.0f m/s limit" % [limited.cruise_target_speed(), LIMIT])
    free.toggle_cruise_control()
    free.set_speed_limiter(LIMIT)
    free.update_cruise_control(0.1, 0.0, 0.0, false, false, true)
    if free.cruise_target_speed() != LIMIT:
        return fail("Ctrl+Space at %.1f m/s set the cruise target to %.3f, not the %.0f m/s limit" % [free.avg_wheel_speed(), free.cruise_target_speed(), LIMIT])
    return ok("every frame's throttle by upstream's rule; held to %.2f m/s under a %.0f m/s limit where unlimited reached %.1f; the cruise target capped" % [
        fastest, LIMIT, free.avg_wheel_speed()], fastest)


func _truck(mod_dir: String) -> RorSolver:
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    var solver: RorSolver = rig["solver"]
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, rig["truck"], Vector3.ZERO, 0.0, 0.15)
    solver.start_engine()
    solver.set_gear_selector(1)
    return solver


func _f1(x: float) -> float:
    return PackedFloat32Array([x])[0]
