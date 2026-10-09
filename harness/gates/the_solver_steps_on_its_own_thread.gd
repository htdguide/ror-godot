extends GateBase
## The solver steps on a thread of its own, and the thread changes nothing but where.
##
## M1's acceptance 2, second half. Rigs of Rods runs its physics on its own threads and draws the
## last completed state; `PlayDrive.step` does the same through `RorSolver.step_async`, posing the
## vehicle from a snapshot while the step runs. Two things can go wrong with that and neither
## shows in a picture: the step can quietly run on the calling thread after all, and the two
## threads can touch the same node while one of them is integrating it. The second is the one
## that bites — a position read halfway through a substep is a position no step ever produced.
##
## So two vehicles are driven side by side through the same drop onto the same kerb, one with the
## solver on its thread and one with it on this one, and every frame's positions are compared,
## with a SHA-256 of each run for the record. The oracle is identity: the runs are equal to the
## bit. The thread is checked as an OS fact rather than a flag — the hash of the std::thread::id
## that ran the step differs from the caller's on the threaded drive and equals it on the other.
##
## PlayDrive asks the solver nothing while a step is in flight, so it cannot tell whether the
## solver would have waited; the guard that every entry point waits is held on the solver
## directly — a bare solver is posted a step and asked for its positions in the same breath, and
## has to answer with the stepped ones. The time the frame waited for the solver against what the
## solver cost is reported and not judged: it is wall-clock, and it is the number the thread
## exists to make small.

const PRESET: String = "hero_3q"
const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const FRAME_S: float = 1.0 / 60.0
## Frames compared position for position; frames a bare solver is read mid-step; and frames run
## afterwards with nothing asking the solver anything, so the overlap the thread buys can be measured.
const COMPARED_FRAMES: int = 180
const BARE_FRAMES: int = 120
const OVERLAP_FRAMES: int = 120
const SUBSTEPS: int = 33
## A kerb under one side of the rig, so the drop is not a symmetric settle.
const KERB_AT: Vector3 = Vector3(0.8, 0.1, 1.2)
const KERB_HALF: Vector3 = Vector3(0.6, 0.1, 0.6)


