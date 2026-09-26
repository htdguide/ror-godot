extends GateBase
## Every feature the shot list names exists in the terrain, at a size worth photographing.
##
## PLAN §0.5 lists what Valley One has to contain and eight money shots that each need one of
## those things in frame. Six of the eight named content that did not exist, so the shot list was
## blocked on the scene rather than on the shots. This gate is what stops that happening
## silently again: it measures the terrain for each feature and fails naming the one that is
## missing.
##
## It is an invariant rather than an outside oracle. There is no authority that says a valley
## contains a lake — the plan does — so what is checked is that the shape function actually
## produces each feature at the scale the plan asks for, rather than that some third party
## agrees it should. What the *rig* makes of them is the drivability work, which is a separate
## claim measured by driving.
##
## Sampled against `ValleyShape` and not against a built terrain: the two are the same numbers
## by construction, `terrain_collision_agreement` is what proves that, and sampling the function
## costs milliseconds instead of a terrain build.

## Each feature, and the smallest version of it that is still the feature. A relief is what a
## camera and a suspension both read, so each bound is a height or a depth in metres.
const MIN_LAKE_DEPTH_M: float = 6.0
## And the basin has to be dug, not merely flooded. Measured separately because the two come
## apart: the valley floor descends under a flat water level, so the lake is metres deep even
## with no basin at all — which is how a first version of this gate passed with the basin set to
## half a metre.
const MIN_LAKE_BASIN_M: float = 4.0
const MIN_RIVER_DEPTH_M: float = 2.0
## The ford is a bar in the bed, and this is how far it has to stand above the channel either side
## of it. How much water stands *over* the bar is a different claim, and `water_runs_downhill`
## makes it: measuring the bar against the valley floor instead, as a first version of this gate
## did, measures the channel's own depth and fails as soon as the river is regraded.
const MIN_FORD_BAR_M: float = 0.4
const MIN_WASHOUT_M: float = 0.2
const MIN_SHELF_CROSSFALL: float = 0.06
const MAX_SHELF_CROSSFALL: float = 0.25
const MIN_ROAD_CLIMB_M: float = 80.0
const MIN_RIDGE_M: float = 80.0
## The straight: the test track has to stay flat enough to be one, or the driving gates that
## spawn on it are measuring a hill.
const MAX_TRACK_RELIEF_M: float = 3.0


static func meta() -> Dictionary:
    return {
        "name": "valley_has_its_features",
        "proves": "the valley contains each feature the money shots name — lake, river, ford, washout, rock shelf, climbing road, ridge — at the size the plan asks for",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "lake at least %.0f m deep, river %.1f m, a ford bar %.1f m above the channel,"
            % [MIN_LAKE_DEPTH_M, MIN_RIVER_DEPTH_M, MIN_FORD_BAR_M]
            + " washout %.2f m, shelf crossfall %.0f%% to %.0f%%, road climb %.0f m,"
            % [MIN_WASHOUT_M, MIN_SHELF_CROSSFALL * 100.0, MAX_SHELF_CROSSFALL * 100.0,
               MIN_ROAD_CLIMB_M]
            + " ridge %.0f m above the floor, and the test track flat to %.1f m"
            % [MIN_RIDGE_M, MAX_TRACK_RELIEF_M]
        ),
        "why": (
            "six of the eight money shots name content that did not exist when the shot list"
            + " was written, so the list was blocked on the scene and nothing said so. A"
            + " feature that is present but too small to read is the same failure with a"
            + " passing check, which is why each bound is a measured relief rather than a"
            + " flag."
        ),
        "budget_s": 10.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var checks: Array = [
        _lake(), _river(), _ford(), _washout(), _shelf(), _road(), _ridge(), _track(),
    ]
    var reported: PackedStringArray = PackedStringArray()
    for check: Dictionary in checks:
        if not bool(check["pass"]):
            return fail(check["detail"] as String, check["measured"])
        reported.append(check["detail"] as String)
    return ok(", ".join(reported), checks.size())


func _lake() -> Dictionary:
    var deepest: float = 0.0
    var basin: float = 0.0
    for step: int in 300:
        var x: float = ValleyLayout.LAKE_SHORE_X_M - float(step)
        var bed: float = ValleyShape.height_at_world(x, 0.0)
        deepest = maxf(deepest, ValleyShape.lake_water_y() - bed)
        basin = maxf(basin, ValleyShape.floor_y_at(x, 0.0) - bed)
    if basin < MIN_LAKE_BASIN_M:
        return _no("the lake basin is dug %.2f m below the valley floor, under %.1f m" % [
            basin, MIN_LAKE_BASIN_M], basin)
    if deepest < MIN_LAKE_DEPTH_M:
        return _no("the lake is %.2f m deep at its deepest, under the %.1f m a lake reads as"
            % [deepest, MIN_LAKE_DEPTH_M], deepest)
    return _yes("lake %.1f m deep over a %.1f m basin" % [deepest, basin], deepest)


func _river() -> Dictionary:
    var cross_x: float = ValleyLayout.RIVER_CROSS_X_M
    var deepest: float = 0.0
    for step: int in 130:
        var z: float = float(step)
        deepest = maxf(
            deepest,
            ValleyShape.floor_y_at(cross_x, z) - ValleyShape.height_at_world(cross_x, z)
        )
    if deepest < MIN_RIVER_DEPTH_M:
        return _no("the river channel is %.2f m deep, under %.1f m" % [
            deepest, MIN_RIVER_DEPTH_M], deepest)
    return _yes("river channel %.1f m" % deepest, deepest)


