extends GateBase
## A scripted route across a terrain somebody else authored completes: the rig does not fall
## through the ground, does not get stuck, and does not explode.
##
## PLAN M1 acceptance 7. It used to be three gates — `switchback_climb`, `ford_crossing` and
## `rut_traverse` — each driving a named feature of a valley this project generated for itself.
## Those features were placed by the same code that then measured them, so what the three gates
## proved was that the generator and the solver agreed; a fault in the terrain reader could not
## reach any of them. They are gone with the valley, and this is what replaces them: the same
## four failure modes, watched over a route on ground an author drew.
##
## The route is derived from the terrain rather than written down. A list of coordinates is a
## list that means something on one map and nothing on the next, which is what made the three
## old gates unportable. So the rig starts where the terrain's own `.terrn2` says a vehicle
## starts, and the waypoints are laid out from there along the first heading whose ground the
## rig can actually climb — sampled off the author's heightmap, not off anything this project
## decided. The gate reports the heading it took and the relief it covered.
##
## What is watched is `DriveRoute`'s own four: a node more than a metre under the drawn terrain,
## no progress for eight seconds, a node over 60 m/s, and solver energy running away. The
## outside side of the fall-through check is the terrain's own heightmap, not the heightfield the
## solver was handed — a heightfield five metres low was once driven on quite happily, with the
## rig floating over the drawn ground and every check reporting nothing wrong.

const TERRAIN_DIR: String = "assets/terrains/lapaz2"
## How the route is laid out from the terrain's own spawn: this many legs of this length, along
## whichever heading is drivable.
const LEG_M: float = 40.0
const LEGS: int = 6
## Headings tried, in order, as turns from the terrain's +x axis. A whole turn in eighths, so a
## spawn in a corner still has somewhere to go.
const HEADINGS: int = 8
## The steepest ground the route may cross, as a rise over the sampled run. The hero truck is a
## lifted 4WD and climbs far more than this; the bound is here so the route is a drive and not a
## rock-crawling test, which is a different claim.
const MAX_GRADE: float = 0.18
## And the route has to cross ground with some shape to it, or this is the flat-plane test with
## more steps.
const MIN_RELIEF_M: float = 1.0
## How long the drive is given, and how fast it is asked to go.
const LIMIT_S: float = 180.0
const TARGET_SPEED_MS: float = 6.0
## How much of the route has to be reached. Every waypoint: a route that counts as completed
## with one leg left is a route whose last leg was never checked.
const MIN_REACHED_SHARE: float = 1.0


static func meta() -> Dictionary:
    return {
        "name": "a_route_across_a_shipped_terrain_completes",
        "proves": "the hero truck drives a scripted route across a shipped Rigs of Rods terrain without falling through the ground, getting stuck, or exploding, with solver energy bounded",
        # the terrain has to import and be drivable at a standstill before a route over it means
        # anything, and the rig has to drive on flat ground first.
        "builds_on": ["ror_terrain_is_drivable", "rig_settles_on_terrain"],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "every one of %d waypoints reached over %.0f m legs; no node more than 1 m under the"
            % [LEGS, LEG_M]
            + " terrain's own heightmap, no stall, no node over 60 m/s, energy bounded; route"
            + " relief at least %.1f m" % MIN_RELIEF_M
        ),
        "why": (
            "PLAN M1 acceptance 7 asked for scripted routes completing without the actor"
            + " falling through, getting stuck or exploding. The three gates that made that"
            + " claim drove features of a valley this project generated, so they compared the"
            + " generator with the solver and a terrain-reading fault could not reach them."
            + " Driving an author's own ground is the version of the claim that can fail."
        ),
        "budget_s": 300.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var directory: String = SourceScan.repo_root().path_join(TERRAIN_DIR)
    if not DirAccess.dir_exists_absolute(directory):
        return ok("skipped: no terrain at %s" % TERRAIN_DIR, 0)
    var loaded: Dictionary = RorTerrain.load_from(directory)
    if (loaded["error"] as String) != "":
        return fail(loaded["error"] as String)
    var terrain_data: RorTerrain = loaded["terrain"] as RorTerrain

    var route: Dictionary = _route(terrain_data)
    if (route["error"] as String) != "":
        return fail(route["error"] as String)
    var waypoints: Array[Vector2] = route["waypoints"] as Array[Vector2]

    var report: Dictionary = await DriveScenario.run(harness, waypoints, {
        "limit_s": LIMIT_S,
        "target_speed_ms": TARGET_SPEED_MS,
    }, terrain_data)
    if report.has("skipped"):
        return ok("skipped: %s" % report["skipped"], 0)
    if (report.get("error", "") as String) != "":
        return fail(report["error"] as String)
    if (report["reason"] as String) != "":
        return fail(
            "%s: driving %.0f deg from the spawn, %s after %.1f s and %.0f m, having reached"
            % [terrain_data.name, route["heading_deg"] as float, report["reason"],
               report["seconds"] as float, report["distance_m"] as float]
            + " %d of %d waypoints" % [report["reached"] as int, waypoints.size() - 1],
            report["distance_m"]
        )
    var reached: int = report["reached"] as int
    var wanted: int = waypoints.size() - 1
    if float(reached) / float(wanted) < MIN_REACHED_SHARE:
        return fail(
            "the route ran out of time having reached %d of %d waypoints in %.1f s"
            % [reached, wanted, report["seconds"] as float],
            float(reached)
        )
    return ok(
        "%s: %.0f m of route %.0f deg from the spawn over %.1f m of relief on %s, all %d"
        % [terrain_data.name, report["distance_m"] as float, route["heading_deg"] as float,
           route["relief_m"] as float, report["surface_at_start"] as String, wanted]
        + " waypoints reached in %.1f s; deepest %.2f m under the drawn ground, worst node"
        % [report["seconds"] as float, report["deepest_m"] as float]
        + " %.1f m/s, energy peaked at %.2f of settled"
        % [report["worst_speed_ms"] as float, report["energy_ratio"] as float],
        report["distance_m"]
    )