static func meta() -> Dictionary:
    return {
        "name": "the_solver_steps_on_its_own_thread",
        "proves": "a vehicle whose solver steps on its own thread has, on every one of %d frames, the node positions the same solver gives on the calling thread; the step ran on a different thread; and a solver read the instant a step is posted answers with the stepped positions" % COMPARED_FRAMES,
        "builds_on": ["the_solver_is_deterministic", "a_frame_reports_its_parts"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "positions equal to the bit on all %d driven frames and %d bare ones read mid-step; the step's thread id differs from the caller's when threaded and equals it when not" % [COMPARED_FRAMES, BARE_FRAMES],
        "why": (
            "the plan puts the solver on its own thread so the frame pays a wait instead of the"
            + " step, and a thread that shares a node with the frame tears a position that no"
            + " step produced. Equality with the synchronous run is the only thing that says"
            + " the thread moved the arithmetic without touching it."
        ),
        "budget_s": 90.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)
    var drives: Array[PlayDrive] = []
    for synchronous: bool in [false, true]:
        var built: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
        if (built.get("error", "") as String) != "":
            return fail(built["error"] as String)
        harness.world.add_child(built["root"] as Node3D)
        var drive: PlayDrive = PlayDrive.new()
        drive.synchronous = synchronous
        var set_up: String = drive.setup(built)
        if set_up != "":
            return fail(set_up)
        drive.solver.add_obstacle_box(Transform3D(Basis.IDENTITY, KERB_AT), KERB_HALF, 0)
        drives.append(drive)
    var threaded: PlayDrive = drives[0]
    var on_this_thread: PlayDrive = drives[1]

    var digests: Array[HashingContext] = [HashingContext.new(), HashingContext.new()]
    for digest: HashingContext in digests:
        digest.start(HashingContext.HASH_SHA256)
    var moved: float = 0.0
    var first: PackedVector3Array = threaded.solver.get_positions()
    for frame: int in COMPARED_FRAMES:
        # The threaded drive's positions are read the moment its frame returns, while its step
        # is still running: a read that did not wait for the step would see the rig mid-substep,
        # and that is the read this has to be able to catch.
        threaded.step(FRAME_S)
        var a: PackedByteArray = threaded.solver.get_positions().to_byte_array()
        on_this_thread.step(FRAME_S)
        var b: PackedByteArray = on_this_thread.solver.get_positions().to_byte_array()
        digests[0].update(a)
        digests[1].update(b)
        if a != b:
            return fail(
                "frame %d: the threaded solver's positions differ from the synchronous solver's"
                % frame, frame
            )
        var now: PackedVector3Array = threaded.solver.get_positions()
        for n: int in mini(first.size(), now.size()):
            moved = maxf(moved, first[n].distance_to(now[n]))
    if moved < 0.01:
        return fail("the rig did not move in %d frames (%.4f m): the comparison compared nothing" % [COMPARED_FRAMES, moved], 0)
    var threaded_on: int = threaded.solver.last_step_thread()
    var threaded_caller: int = threaded.solver.caller_thread()
    if threaded_on == threaded_caller:
        return fail("the threaded drive's last step ran on the calling thread (%d)" % threaded_on, 0)
    if on_this_thread.solver.last_step_thread() != on_this_thread.solver.caller_thread():
        return fail("the synchronous drive's last step ran on another thread", 0)
    var bare: String = _bare_solver_waits(threaded.truck)
    if bare != "":
        return fail(bare, 0)

    # The overlap: frames that ask the solver nothing between steps, which is how PlayDrive runs
    # in a window. Wall-clock, so reported and not judged.
    var solver_usec: int = 0
    var wait_usec: int = 0
    for _frame: int in OVERLAP_FRAMES:
        threaded.step(FRAME_S)
        solver_usec += threaded.solver_usec
        wait_usec += threaded.wait_usec
    threaded.solver.sync()
    return ok(
        "%d frames equal to the bit (SHA-256 %s…); the step ran on thread %x, the frame on %x; over %d further frames the solver took %.3f ms a frame and the frame waited %.3f ms of it (%.0f%%); the rig moved %.2f m"
        % [COMPARED_FRAMES, digests[0].finish().hex_encode().substr(0, 16), threaded_on & 0xffff,
           threaded_caller & 0xffff, OVERLAP_FRAMES,
           float(solver_usec) / OVERLAP_FRAMES / 1000.0, float(wait_usec) / OVERLAP_FRAMES / 1000.0,
           100.0 * float(wait_usec) / maxf(float(solver_usec), 1.0), moved],
        COMPARED_FRAMES
    )


## Two bare solvers from the same rig: one is posted each frame's substeps and read for its
## positions in the same breath, the other steps on this thread. A read that did not wait would
## see the rig part-way through a substep, and the two would differ. Returns "" when they agree.
func _bare_solver_waits(truck: TruckParser) -> String:
    var solvers: Array[RefCounted] = []
    for _i: int in 2:
        var rig: Dictionary = RigBuilder.build(truck, DriveCfg.SPAWN_HEIGHT_M)
        if (rig["error"] as String) != "":
            return rig["error"] as String
        var solver: RefCounted = rig["solver"] as RefCounted
        solver.set_ground(0.0, true)
        solver.add_obstacle_box(Transform3D(Basis.IDENTITY, KERB_AT), KERB_HALF, 0)
        solver.start_engine()
        solver.set_gear_selector(1)
        solver.set_throttle(0.5)
        solvers.append(solver)
    var dt: float = 1.0 / DriveCfg.SUBSTEP_HZ
    for frame: int in BARE_FRAMES:
        solvers[0].step_async(dt, SUBSTEPS)
        var a: PackedByteArray = solvers[0].get_positions().to_byte_array()
        solvers[1].step(dt, SUBSTEPS)
        var b: PackedByteArray = solvers[1].get_positions().to_byte_array()
        if a != b:
            return (
                "bare frame %d: a solver read the instant its step was posted gave positions the"
                % frame + " synchronous solver did not — the read did not wait for the step"
            )
    return ""
