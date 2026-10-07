extends GateBase
## Driven into a wall, the hero truck bends and stays bent. Driven gently into the same wall, it
## does not.
##
## This is the vehicle-level half of `beams_deform_and_break`: that one checks the arithmetic on
## one beam, and this one checks that a real rig, with the deform and break figures its own file
## declares, actually crumples when it is crashed. Both are needed — the law can be exactly right
## and still reach no beam, which is what was happening before the `set_beam_defaults` deform and
## break fields were parsed at all.
##
## The measurement is the rig's own rest lengths, before and after. A bend is permanent by
## definition: the shape the structure returns to has changed, and that is visible in the beams
## rather than in a photograph of a truck that has stopped moving.
##
## The gentle run is the control, and it is part of the gate rather than a note: a threshold that
## calls every drive a crash proves nothing.

## **Two vehicles, because a rig that will not bend looks exactly like one nobody crashed.** Every
## fault found in this loader so far was invisible on the hero truck and plain on a second car.
const VEHICLES: Array[Dictionary] = [
    {"dir": "assets/mods/ChevyS1023", "file": "S10offroad.truck"},
    {"dir": "assets/mods/mazda626gf", "file": "mazda626sd18i-mt.car"},
]
const SUBSTEP_HZ: float = 2000.0
const SETTLE_SECONDS: float = 1.5
const IMPACT_SECONDS: float = 6.0
## Where the wall stands, and how big it is.
const WALL_AT_M: float = 22.0
const WALL_HALF: Vector3 = Vector3(9.0, 1.6, 1.0)
## The crash, and the control. Both are throttle settings rather than speeds, because what the rig
## reaches is the rig's business: the fast run is reported with the speed it actually hit at.
const CRASH_THROTTLE: float = 1.0
const GENTLE_THROTTLE: float = 0.12
## A beam counts as bent when its rest length has moved by this much. Above the millimetre a
## settling rig moves its shocks by, well below what a crash does.
const BENT_M: float = 0.01
## What a crash has to produce, and what a gentle nudge may not exceed.
const MIN_BENT_BEAMS: int = 8
const MAX_GENTLE_BENT_BEAMS: int = 0
## And it has to survive: a rig that comes apart entirely is not bending, it is exploding.
const MAX_BROKEN_SHARE: float = 0.15


