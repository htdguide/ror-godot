extends GateBase
## A rig settles, drives and is recovered without anything on it breaking — and it still steers.
##
## A session pressed R to set the truck back on its wheels and reported that it "breaks one of
## the wheels and the car can't steer". It was the dampers. Upstream's spawner gives a shock four
## times the file's breaking threshold in force, and a shock's force is mostly damping: at the
## hero truck's 2400 Ns/m against a 4000 N threshold it snaps at 1.7 m/s of suspension travel,
## which is a kerb. Two of them were breaking while the rig settled onto its own springs, before
## anything had been driven.
##
## So the claim is the whole sequence a person actually performs — spawn, settle, drive, recover,
## settle again, steer — with nothing broken at the end of it. A gate on the shock's strength
## alone would be a gate on one number; this is the thing the number is for.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const SUBSTEP_HZ: float = 2000.0
const SETTLE_SECONDS: float = 2.0
const DRIVE_SECONDS: float = 6.0
const AFTER_RECOVER_SECONDS: float = 4.0
const THROTTLE: float = 0.8
## What a recovery drops the rig from, which is what `DriveCfg.RECOVER_CLEARANCE_M` says.
## Deliberately taken from the same constant a session uses rather than restated here.
## How much the front wheels must turn when the wheel is put on full lock, in degrees. Far below
## the hero truck's own 31 degrees of lock: this is asking whether steering still exists.
const MIN_LOCK_DEG: float = 10.0


static func meta() -> Dictionary:
    return {
        "name": "a_recovered_rig_is_whole",
        "proves": "a rig spawns, settles, drives and is recovered with nothing on it broken, and still steers afterwards",
        # the rig has to hold itself up at all before a recovery means anything.
        "builds_on": ["solver_settles_vehicle", "rig_steers"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "0 beams broken through spawn, %.0f s of driving, a recovery and %.0f s after it,"
            % [DRIVE_SECONDS, AFTER_RECOVER_SECONDS]
            + " and at least %.0f degrees of steering left" % MIN_LOCK_DEG
        ),
        "why": (
            "a session reported that recovering the truck broke a wheel and left it unable to"
            + " steer. It was the shocks: upstream gives them four times the file's breaking"
            + " threshold because their force is mostly damping, and without that they snap at"
            + " 1.7 m/s of suspension travel. Two were breaking during the spawn itself."
        ),
        "budget_s": 180.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        return fail(rig["error"] as String)
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, DriveCfg.SPAWN_HEIGHT_M)

    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    _run(solver, dt, chunk, SETTLE_SECONDS)
    if solver.broken_beam_count() > 0:
        return fail(
            "%d beams broke while the rig settled onto its own springs, before it had been"
            % solver.broken_beam_count() + " driven at all",
            solver.broken_beam_count()
        )

    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(THROTTLE)
    _run(solver, dt, chunk, DRIVE_SECONDS)
    var after_drive: int = solver.broken_beam_count()
    if after_drive > 0:
        return fail(
            "%d beams broke over %.0f s of driving on flat ground at %.0f km/h"
            % [after_drive, DRIVE_SECONDS, solver.road_speed() * 3.6],
            after_drive
        )

    # The recovery a session performs: upright, where it is, facing the way it was going.
    var positions: PackedVector3Array = solver.get_positions()
    RigBuilder.place(
        solver,
        truck,
        ActorFrame.of(positions, truck.camera_nodes).origin,
        RigBuilder.heading_of(positions, truck.camera_nodes),
        DriveCfg.RECOVER_CLEARANCE_M
    )
    solver.set_throttle(0.0)
    _run(solver, dt, chunk, AFTER_RECOVER_SECONDS)
    var after_recover: int = solver.broken_beam_count()
    if after_recover > 0:
        return fail(
            "%d beams broke when the rig was recovered and set back down from %.2f m"
            % [after_recover, DriveCfg.RECOVER_CLEARANCE_M],
            after_recover
        )

    # And it still steers.
    var rest: float = _steer_angle(solver, truck)
    solver.set_steer_command(DriveCfg.steer_command(1.0))
    _run(solver, dt, chunk, 1.5)
    var lock: float = rad_to_deg(absf(wrapf(_steer_angle(solver, truck) - rest, -PI, PI)))
    if lock < MIN_LOCK_DEG:
        return fail(
            "on full lock the front wheels turned %.1f degrees, under %.0f: the steering did not"
            % [lock, MIN_LOCK_DEG] + " survive the recovery",
            lock
        )
    return ok(
        "spawned, settled, drove %.0f s to %.0f km/h, recovered from %.2f m and steered %.1f"
        % [DRIVE_SECONDS, solver.road_speed() * 3.6, DriveCfg.RECOVER_CLEARANCE_M, lock]
        + " degrees, with 0 of %d beams broken" % solver.beam_count(),
        lock
    )


func _run(solver: RefCounted, dt: float, chunk: int, seconds: float) -> void:
    for _frame: int in int(seconds * 60.0):
        solver.step(dt, chunk)


## The angle between the front axle and the rear one, which is the steering lock.
func _steer_angle(solver: RefCounted, truck: TruckParser) -> float:
    return wrapf(_axle_heading(solver, truck, 0, 1) - _axle_heading(solver, truck, 2, 3), -PI, PI)


func _axle_heading(solver: RefCounted, truck: TruckParser, left: int, right: int) -> float:
    var sum: Vector3 = Vector3.ZERO
    for index: int in [left, right]:
        var wheel: Dictionary = truck.wheels[index]
        var a: Vector3 = solver.get_node_position(wheel["node1"] as int)
        var b: Vector3 = solver.get_node_position(wheel["node2"] as int)
        sum += Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
    return atan2(sum.z, sum.x)
