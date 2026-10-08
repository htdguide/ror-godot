extends GateBase
## The same rig, the same inputs, six hundred frames: the same node positions to the bit.
##
## M1's acceptance 4. Determinism is what makes a replay a replay, a golden a golden and a
## measurement a measurement: every number this project records from the solver assumes that
## running it again gives the same number. Nothing checked that. A wall-clock read inside a force
## law, an unordered container iterated for forces, an uninitialised field, a fast-math flag — any
## of them makes the second run a different run, and none of them shows up as a wrong-looking
## picture.
##
## Two fresh solvers are built from the same file and driven through the same script — settle,
## full throttle, a steer, a crash into a box, brakes — **interleaved, a frame of one and then a
## frame of the other**, so anything one run leaves in the process is in the other's way; every
## frame's node positions go into a SHA-256. The oracle is identity: the two digests are equal.
## **And the instrument is checked in the same run**: a third solver takes the same script with one
## substep more, and its digest has to differ, or the hash is not reading the positions.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const SUBSTEP_HZ: float = 2000.0
const FRAMES: int = 600
const FRAME_HZ: float = 60.0
## The script, in frames: when the throttle goes down, the wheel turns, the brakes go on.
const THROTTLE_FROM: int = 60
const STEER_FROM: int = 150
const STEER_TO: int = 250
const BRAKE_FROM: int = 420
## A box across the road, far enough that the rig reaches it at speed and near enough that it does
## before the brakes: a crash bends and breaks beams, and a broken beam is state the second run has
## to break identically.
const WALL_AHEAD_M: float = 45.0
const WALL_HALF: Vector3 = Vector3(6.0, 1.5, 0.6)


static func meta() -> Dictionary:
    return {
        "name": "the_solver_is_deterministic",
        "proves": "two solvers built from the same file and given the same %d frames of inputs produce bit-identical node positions on every frame, and the hash that says so tells one extra substep apart" % FRAMES,
        "builds_on": ["solver_settles_vehicle"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "SHA-256 over %d frames of node positions equal between two fresh runs; a third run with one more substep differs" % FRAMES,
        "why": (
            "every replay, golden and measurement taken from the solver assumes a second run"
            + " gives the same numbers, and nothing checked it. A clock in a force law or an"
            + " unordered container iterated for forces makes the second run a different run"
            + " without making a picture look wrong."
        ),
        "budget_s": 120.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var pair: Array[Dictionary] = _run_many(mod_dir, [0, 0])
    var nudged: Array[Dictionary] = _run_many(mod_dir, [1])
    for run: Dictionary in pair + nudged:
        if (run["error"] as String) != "":
            return fail(run["error"] as String)
    var first: Dictionary = pair[0]
    var second: Dictionary = pair[1]

    if (nudged[0]["digest"] as String) == (first["digest"] as String):
        return fail(
            "a run with one extra substep hashed the same as the plain run (%s): the hash is not"
            % first["digest"] + " reading the positions",
            0
        )
    if (first["digest"] as String) != (second["digest"] as String):
        var frames_a: PackedStringArray = first["frames"] as PackedStringArray
        var frames_b: PackedStringArray = second["frames"] as PackedStringArray
        var diverged: int = -1
        for frame: int in frames_a.size():
            if frames_a[frame] != frames_b[frame]:
                diverged = frame
                break
        return fail(
            "two interleaved runs of the same %d frames diverge at frame %d (%s against %s over"
            % [FRAMES, diverged, first["digest"], second["digest"]]
            + " the whole): the solver is not deterministic",
            diverged
        )
    return ok(
        "%d frames, %d nodes, two interleaved runs identical to the bit (%s); %d beams broken in"
        % [FRAMES, first["nodes"], (first["digest"] as String).substr(0, 16), first["broken"]]
        + " the crash; one extra substep gives %s" % (nudged[0]["digest"] as String).substr(0, 16),
        first["broken"]
    )


## Runs of the script on fresh solvers, one per entry of `extra_substeps`, stepped a frame at a
## time in turn so that they share the process while they run. Each entry is that run's control
## knob: substeps added to its first frame.
func _run_many(mod_dir: String, extra_substeps: Array[int]) -> Array[Dictionary]:
    var runs: Array[Dictionary] = []
    for extra: int in extra_substeps:
        var started: Dictionary = _start(mod_dir)
        if (started["error"] as String) != "":
            return [started]
        started["extra"] = extra
        started["digest"] = HashingContext.new()
        (started["digest"] as HashingContext).start(HashingContext.HASH_SHA256)
        started["frames"] = PackedStringArray()
        runs.append(started)
    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / FRAME_HZ)
    for frame: int in FRAMES:
        for run: Dictionary in runs:
            var solver: RefCounted = run["solver"] as RefCounted
            solver.set_throttle(1.0 if frame >= THROTTLE_FROM and frame < BRAKE_FROM else 0.0)
            solver.set_brake(1.0 if frame >= BRAKE_FROM else 0.0)
            solver.set_steer_command(
                DriveCfg.steer_command(0.4) if frame >= STEER_FROM and frame < STEER_TO else 0.0
            )
            solver.step(dt, chunk + ((run["extra"] as int) if frame == 0 else 0))
            var positions: PackedVector3Array = solver.get_positions()
            if positions.is_empty() or not is_finite(positions[0].length()):
                return [{"error": "the solver went non-finite at frame %d" % frame}]
            var bytes: PackedByteArray = positions.to_byte_array()
            (run["digest"] as HashingContext).update(bytes)
            # One hash per frame beside the running one, so a divergence names its frame.
            var per_frame: HashingContext = HashingContext.new()
            per_frame.start(HashingContext.HASH_MD5)
            per_frame.update(bytes)
            (run["frames"] as PackedStringArray).append(per_frame.finish().hex_encode())
    var out: Array[Dictionary] = []
    for run: Dictionary in runs:
        var solver: RefCounted = run["solver"] as RefCounted
        out.append({
            "error": "", "digest": (run["digest"] as HashingContext).finish().hex_encode(),
            "frames": run["frames"], "nodes": solver.node_count(),
            "broken": solver.broken_beam_count(),
        })
    return out


## A fresh solver on the hero, settled, with the wall standing across its own forward — read off
## the settled rig rather than assumed.
func _start(mod_dir: String) -> Dictionary:
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        return {"error": rig["error"]}
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.15)
    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / FRAME_HZ)
    for _i: int in 30:
        solver.step(dt, chunk)
    var pose: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
    var forward: Vector3 = Vector3(-pose.basis.z.x, 0.0, -pose.basis.z.z).normalized()
    var wall_at: Vector3 = pose.origin + forward * WALL_AHEAD_M
    solver.add_obstacle_box(
        Transform3D(Basis.looking_at(-forward, Vector3.UP), Vector3(wall_at.x, WALL_HALF.y, wall_at.z)),
        WALL_HALF, 0
    )
    solver.start_engine()
    solver.set_gear_selector(1)
    return {"error": "", "solver": solver, "truck": truck}
