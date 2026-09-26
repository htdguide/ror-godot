class_name ValleyWaterCut
extends RefCounted
## Where water has dug into the valley: the channel that crosses the floor, the drain that runs
## west from it, and the lake basin at the low end.
##
## Extracted from `ValleyShape` as its own responsibility, because the water pass needs the same
## numbers to build a surface over: a river bed and the water on top of it come from one place or
## they disagree, and a shoreline that does not match the basin it sits in is the fault that reads
## as the ground being transparent.
##
## Every function returns a depth below the valley floor in metres, and zero outside its own
## feature. Pure and static, like the shape it is part of.

## The river channel's banks, either side of the crossing.
const RIVER_BANK_M: float = 8.0
## How far across the valley the lake reaches before its basin has narrowed to nothing.
const LAKE_HALF_WIDTH_M: float = 200.0


## How much the water has dug out of the floor at a point: the crossing channel, the drain
## that runs west from it, and the lake basin, taken as whichever is deepest.
static func depth_at(x: float, z: float) -> float:
    return maxf(maxf(crossing_depth(x, z), drain_depth(x, z)), lake_basin_depth(x, z))


## The channel that crosses the floor, shallow in the middle where the ford is.
static func crossing_depth(x: float, z: float) -> float:
    var along: float = absf(x - ValleyLayout.RIVER_CROSS_X_M)
    var half: float = ValleyLayout.RIVER_CROSS_HALF_WIDTH_M
    if along > half or absf(z) > ValleyLayout.SHOULDER_END_M:
        return 0.0
    # The banks: the bed rises to the floor over the outer edge of the channel.
    var banks: float = ValleyShape.ramp(half - along, RIVER_BANK_M)
    var across: float = absf(z)
    var depth: float = ValleyLayout.RIVER_DEPTH_M
    if across <= ValleyLayout.FORD_HALF_WIDTH_M:
        depth = ValleyLayout.FORD_DEPTH_M
    elif across <= ValleyLayout.FORD_HALF_WIDTH_M + ValleyLayout.FORD_RAMP_M:
        var ramp: float = (across - ValleyLayout.FORD_HALF_WIDTH_M) / ValleyLayout.FORD_RAMP_M
        depth = lerpf(ValleyLayout.FORD_DEPTH_M, ValleyLayout.RIVER_DEPTH_M, ramp)
    return depth * banks


## The drain: the river's course west from the crossing to the lake, along the floor's north
## edge. Parabolic across, so its bed is a channel rather than a trench with vertical walls.
static func drain_depth(x: float, z: float) -> float:
    if x > ValleyLayout.RIVER_CROSS_X_M or x < ValleyLayout.LAKE_SHORE_X_M:
        return 0.0
    var across: float = absf(z - ValleyLayout.DRAIN_Z_M) / ValleyLayout.DRAIN_HALF_WIDTH_M
    if across >= 1.0:
        return 0.0
    return ValleyLayout.DRAIN_DEPTH_M * (1.0 - across * across)


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
