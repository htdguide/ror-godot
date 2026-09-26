extends GateBase
## The river's surface descends the whole way from its inlet to the lake, stays above its bed, and
## meets the lake's level without a step.
##
## This is the gate for a fault that was built and shipped in an earlier version of the valley: a
## channel carved at a constant depth below the valley floor. The floor drops 2.9 m from the
## shoulder to the centre line, so a bed that follows it down and back up carries a surface that
## humps 1.9 m in the middle — water flowing uphill into the ford and back down out of it. It looks
## plausible in the layout file, it passes every check that samples a single point, and a person
## looking at the ford sees a ridge of water.
##
## So the whole course is walked, a metre at a time, and three things are measured: the surface
## never rises, the depth never reaches zero except where the ford's bar is, and the drain's mouth
## arrives at the lake's own level.

## The surface may not rise along the course by more than this between samples. Not zero: the
## course is walked in world metres and the elevations are interpolated in floats.
const MAX_RISE_M: float = 0.001
## Water shallower than this is not water. The ford's bar is the shallowest point by design.
const MIN_DEPTH_M: float = 0.2
## The river begins at zero depth — its bed meets its surface at the inlet, so that the water mesh
## thins out instead of ending at a straight edge in the open — so the depth bound starts below
## the head of the channel rather than at it.
const HEAD_M: float = 20.0
## And the ford has to stay crossable: this is wheel-deep on the hero truck, well under its body.
const MAX_FORD_DEPTH_M: float = 0.5
## How closely the drain's mouth has to meet the lake's level. A step here is a waterfall into the
## lake, which is not what a drain does.
const MAX_MOUTH_STEP_M: float = 0.05


static func meta() -> Dictionary:
    return {
        "name": "water_runs_downhill",
        "proves": "the river's surface descends from its inlet to the lake, stays above its bed below the head of the channel, and meets the lake's level without a step",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "no rise over %.3f m along the course; depth at least %.1f m below the first %.0f m;"
            % [MAX_RISE_M, MIN_DEPTH_M, HEAD_M]
            + " ford at most %.1f m; mouth within %.2f m of the lake"
            % [MAX_FORD_DEPTH_M, MAX_MOUTH_STEP_M]
        ),
        "why": (
            "a channel carved at a constant depth below the valley floor follows the floor down"
            + " and back up, so its surface humps 1.9 m in the middle and the water runs uphill"
            + " into the ford. That version existed, read reasonably in the layout file, and"
            + " passed every check that sampled one point."
        ),
        "budget_s": 10.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var crossing: Dictionary = _walk_crossing()
    var drain: Dictionary = _walk_drain()
    var worst_rise: float = maxf(crossing["rise"] as float, drain["rise"] as float)
    var rise_at: Vector2 = (
        crossing["rise_at"] as Vector2
        if (crossing["rise"] as float) >= (drain["rise"] as float)
        else drain["rise_at"] as Vector2
    )
    if worst_rise > MAX_RISE_M:
        return fail(
            "the river's surface rises %.3f m at %v: the water is running uphill"
            % [worst_rise, rise_at],
            worst_rise
        )

    var shallowest: float = minf(crossing["shallowest"] as float, drain["shallowest"] as float)
    var shallow_at: Vector2 = (
        crossing["shallow_at"] as Vector2
        if (crossing["shallowest"] as float) <= (drain["shallowest"] as float)
        else drain["shallow_at"] as Vector2
    )
    if shallowest < MIN_DEPTH_M:
        return fail(
            "the river is %.3f m deep at %v, under %.1f m: its bed has come through its surface"
            % [shallowest, shallow_at, MIN_DEPTH_M],
            shallowest
        )

    var ford: float = ValleyWaterCut.ford_depth()
    if ford > MAX_FORD_DEPTH_M or ford < MIN_DEPTH_M:
        return fail(
            "the ford is %.2f m deep, outside the %.1f to %.1f m a truck crosses"
            % [ford, MIN_DEPTH_M, MAX_FORD_DEPTH_M],
            ford
        )

    var step: float = absf((drain["mouth"] as float) - ValleyShape.lake_water_y())
    if step > MAX_MOUTH_STEP_M:
        return fail(
            "the drain arrives at %.3f m against a lake at %.3f m, a step of %.3f m"
            % [drain["mouth"] as float, ValleyShape.lake_water_y(), step],
            step
        )

    return ok(
        "the course falls %.2f m from %.2f m at the inlet to the lake at %.2f m," % [
            (crossing["top"] as float) - ValleyShape.lake_water_y(),
            crossing["top"] as float,
            ValleyShape.lake_water_y(),
        ]
        + " never rising; depth %.2f m at the shallowest, %.2f m over the ford;" % [
            shallowest, ford]
        + " the mouth meets the lake within %.3f m" % step,
        shallowest
    )


## Across the valley, from the inlet down to the junction.
func _walk_crossing() -> Dictionary:
    var x: float = ValleyLayout.RIVER_CROSS_X_M
    var from: float = ValleyLayout.RIVER_INLET_Z_M
    var to: float = ValleyLayout.DRAIN_Z_M
    return _walk(int(from - to) + 1 - int(HEAD_M), func(step: int) -> Vector2:
        return Vector2(x, from - HEAD_M - float(step))
    )


## West from the junction to the lake's mouth.
func _walk_drain() -> Dictionary:
    var z: float = ValleyLayout.DRAIN_Z_M
    var from: float = ValleyLayout.RIVER_CROSS_X_M
    var to: float = ValleyLayout.LAKE_SHORE_X_M
    return _walk(int(from - to) + 1, func(step: int) -> Vector2:
        return Vector2(from - float(step), z)
    )


## Walks a course a metre at a time, reporting the worst rise, the shallowest depth, the surface it
## started at and the surface it ended at.
func _walk(samples: int, position_of: Callable) -> Dictionary:
    var rise: float = 0.0
    var rise_at: Vector2 = Vector2.ZERO
    var shallowest: float = INF
    var shallow_at: Vector2 = Vector2.ZERO
    var top: float = -INF
    var mouth: float = 0.0
    var previous: float = INF
    for step: int in samples:
        var at: Vector2 = position_of.call(step) as Vector2
        var water: float = ValleyWaterCut.river_water_y(at.x, at.y)
        if not is_finite(water):
            continue
        if is_finite(previous) and water - previous > rise:
            rise = water - previous
            rise_at = at
        previous = water
        if top == -INF:
            top = water
        mouth = water
        var depth: float = water - ValleyShape.height_at_world(at.x, at.y)
        if depth < shallowest:
            shallowest = depth
            shallow_at = at
    return {
        "rise": rise,
        "rise_at": rise_at,
        "shallowest": shallowest,
        "shallow_at": shallow_at,
        "top": top,
        "mouth": mouth,
    }
