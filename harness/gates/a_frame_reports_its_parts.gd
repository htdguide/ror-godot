extends GateBase
## A frame of a driven vehicle reports what it spent on the solver, on deforming the vehicle, and
## on submitting it to the renderer, each on its own, in the metric line tooling reads.
##
## M1's acceptance 2 asks `HARNESS_METRIC` for `solver_ms`, `deform_ms` and `submit_ms`
## separately, and for a year the line carried `frame_ms` alone: a frame that went over budget
## said so and said nothing about which of this project's own three jobs did it. The split is a
## measurement of where the time goes — the solver is the physics, deform is the arithmetic that
## turns node positions into bone and prop transforms, submit is handing those to the renderer —
## and the three are the levers M1's threading and M3's skinning work pull on.
##
## The oracle is an identity. Deform and submit are parts of the frame they are reported in, and
## so is `solver_wait_ms`, the time the frame spent waiting for a step posted to the solver's own
## thread; those cannot sum to more than the frame. `solver_ms` is the step's own time on
## whichever thread ran it, and it is positive while a vehicle is being driven. A part reported
## as zero is a part nobody timed; a sum over the whole is a clock read twice.

const PRESET: String = "hero_3q"
const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const SETTLE_FRAMES: int = 3
const DRIVEN_FRAMES: int = 30
const FRAME_S: float = 1.0 / 60.0
## What a driven frame has to have timed, and what it spent on this thread.
const PHASES: Array[String] = ["solver_ms", "deform_ms", "submit_ms"]
const ON_THIS_THREAD: Array[String] = ["solver_wait_ms", "deform_ms", "submit_ms"]


static func meta() -> Dictionary:
    return {
        "name": "a_frame_reports_its_parts",
        "proves": "every metric row of a driven frame carries solver_ms, deform_ms and submit_ms, each positive, and what the frame spent on its own thread — solver_wait_ms, deform_ms, submit_ms — is no more than the frame",
        "builds_on": ["vehicle_drops_live"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "over %d driven frames every row has all three keys, each above zero, and"
            % DRIVEN_FRAMES + " solver_wait_ms + deform_ms + submit_ms is at most frame_ms"
        ),
        "why": (
            "a frame over budget has to say which of the project's own jobs did it, and until the"
            + " line carried the three names a hitch was a number with no owner. The bound is an"
            + " identity rather than a budget: parts of a frame are positive and do not exceed it,"
            + " and once the solver has its own thread the part of it the frame pays is the wait."
        ),
        "budget_s": 60.0,
        "needs_gpu": true,
        "milestone": "M1",
        # The measured value is the worst share of a frame the parts took: a wall-clock ratio,
        # compared by verdict in the order check.
        "measured_is_wall_clock": true,
    }


func run(harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)
    var built: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    harness.world.add_child(built["root"] as Node3D)
    var drive: PlayDrive = PlayDrive.new()
    var set_up: String = drive.setup(built)
    if set_up != "":
        return fail(set_up)
    for _i: int in SETTLE_FRAMES:
        drive.step(FRAME_S)
        await harness.advance_frames(1, "static", "settle")
    drive.solver.set_throttle(0.5)

    var worst_share: float = 0.0
    var sums: Dictionary = {"solver_ms": 0.0, "solver_wait_ms": 0.0, "deform_ms": 0.0, "submit_ms": 0.0}
    for frame: int in DRIVEN_FRAMES:
        drive.step(FRAME_S)
        await harness.advance_frames(1, "static", "driven")
        var row: Dictionary = harness.metrics.last_sample
        for key: String in PHASES:
            if not row.has(key):
                return fail("driven frame %d reported no %s: the row is %s" % [frame, key, JSON.stringify(row)])
            var ms: float = float(row[key])
            if ms <= 0.0:
                return fail(
                    "driven frame %d reports %s as %.3f: a part nobody timed. Row: %s"
                    % [frame, key, ms, JSON.stringify(row)], ms
                )
        var total: float = 0.0
        for key: String in ON_THIS_THREAD:
            if not row.has(key):
                return fail("driven frame %d reported no %s: the row is %s" % [frame, key, JSON.stringify(row)])
            total += float(row[key])
        for key: String in sums:
            sums[key] = float(sums[key]) + float(row[key])
        var frame_ms: float = float(row["frame_ms"])
        var share: float = total / maxf(frame_ms, 0.001)
        worst_share = maxf(worst_share, share)
        if total > frame_ms:
            return fail(
                "driven frame %d reports %.3f ms of its own thread's parts inside a %.3f ms frame: a clock read twice"
                % [frame, total, frame_ms], share
            )
    return ok(
        "%d driven frames: mean solver %.3f ms on its thread, of which this thread waited %.3f; deform %.3f, submit %.3f ms; this thread's parts take at most %.0f%% of a frame"
        % [DRIVEN_FRAMES, float(sums["solver_ms"]) / DRIVEN_FRAMES,
           float(sums["solver_wait_ms"]) / DRIVEN_FRAMES,
           float(sums["deform_ms"]) / DRIVEN_FRAMES, float(sums["submit_ms"]) / DRIVEN_FRAMES,
           worst_share * 100.0],
        worst_share
    )
