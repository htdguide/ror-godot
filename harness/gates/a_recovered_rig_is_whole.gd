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
## settle again, steer. A gate on the shock's strength alone would be a gate on one number; this is
## the thing the number is for.
##
## **Restated 2026-10-11, by the owner's decision to turn self-collision on.** With it, the hero
## landing from its 0.40 m recovery breaks one cab beam (79-195), and nothing at 0.30 to 0.50 m in
## 1 cm steps either side (`harness/dev/self_contact_probe.gd`). What this gate was written for —
## a broken wheel and no steering — is unchanged and still held absolutely: nothing at all may
## break through spawn, settle and drive, and the landing may break no shock, rope, support,
## hydro or wheel beam. A cab beam broken on landing is named in the report, and **the same
## sequence with self-collision off is the control**: it must land with nothing broken, or the
## break is something other than the self-contacts the owner accepted.

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
        "proves": "a rig spawns, settles and drives with nothing broken, lands from a recovery with no suspension, steering or wheel beam broken (and nothing at all with self-collision off), and still steers afterwards",
        # the rig has to hold itself up at all before a recovery means anything.
        "builds_on": ["solver_settles_vehicle", "rig_steers"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "0 beams broken through spawn and %.0f s of driving; after a recovery and %.0f s, 0"
            % [DRIVE_SECONDS, AFTER_RECOVER_SECONDS]
            + " shock, rope, support, hydro or wheel beams broken, and 0 of any kind with"
            + " self-collision off"
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
    var landed: Dictionary = _sequence(mod_dir, true)
    if (landed["error"] as String) != "":
        return fail(landed["error"] as String, landed.get("measured", 0))
    var control: Dictionary = _sequence(mod_dir, false)
    if (control["error"] as String) != "":
        return fail("with self-collision off: %s" % control["error"], control.get("measured", 0))
    if (control["landing"] as Array).size() > 0:
        return fail(
            "with self-collision off the landing still broke %s: the break is not the"
            % ", ".join(control["landing"] as Array) + " self-contacts this gate allows",
            (control["landing"] as Array).size()
        )
    var broke: String = "nothing" if (landed["landing"] as Array).is_empty() else ", ".join(
        landed["landing"] as Array)
    return ok(
        "spawned, settled, drove %.0f s to %.0f km/h with nothing broken; recovered from %.2f m:"
        % [DRIVE_SECONDS, landed["kmh"], DriveCfg.RECOVER_CLEARANCE_M]
        + " the landing broke %s (with self-collision off, nothing); steered %.1f degrees"
        % [broke, landed["lock"]],
        landed["lock"]
    )


## The whole sequence on a fresh rig. Returns the error, the speed reached, the beams the landing
## broke (each as "kind a-b"), and the steering lock afterwards.
func _sequence(mod_dir: String, self_collision: bool) -> Dictionary:
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        return {"error": rig["error"]}
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_self_collision(self_collision)
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, DriveCfg.SPAWN_HEIGHT_M)
    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    _run(solver, dt, chunk, SETTLE_SECONDS)
    if solver.broken_beam_count() > 0:
        return {"error": (
            "%d beams broke while the rig settled onto its own springs, before it had been"
            % solver.broken_beam_count() + " driven at all"), "measured": solver.broken_beam_count()}
    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(THROTTLE)
    _run(solver, dt, chunk, DRIVE_SECONDS)
    var kmh: float = solver.road_speed() * 3.6
    if solver.broken_beam_count() > 0:
        return {"error": "%d beams broke over %.0f s of driving on flat ground at %.0f km/h" % [
            solver.broken_beam_count(), DRIVE_SECONDS, kmh], "measured": solver.broken_beam_count()}

    var positions: PackedVector3Array = solver.get_positions()
    RigBuilder.place(
        solver, truck, ActorFrame.of(positions, truck.camera_nodes).origin,
        RigBuilder.heading_of(positions, truck.camera_nodes), DriveCfg.RECOVER_CLEARANCE_M
    )
    solver.set_throttle(0.0)
    _run(solver, dt, chunk, AFTER_RECOVER_SECONDS)
    var kinds: Dictionary = _beam_kinds(truck)
    var landing: Array = []
    for beam: int in solver.beam_count():
        if not solver.beam_broken(beam):
            continue
        var ends: Vector2i = solver.get_beam_nodes(beam)
        var kind: String = kinds.get(beam, "cab") as String
        if kind != "cab":
            return {"error": (
                "the landing from %.2f m broke a %s beam (%d-%d): the vehicle the session"
                % [DriveCfg.RECOVER_CLEARANCE_M, kind, ends.x, ends.y]
                + " complained about, a broken wheel or suspension"), "measured": beam}
        landing.append("%s %d-%d" % [kind, ends.x, ends.y])

    var rest: float = _steer_angle(solver, truck)
    solver.set_steer_command(DriveCfg.steer_command(1.0))
    _run(solver, dt, chunk, 1.5)
    var lock: float = rad_to_deg(absf(wrapf(_steer_angle(solver, truck) - rest, -PI, PI)))
    if lock < MIN_LOCK_DEG:
        return {"error": (
            "on full lock the front wheels turned %.1f degrees, under %.0f: the steering did not"
            % [lock, MIN_LOCK_DEG] + " survive the recovery"), "measured": lock}
    return {"error": "", "kmh": kmh, "landing": landing, "lock": lock}


## Which beams are suspension, steering or wheel: the bounded beams (shocks, ropes, supports),
## the hydros, and every beam touching a wheel's axle or a node a wheel generated.
func _beam_kinds(truck: TruckParser) -> Dictionary:
    var out: Dictionary = {}
    for entry: Dictionary in truck.bounded_beams:
        out[entry["beam"] as int] = "suspension"
    for entry: Dictionary in truck.hydros:
        out[entry["beam"] as int] = "steering"
    var wheel_nodes: Dictionary = {}
    for wheel: Dictionary in truck.wheels:
        wheel_nodes[wheel["node1"] as int] = true
        wheel_nodes[wheel["node2"] as int] = true
    for beam: int in truck.beams.size() / 2:
        var a: int = truck.beams[beam * 2]
        var b: int = truck.beams[beam * 2 + 1]
        var generated: bool = truck.generated_from >= 0 and (
            a >= truck.generated_from or b >= truck.generated_from)
        if not out.has(beam) and (generated or wheel_nodes.has(a) or wheel_nodes.has(b)):
            out[beam] = "wheel"
    return out


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