static func meta() -> Dictionary:
    return {
        "name": "a_crash_bends_the_rig",
        "proves": "a real vehicle driven into a wall takes a permanent set in its own structure, a gentle one does not, and neither comes apart",
        # one beam's arithmetic first; this is whether it reaches a whole rig.
        "builds_on": ["beams_deform_and_break", "obstacles_are_solid"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "at least %d beams permanently changed by %.0f mm after the crash, none after the"
            % [MIN_BENT_BEAMS, BENT_M * 1000.0]
            + " gentle run, and at most %.0f%% of beams broken" % (MAX_BROKEN_SHARE * 100.0)
        ),
        "why": (
            "the deform law can be exactly right and still reach no beam in a real rig — which is"
            + " what was happening while the file's deform and break figures went unparsed, and"
            + " what a session reported as the truck being too stiff to bend. One beam's"
            + " arithmetic does not answer that; a whole vehicle hitting a wall does."
        ),
        "budget_s": 120.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var reports: PackedStringArray = PackedStringArray()
    for entry: Dictionary in VEHICLES:
        var mod_dir: String = SourceScan.repo_root().path_join(entry["dir"] as String)
        if not DirAccess.dir_exists_absolute(mod_dir):
            continue
        var outcome: Dictionary = _crash(mod_dir, entry["file"] as String)
        if (outcome["error"] as String) != "":
            return fail("%s: %s" % [entry["file"], outcome["error"]], outcome.get("measured", 0))
        reports.append("%s %s" % [entry["file"], outcome["report"]])
    if reports.is_empty():
        return ok("skipped: none of the gate's vehicles are in this checkout", 0)
    return ok("; ".join(reports), reports.size())


## One vehicle, driven into a wall twice. Returns {"error", "report"}.
func _crash(mod_dir: String, file: String) -> Dictionary:
    var crash: Dictionary = _drive_into_wall(mod_dir, CRASH_THROTTLE, file)
    if (crash["error"] as String) != "":
        return {"error": crash["error"] as String, "report": ""}
    var gentle: Dictionary = _drive_into_wall(mod_dir, GENTLE_THROTTLE, file)
    if (gentle["error"] as String) != "":
        return {"error": gentle["error"] as String, "report": ""}

    if (crash["bent"] as int) < MIN_BENT_BEAMS:
        return {
            "error": (
                "hit at %.1f m/s, %d beams took a permanent set, under %d: the rig is not bending"
                % [crash["speed"] as float, crash["bent"] as int, MIN_BENT_BEAMS]
            ),
            "measured": crash["bent"], "report": "",
        }
    if (gentle["bent"] as int) > MAX_GENTLE_BENT_BEAMS:
        return {
            "error": (
                "the gentle run at %.1f m/s bent %d beams: the threshold calls an ordinary drive"
                % [gentle["speed"] as float, gentle["bent"] as int] + " a crash"
            ),
            "measured": gentle["bent"], "report": "",
        }
    var broken_share: float = float(crash["broken"] as int) / float(maxi(crash["beams"] as int, 1))
    if broken_share > MAX_BROKEN_SHARE:
        return {
            "error": (
                "the crash broke %d of %d beams (%.0f%%): that is coming apart rather than bending"
                % [crash["broken"] as int, crash["beams"] as int, broken_share * 100.0]
            ),
            "measured": broken_share, "report": "",
        }
    return {
        "error": "",
        "report": (
            "hit at %.1f m/s: %d bent, worst %.0f mm, %d broken of %d; gentle %.1f m/s bent %d"
            % [crash["speed"] as float, crash["bent"] as int, (crash["worst"] as float) * 1000.0,
               crash["broken"] as int, crash["beams"] as int, gentle["speed"] as float,
               gentle["bent"] as int]
        ),
    }


## Drives the rig at a wall and reports what its own structure did. The wall is placed along the
## rig's own forward axis after it has settled, the way `obstacles_are_solid` does it: which way a
## placed rig faces is its own business.
func _drive_into_wall(mod_dir: String, throttle: float, file: String) -> Dictionary:
    var blank: Dictionary = {
        "error": "", "bent": 0, "worst": 0.0, "broken": 0, "beams": 0, "speed": 0.0,
    }
    var rig: Dictionary = RigBuilder.from_file(mod_dir, file, 0.0)
    if (rig["error"] as String) != "":
        blank["error"] = rig["error"] as String
        return blank
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.15)

    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    for _i: int in int(SETTLE_SECONDS * 60.0):
        solver.step(dt, chunk)
    # The rest lengths the rig settled at: shocks have already moved, so this is the datum a bend
    # is measured against rather than what the file said.
    var before: PackedFloat32Array = _rest_lengths(solver)

    var pose: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
    var forward: Vector3 = -pose.basis.z
    forward = Vector3(forward.x, 0.0, forward.z).normalized()
    var centre: Vector3 = pose.origin + forward * WALL_AT_M + Vector3(0.0, WALL_HALF.y, 0.0)
    solver.add_obstacle_box(
        Transform3D(Basis.looking_at(-forward, Vector3.UP), centre), WALL_HALF, 0
    )

    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(throttle)
    var fastest: float = 0.0
    for frame: int in int(IMPACT_SECONDS * 60.0):
        solver.step(dt, chunk)
        fastest = maxf(fastest, absf(solver.road_speed()))
        if not is_finite(solver.get_node_position(0).length()):
            blank["error"] = "the solver went non-finite %.2f s into the run" % (
                float(frame) / 60.0)
            return blank
    # Let it come to rest before reading the shape back: what is wanted is the set it kept, not
    # what it looked like while it was still ringing.
    solver.set_throttle(0.0)
    solver.set_brake(1.0)
    for _i: int in int(2.0 * 60.0):
        solver.step(dt, chunk)

    var after: PackedFloat32Array = _rest_lengths(solver)
    var bent: int = 0
    var worst: float = 0.0
    for index: int in mini(before.size(), after.size()):
        var moved: float = absf(after[index] - before[index])
        if moved > BENT_M:
            bent += 1
        worst = maxf(worst, moved)
    return {
        "error": "",
        "bent": bent,
        "worst": worst,
        "broken": solver.broken_beam_count(),
        "beams": solver.beam_count(),
        "speed": fastest,
    }


func _rest_lengths(solver: RefCounted) -> PackedFloat32Array:
    var out: PackedFloat32Array = PackedFloat32Array()
    for beam: int in solver.beam_count():
        out.append(solver.get_beam_rest_length(beam))
    return out
