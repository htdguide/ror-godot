class_name ValleyWaterCut
extends RefCounted
## The river: where its bed is, and where its surface is.
##
## Both come from one place, because a bed and the water on top of it disagree as soon as they are
## declared separately, and the way that shows up is water standing above dry ground or a river
## running uphill.
##
## The course is three points. The river enters over the south shoulder at the inlet, runs north
## across the valley floor to the junction, and turns west down the drain to the lake's mouth. The
## bed and the surface are *graded*: an elevation at each point, interpolated along the course.
##
## Grading is the part that took a second attempt. A constant-depth cut — always 2.6 m below the
## valley floor — is the obvious way to carve a river, and it makes water flow uphill: the floor
## drops 2.9 m from the shoulder to the centre line, so a bed that follows it down and back up
## carries a surface that humps in the middle. With the bed graded, the ford becomes a bar: a rise
## in the bed toward a surface that is still descending, which is what a ford is.
##
## Every depth function returns metres below the valley floor, and zero outside its own feature.
## Pure and static, like the shape it is part of.

## The channel's banks, either side of the crossing: how far the cut tapers out to the floor.
const RIVER_BANK_M: float = 8.0
## How far across the valley the lake reaches before its basin has narrowed to nothing.
const LAKE_HALF_WIDTH_M: float = 200.0
## Anything shallower than this is not water.
const MIN_DEPTH_M: float = 0.01


## How much the water has dug out of the floor at a point: the crossing channel, the drain that
## runs west from it, and the lake basin, taken as whichever is deepest.
static func depth_at(x: float, z: float) -> float:
    return maxf(maxf(crossing_depth(x, z), drain_depth(x, z)), lake_basin_depth(x, z))


## The water surface at a point of the river, or `INF` where the river is not.
##
## Used to build the water mesh and to measure the ford, so what is drawn and what is measured are
## the same number.
static func river_water_y(x: float, z: float) -> float:
    if crossing_depth(x, z) > MIN_DEPTH_M:
        return crossing_water_y(z)
    if drain_depth(x, z) > MIN_DEPTH_M:
        return drain_water_y(x)
    return INF


## How much water stands over the ford, in metres: the bar the driving line crosses.
static func ford_depth() -> float:
    var x: float = ValleyLayout.RIVER_CROSS_X_M
    return crossing_water_y(0.0) - ValleyShape.height_at_world(x, 0.0)


## --- The river's surface, and the bed under it -----------------------------------------------


## The highest the water may sit at a point: the valley's own profile there, less the ripple's
## amplitude and the freeboard.
##
## The ripple is subtracted as an amplitude rather than evaluated, which is the whole trick. The
## profile without it is smooth and descends wherever the valley does, so a surface derived from
## it descends too; taking the amplitude off as a constant then guarantees the surface is under
## the lowest the ground actually gets. Evaluating the ripple instead would put the surface under
## the ground at every point *and* make it rise and fall with the ground, which is water running
## uphill again.
static func _surface_bound(x: float, z: float) -> float:
    return (
        ValleyShape.across_y(z)
        + ValleyShape.along_y(x)
        - ValleyLayout.RIPPLE_HEIGHT_M
        - ValleyLayout.RIVER_FREEBOARD_M
    )


## The water surface where the river crosses the valley floor, whether or not there is water at a
## given point of it. The mesh builder wants the surface everywhere across the channel, including
## at the banks where the depth has gone to zero; `river_water_y` is the masked version, for
## measuring water that is actually there.
static func crossing_water_y(z: float) -> float:
    return _surface_bound(ValleyLayout.RIVER_CROSS_X_M, z)


## The water surface down the drain. It stops falling at the lake's own level, which is how the
## two meet without a step: below that point the drain is simply under the lake.
static func drain_water_y(x: float) -> float:
    return maxf(ValleyLayout.LAKE_WATER_Y_M, _surface_bound(x, ValleyLayout.DRAIN_Z_M))


## How deep the channel is under its surface at a point of the course, given how far along the
## course that point is: nothing at the head, the full depth once the river has run RIVER_HEAD_M,
## and the ford's own depth over the bar.
static func _channel_depth(travelled: float, across_ford: float) -> float:
    var deepening: float = ValleyShape.ramp(travelled, ValleyLayout.RIVER_HEAD_M)
    var depth: float = ValleyLayout.RIVER_CHANNEL_DEPTH_M * deepening
    if across_ford > ValleyLayout.FORD_HALF_WIDTH_M + ValleyLayout.FORD_RAMP_M:
        return depth
    var ford: float = minf(ValleyLayout.FORD_DEPTH_M, depth)
    if across_ford <= ValleyLayout.FORD_HALF_WIDTH_M:
        return ford
    var ramp: float = (across_ford - ValleyLayout.FORD_HALF_WIDTH_M) / ValleyLayout.FORD_RAMP_M
    return lerpf(ford, depth, smoothstep(0.0, 1.0, ramp))


## The channel that crosses the floor: the floor cut down to the bed, tapering out to the banks
## either side.
static func crossing_depth(x: float, z: float) -> float:
    var along: float = absf(x - ValleyLayout.RIVER_CROSS_X_M)
    var half: float = ValleyLayout.RIVER_CROSS_HALF_WIDTH_M
    if along > half or z > ValleyLayout.RIVER_INLET_Z_M or z < ValleyLayout.DRAIN_Z_M:
        return 0.0
    var banks: float = ValleyShape.ramp(half - along, RIVER_BANK_M)
    var bed: float = crossing_water_y(z) - _channel_depth(
        ValleyLayout.RIVER_INLET_Z_M - z, absf(z)
    )
    return maxf(0.0, ValleyShape.floor_y_at(x, z) - bed) * banks


## The drain: the river's course west from the junction to the lake. Parabolic across, so its bed
## is a channel rather than a trench with vertical walls.
static func drain_depth(x: float, z: float) -> float:
    if x > ValleyLayout.RIVER_CROSS_X_M or x < ValleyLayout.LAKE_SHORE_X_M:
        return 0.0
    var across: float = absf(z - ValleyLayout.DRAIN_Z_M) / ValleyLayout.DRAIN_HALF_WIDTH_M
    if across >= 1.0:
        return 0.0
    # Travelled far enough for the channel to be at full depth: the head is up on the crossing.
    var bed: float = drain_water_y(x) - _channel_depth(ValleyLayout.RIVER_HEAD_M, INF)
    var cut: float = ValleyShape.floor_y_at(x, ValleyLayout.DRAIN_Z_M) - bed
    return maxf(0.0, cut) * (1.0 - across * across)


## The lake basin at the west end: a shore that ramps down to a floor, narrowing to nothing
## against the valley walls.
static func lake_basin_depth(x: float, z: float) -> float:
    if x > ValleyLayout.LAKE_SHORE_X_M:
        return 0.0
    var along: float = (
        (ValleyLayout.LAKE_SHORE_X_M - x)
        / (ValleyLayout.LAKE_SHORE_X_M - ValleyLayout.LAKE_FLOOR_X_M)
    )
    along = smoothstep(0.0, 1.0, minf(along, 1.0))
    var across: float = absf(z)
    var edge: float = 1.0
    if across > ValleyLayout.FLOOR_HALF_WIDTH_M:
        edge = 1.0 - smoothstep(
            ValleyLayout.FLOOR_HALF_WIDTH_M, LAKE_HALF_WIDTH_M, minf(across, LAKE_HALF_WIDTH_M)
        )
    return ValleyLayout.LAKE_DEPTH_M * along * edge
