extends GateBase
## The rig drives the washout — 240 m of transverse corrugations — without falling through it,
## sticking in it or coming apart in it.
##
## PLAN M1 acceptance 7, one of its three scenarios. This is the one that shakes the rig: the
## corrugations are close to the wheelbase in wavelength, which is the spacing that pitches a
## vehicle rather than merely vibrating it, so the suspension works through its travel hundreds of
## times in a run. A softbody that is quietly gaining energy shows it here long before it shows it
## on a flat lane, which is why the energy bound matters more on this route than on the others.
##
## What is measured is what the plan asks for and nothing more: the route completes, no node goes
## through the terrain, the rig never stops making progress, nothing comes apart, and the solver's
## energy stays bounded. How well it drives is not the claim; `rig_steers` owns that.

## Long enough for the run at the speed below, with room for the driver to make a mess of the
## approach and still get there.
const LIMIT_S: float = 120.0
## Fast enough that the corrugations are driven over rather than crawled across: a rut section
## taken at walking pace is a rut section the suspension barely notices.
const TARGET_SPEED_MS: float = 7.0
## The rig's energy may not grow beyond this much of what it settled at. A softbody that is
## gaining energy is one that will eventually explode, whether or not it does so inside the run.
const MAX_ENERGY_RATIO: float = 60.0
## The washout is 240 m long with 70 m of approach either side.
const MIN_DISTANCE_M: float = 330.0


static func meta() -> Dictionary:
    return {
        "name": "rut_traverse",
        "proves": "the rig drives the washout's corrugations without falling through the terrain, getting stuck or coming apart, and without gaining energy",
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
            "corrugations near the wheelbase in wavelength pitch a vehicle rather than shaking"
            + " it, so this route works the suspension through its travel hundreds of times. A"
            + " solver that is gaining a little energy per contact shows it here first."
        ),
        "budget_s": 180.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var report: Dictionary = await DriveScenario.run(harness, ValleyRoutes.rut_traverse(), {
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
            "the traverse did not complete: %s (%.0f m driven, %d waypoints reached, path %s)"
            % [report["reason"] as String, report["distance_m"] as float,
               report["reached"] as int, _path_summary(report["path"] as PackedVector2Array)],
            report["distance_m"]
        )
    if (report["distance_m"] as float) < MIN_DISTANCE_M:
        return fail(
            "the route completed in %.0f m, under the %.0f m the washout is: the waypoints are"
            % [report["distance_m"] as float, MIN_DISTANCE_M]
            + " not where the corrugations are",
            report["distance_m"]
        )
    if (report["energy_ratio"] as float) > MAX_ENERGY_RATIO:
        return fail(
            "the rig's energy reached %.0fx what it settled at, over %.0fx: it is gaining energy"
            % [report["energy_ratio"] as float, MAX_ENERGY_RATIO],
            report["energy_ratio"]
        )
    return ok(
        "traversed in %.1f s over %.0f m: worst node %.1f m/s, deepest %.2f m into the terrain,"
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