## The route: the terrain's own spawn, then `LEGS` legs along the first heading whose ground the
## rig can climb.
##
## Headings are tried in a fixed order and the ground is sampled off the author's heightmap, so
## the answer is the same on every machine. Returns {"waypoints", "heading_deg", "relief_m",
## "error"}.
func _route(terrain_data: RorTerrain) -> Dictionary:
    var out: Dictionary = {
        "error": "", "waypoints": [] as Array[Vector2], "heading_deg": 0.0, "relief_m": 0.0,
    }
    var grid: Dictionary = terrain_data.lattice()
    var span: float = float((grid["size"] as int) - 1) * (grid["spacing"] as float)
    var start: Vector3 = terrain_data.start_position()
    var from: Vector2 = Vector2(start.x, start.z)
    var steepest_seen: float = 0.0
    for step: int in HEADINGS:
        var angle: float = TAU * float(step) / float(HEADINGS)
        var along: Vector2 = Vector2(cos(angle), sin(angle))
        var points: Array[Vector2] = [from]
        var lowest: float = terrain_data.height_at_world(from.x, from.y)
        var highest: float = lowest
        var steepest: float = 0.0
        var inside: bool = true
        for leg: int in LEGS:
            var to: Vector2 = from + along * LEG_M * float(leg + 1)
            if to.x < LEG_M or to.y < LEG_M or to.x > span - LEG_M or to.y > span - LEG_M:
                inside = false
                break
            var here: float = terrain_data.height_at_world(to.x, to.y)
            var previous: float = terrain_data.height_at_world(
                points[points.size() - 1].x, points[points.size() - 1].y
            )
            steepest = maxf(steepest, absf(here - previous) / LEG_M)
            lowest = minf(lowest, here)
            highest = maxf(highest, here)
            points.append(to)
        if not inside:
            continue
        steepest_seen = maxf(steepest_seen, steepest)
        if steepest > MAX_GRADE:
            continue
        if highest - lowest < MIN_RELIEF_M:
            continue
        out["waypoints"] = points
        out["heading_deg"] = rad_to_deg(angle)
        out["relief_m"] = highest - lowest
        return out
    out["error"] = (
        "no heading from %s's own spawn at %.0f, %.0f gives %d legs of %.0f m that are inside"
        % [terrain_data.name, from.x, from.y, LEGS, LEG_M]
        + " the map, under %.0f%% grade and over %.1f m of relief (steepest tried %.0f%%)"
        % [MAX_GRADE * 100.0, MIN_RELIEF_M, steepest_seen * 100.0]
    )
    return out
