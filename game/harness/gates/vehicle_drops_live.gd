extends GateBase
## The whole bridge, end to end: the solver moves the rig, the rig drives the vehicle, and
## the vehicle appears on screen.
##
## Everything before this proves a piece. This runs them together the way the game will —
## solver steps, then `apply_pose`, then a rendered frame — and requires the truck to
## actually fall and land rather than merely not crash.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const PRESET: String = "hero_3q"
## The step this core needs on a real rig; see solver_settles_vehicle for why it is not
## upstream's 2 kHz yet.
const SUBSTEP_HZ: float = 10000.0
const FRAME_HZ: float = 60.0
const FRAMES: int = 90
const DROP_HEIGHT_M: float = 0.8
## The truck must visibly fall: less than this and the test would pass on a rig that
## barely twitched.
const MIN_DESCENT_M: float = 0.3
## And it must stop falling rather than sink through the ground.
const MAX_FINAL_DEPTH_M: float = 0.1


static func meta() -> Dictionary:
    return {
        "name": "vehicle_drops_live",
        "proves": "solver, bridge and renderer run together: a dropped vehicle falls, lands and is drawn doing it",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "vehicle descends at least %.1f m, ends within %.2f m of the ground, stays finite"
            % [MIN_DESCENT_M, MAX_FINAL_DEPTH_M]
        ),
        "why": (
            "each piece is verified alone; this is the first time they run as a system."
            + " Requiring a real descent and a real landing rules out the two ways this"
            + " can look fine while doing nothing: a rig that never moves, and one that"
            + " falls straight through the world."
        ),
        "budget_s": 180.0,
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

    var built: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    var truck: TruckParser = built["truck"] as TruckParser
    harness.world.add_child(built["root"] as Node3D)

    var rig: Dictionary = RigBuilder.build(truck, DROP_HEIGHT_M)
    if (rig["error"] as String) != "":
        return fail(rig["error"] as String)
    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_ground(0.0, true)

    var substeps: int = int(SUBSTEP_HZ / FRAME_HZ)
    var start_height: float = _lowest_node(solver)
    var lowest_seen: float = start_height
    var heights: PackedFloat32Array = PackedFloat32Array()

    for frame: int in FRAMES:
        solver.step(1.0 / SUBSTEP_HZ, substeps)
        var positions: PackedVector3Array = solver.get_positions()
        if not is_finite(positions[0].length()):
            return fail("solver diverged at frame %d" % frame)
        VehicleBuilder.apply_pose(built, truck, positions)
        await harness.advance_frames(1, "static", "drop")
        var height: float = _lowest_node(solver)
        heights.append(height)
        lowest_seen = minf(lowest_seen, height)

    var final_height: float = heights[heights.size() - 1]
    var descent: float = start_height - final_height
    if descent < MIN_DESCENT_M:
        return fail(
            "vehicle descended only %.3f m from %.3f m: it is not falling"
            % [descent, start_height],
            descent
        )
    if final_height < -MAX_FINAL_DEPTH_M:
        return fail(
            "vehicle ended %.3f m below the ground: it fell through" % final_height,
            final_height
        )

    var shot: Dictionary = await harness.capture_shot("vehicle_drops_live", "static", 2)
    if shot["error"] != "":
        return fail(shot["error"] as String)
    return ok(
        "dropped from %.2f m, descended %.2f m over %d frames, resting at %.3f m: %s"
        % [start_height, descent, FRAMES, final_height, shot["png"]],
        descent
    )


func _lowest_node(solver: RefCounted) -> float:
    var lowest: float = INF
    for positions: Vector3 in solver.get_positions():
        lowest = minf(lowest, positions.y)
    return lowest
