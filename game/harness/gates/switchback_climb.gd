extends GateBase
## The rig climbs the switchback road to the ridge without falling through it, sliding off it or
## coming apart on it.
##
## PLAN M1 acceptance 7, one of its three scenarios, and the long one: 2.2 km of road, four
## hairpins and 108 m of climb. It is the route where traction, gearing and the terrain's slope all
## have to work at once — the rig has to pull a 6% grade for minutes at a time, hold a corner on
## gravel, and not lose the road on the side where the wall falls away.
##
## The driver is the plain waypoint follower every drivability gate uses, and that is deliberate:
## a climb only a good driver can make says nothing about the road. If this fails, the first
## question is whether the road is drivable at all — `road_is_drivable` measures that from its
## geometry, and this measures whether a truck agrees.
##
## What is measured is what the plan asks for and nothing more: the route completes, no node goes
## through the terrain, the rig never stops making progress, nothing comes apart, and the solver's
## energy stays bounded. How well it drives is not the claim; `rig_steers` owns that.

## Long enough for the run at the speed below, with room for the driver to make a mess of the
## approach and still get there.
const LIMIT_S: float = 600.0
## Slow enough for the hairpins, which are about 15 m across.
const TARGET_SPEED_MS: float = 5.0
## The rig's energy may not grow beyond this much of what it settled at. A softbody that is
## gaining energy is one that will eventually explode, whether or not it does so inside the run.
const MAX_ENERGY_RATIO: float = 60.0
## The road is 2,213 m long; allow for a driver that does not hold the centre line exactly.
const MIN_DISTANCE_M: float = 1800.0
## And it has to end up on the ridge: the whole point of the route is the height gained.
const MIN_CLIMB_M: float = 80.0


static func meta() -> Dictionary:
    return {
        "name": "switchback_climb",
        "proves": "the rig climbs the switchback road to the ridge without falling through the terrain, getting stuck or coming apart",
        # driving a route is the driven rig of rig_drives_forward, steered, over terrain.
        "builds_on": ["rig_steers", "road_is_drivable"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "the route completes inside %.0f s; no node more than %.1f m under the terrain;"
            % [LIMIT_S, DriveRoute.FALL_THROUGH_M]
            + " no node over %.0f m/s; energy at most %.0fx the settled rig; at least %.0f m"
            % [DriveRoute.EXPLODE_SPEED_MS, MAX_ENERGY_RATIO, MIN_DISTANCE_M]
            + " driven and %.0f m climbed" % MIN_CLIMB_M
        ),
        "why": (
            "a road that measures as drivable from its geometry and cannot be climbed by a truck"
            + " is a road with a fault the geometry does not describe: not enough traction on the"
            + " surface it is made of, a hairpin tighter than the steering, a grade the gearing"
            + " cannot pull. Only driving it distinguishes those."
        ),
        "budget_s": 180.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var report: Dictionary = await DriveScenario.run(harness, ValleyRoutes.switchback_climb(), {
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
            "the climb did not complete: %s (%.0f m driven, %d waypoints reached, path %s)"
            % [report["reason"] as String, report["distance_m"] as float,
               report["reached"] as int, _path_summary(report["path"] as PackedVector2Array)],
            report["distance_m"]
        )
    if (report["distance_m"] as float) < MIN_DISTANCE_M:
        return fail(
            "the route completed in %.0f m, under the %.0f m of road: the waypoints are not"
            % [report["distance_m"] as float, MIN_DISTANCE_M]
            + " following the climb",
            report["distance_m"]
        )
    if (report["climb_m"] as float) < MIN_CLIMB_M:
        return fail(
            "the route ended %.0f m above where it started, under %.0f m: it did not climb"
            % [report["climb_m"] as float, MIN_CLIMB_M],
            report["climb_m"]
        )
    if (report["energy_ratio"] as float) > MAX_ENERGY_RATIO:
        return fail(
            "the rig's energy reached %.0fx what it settled at, over %.0fx: it is gaining energy"
            % [report["energy_ratio"] as float, MAX_ENERGY_RATIO],
            report["energy_ratio"]
        )
    return ok(
        "climbed %.0f m in %.1f s over %.0f m of road: worst node %.1f m/s, deepest %.2f m"
        % [report["climb_m"] as float, report["seconds"] as float,
           report["distance_m"] as float, report["worst_speed_ms"] as float,
           report["deepest_m"] as float]
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
