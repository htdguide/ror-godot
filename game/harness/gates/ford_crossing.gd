extends GateBase
## The rig drives down the valley and through the ford without falling through it, sticking in it
## or coming apart in it.
##
## PLAN M1 acceptance 7, one of its three scenarios. The ford is the interesting one of the three
## because it is where the terrain changes twice in fifteen metres: the floor drops into the
## channel, the bed is sand rather than a lane, and the far bank climbs back out. Each of those is
## a place where a heightfield bridge that is a cell out, or a contact model that lets a wheel
## through a steep face, shows itself — and none of them show on flat ground, which is where every
## driving gate before this one ran.
##
## What is measured is what the plan asks for and nothing more: the route completes, no node goes
## through the terrain, the rig never stops making progress, nothing comes apart, and the solver's
## energy stays bounded. How well it drives is not the claim; `rig_steers` owns that.

## Long enough for the run at the speed below, with room for the driver to make a mess of the
## approach and still get there.
const LIMIT_S: float = 90.0
## Slow enough that the channel is driven rather than jumped.
const TARGET_SPEED_MS: float = 5.0
## The rig's energy may not grow beyond this much of what it settled at. A softbody that is
## gaining energy is one that will eventually explode, whether or not it does so inside the run.
const MAX_ENERGY_RATIO: float = 60.0
## How deep into the ford the run has to get before the crossing counts as driven rather than
## approached: the channel is 44 m wide and the bar is in the middle of it.
const MIN_DISTANCE_M: float = 250.0


static func meta() -> Dictionary:
    return {
        "name": "ford_crossing",
        "proves": "the rig drives the valley floor and crosses the ford without falling through the terrain, getting stuck or coming apart",
        # driving a route is the driven rig of rig_drives_forward, steered, over terrain.
        "builds_on": ["rig_steers", "terrain_collision_agreement"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "the route completes inside %.0f s; no node more than %.1f m under the terrain;"
            % [LIMIT_S, DriveRoute.FALL_THROUGH_M]
            + " no node over %.0f m/s; energy at most %.0fx the settled rig; at least %.0f m"
            % [DriveRoute.EXPLODE_SPEED_MS, MAX_ENERGY_RATIO, MIN_DISTANCE_M]
            + " driven"
        ),
        "why": (
            "every driving gate before this one ran on flat ground, where a heightfield that is"
            + " a cell out and a contact model that lets a wheel through a steep face both look"
            + " perfect. The ford changes the ground twice in fifteen metres, which is where"
            + " those faults live."
        ),
        "budget_s": 180.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var report: Dictionary = await DriveScenario.run(harness, ValleyRoutes.ford_crossing(), {
        "limit_s": LIMIT_S,
        "target_speed_ms": TARGET_SPEED_MS,
    })
    if report.has("skipped"):
        return ok("skipped: %s" % report["skipped"], 0)
    # An empty "error" is the ordinary case: `DriveRoute` reports its own troubles in "reason",
    # and reserves "error" for a run that could not be set up at all.
    if (report.get("error", "") as String) != "":
        return fail(report["error"] as String)
    if not bool(report["completed"]):
        return fail(
            "the crossing did not complete: %s (%.0f m driven, %d waypoints reached, path %s)"
            % [report["reason"] as String, report["distance_m"] as float,
               report["reached"] as int, _path_summary(report["path"] as PackedVector2Array)],
            report["distance_m"]
        )
    if (report["distance_m"] as float) < MIN_DISTANCE_M:
        return fail(
            "the route completed in %.0f m, under the %.0f m the crossing is: the waypoints are"
            % [report["distance_m"] as float, MIN_DISTANCE_M]
            + " not where the ford is",
            report["distance_m"]
        )
    if (report["energy_ratio"] as float) > MAX_ENERGY_RATIO:
        return fail(
            "the rig's energy reached %.0fx what it settled at, over %.0fx: it is gaining energy"
            % [report["energy_ratio"] as float, MAX_ENERGY_RATIO],
            report["energy_ratio"]
        )
    return ok(
        "crossed in %.1f s over %.0f m: worst node %.1f m/s, deepest %.2f m into the terrain,"
        % [report["seconds"] as float, report["distance_m"] as float,
           report["worst_speed_ms"] as float, report["deepest_m"] as float]
        + " energy at most %.0fx the settled rig, starting on %s" % [
            report["energy_ratio"] as float, report["surface_at_start"] as String],
        report["deepest_m"]
    )


## The first few and last few seconds of where the rig went, for a failure to be readable without
## re-running it.
func _path_summary(path: PackedVector2Array) -> String:
    var parts: PackedStringArray = PackedStringArray()
    for index: int in path.size():
        if index < 10 or index >= path.size() - 3:
            parts.append("%.0f,%.0f" % [path[index].x, path[index].y])
        elif index == 10:
            parts.append("...")
    return "[" + " ".join(parts) + "]"