## The ford: a bar across the channel where the driving line crosses it.
func _ford() -> Dictionary:
    var cross_x: float = ValleyLayout.RIVER_CROSS_X_M
    var aside: float = ValleyLayout.FORD_HALF_WIDTH_M + ValleyLayout.FORD_RAMP_M + 5.0
    var bar: float = ValleyShape.height_at_world(cross_x, 0.0)
    var channel: float = minf(
        ValleyShape.height_at_world(cross_x, aside),
        ValleyShape.height_at_world(cross_x, -aside)
    )
    var stands: float = bar - channel
    if stands < MIN_FORD_BAR_M:
        return _no("the ford's bar stands %.2f m above the channel beside it, under %.1f m" % [
            stands, MIN_FORD_BAR_M], stands)
    return _yes("ford bar %.2f m" % stands, stands)


func _washout() -> Dictionary:
    var lowest: float = INF
    var highest: float = -INF
    for step: int in 2400:
        var x: float = ValleyLayout.RUTS_WEST_M + float(step) * 0.1
        var relief: float = ValleyShape.height_at_world(x, 0.0) - ValleyShape.floor_y_at(x, 0.0)
        lowest = minf(lowest, relief)
        highest = maxf(highest, relief)
    var washout: float = highest - lowest
    if washout < MIN_WASHOUT_M:
        return _no("the washout is %.3f m peak to trough, under %.2f m" % [
            washout, MIN_WASHOUT_M], washout)
    return _yes("washout %.2f m" % washout, washout)


## The rock shelf's crossfall, taken between two lines along it rather than at a point, so a bump
## cannot stand in for a tilt.
func _shelf() -> Dictionary:
    var mid_x: float = 0.5 * (ValleyLayout.ROCK_WEST_M + ValleyLayout.ROCK_EAST_M)
    var inner_z: float = ValleyLayout.ROCK_INNER_Z_M + 20.0
    var outer_z: float = ValleyLayout.ROCK_OUTER_Z_M - 20.0
    var inner: float = 0.0
    var outer: float = 0.0
    var samples: int = 40
    for step: int in samples:
        var x: float = mid_x - 40.0 + float(step) * 2.0
        inner += ValleyShape.height_at_world(x, inner_z)
        outer += ValleyShape.height_at_world(x, outer_z)
    var crossfall: float = (outer - inner) / float(samples) / (outer_z - inner_z)
    if crossfall < MIN_SHELF_CROSSFALL or crossfall > MAX_SHELF_CROSSFALL:
        return _no("the rock shelf's crossfall is %.1f%%, outside %.0f%% to %.0f%%" % [
            crossfall * 100.0, MIN_SHELF_CROSSFALL * 100.0, MAX_SHELF_CROSSFALL * 100.0
        ], crossfall)
    return _yes("shelf crossfall %.1f%%" % (crossfall * 100.0), crossfall)


func _road() -> Dictionary:
    var points: Array[Vector2] = ValleyLayout.ROAD_POINTS
    var start: Vector2 = points[0]
    var end: Vector2 = points[points.size() - 1]
    # The terrain's height on the road, not the road's intended height: a road that never cut
    # into the wall would pass a check that asked the road what it is.
    var climb: float = (
        ValleyShape.height_at_world(end.x, end.y) - ValleyShape.height_at_world(start.x, start.y)
    )
    if climb < MIN_ROAD_CLIMB_M:
        return _no("the road climbs %.1f m, under %.0f m" % [climb, MIN_ROAD_CLIMB_M], climb)
    return _yes("road climbs %.0f m" % climb, climb)


func _ridge() -> Dictionary:
    var ridge: float = ValleyShape.across_y(ValleyLayout.WALL_END_M + 100.0)
    if ridge < MIN_RIDGE_M:
        return _no("the ridge is %.1f m above the floor, under %.0f m" % [
            ridge, MIN_RIDGE_M], ridge)
    return _yes("ridge %.0f m" % ridge, ridge)


## The test track is the part of the valley that must not have changed: the driving gates spawn
## on it and a hill under them would be measured as a solver fault.
func _track() -> Dictionary:
    var lowest: float = INF
    var highest: float = -INF
    for step: int in int(ValleyLayout.TRACK_EAST_M - ValleyLayout.TRACK_WEST_M) + 1:
        var y: float = ValleyShape.height_at_world(ValleyLayout.TRACK_WEST_M + float(step), 0.0)
        lowest = minf(lowest, y)
        highest = maxf(highest, y)
    var relief: float = highest - lowest
    if relief > MAX_TRACK_RELIEF_M:
        return _no("the test track's centre line varies by %.2f m, over %.1f m" % [
            relief, MAX_TRACK_RELIEF_M], relief)
    return _yes("track flat to %.2f m" % relief, relief)


func _yes(detail: String, measured: float) -> Dictionary:
    return {"pass": true, "detail": detail, "measured": measured}


func _no(detail: String, measured: float) -> Dictionary:
    return {"pass": false, "detail": detail, "measured": measured}
