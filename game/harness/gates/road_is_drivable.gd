extends GateBase
## The climbing road is a road: a continuous corridor at a grade a truck can pull, benched into
## the wall rather than floating over it.
##
## PLAN §0.5 wants a climbing dirt road with switchbacks, and `switchback_backlit` is shot on it.
## A switchback road generated from a polyline has three ways to be wrong that all look fine in
## the layout file: a leg too steep to climb, a hairpin that leaves a step where two legs meet,
## and a corridor that has drifted off the wall so the bench is a 20 m embankment. Each is
## measured here, walking the centre line a metre at a time.
##
## The grade bound is what the hero rig can pull rather than a highway standard. It makes 11 kNm
## at the wheels on a 2,041 kg truck, so grade is not the limit — traction is, and on gravel at
## 0.85 static friction the tyres let go somewhere near 40%. The bound is set well under that,
## because a road that needs the rig's full traction to climb is not a road a camera can follow a
## truck up either.

## Along the centre line.
const MAX_GRADE: float = 0.15
## Between one metre and the next: a step the suspension would read as a kerb.
const MAX_STEP_M: float = 0.25
## How far the terrain at the corridor's edge may sit from the road surface. The bench is a cut
## on the uphill side and a fill on the downhill one, and on a 24% wall a 5 m half width gives
## 1.2 m of each.
const MAX_BENCH_M: float = 2.0
## The corridor's own width, measured by walking across it until the terrain stops being the
## road's surface.
const MIN_WIDTH_M: float = 8.0
## How far the terrain may sit from the road's surface and still count as the road.
const CORRIDOR_TOLERANCE_M: float = 0.05
## And the road has to go somewhere: from the valley floor to the ridge.
const MIN_CLIMB_M: float = 80.0


static func meta() -> Dictionary:
    return {
        "name": "road_is_drivable",
        "proves": "the climbing road is continuous, no steeper than a truck can pull, at least a lane and a half wide, and benched into the wall rather than standing off it",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "grade at most %.0f%%, no step over %.2f m, bench within %.1f m,"
            % [MAX_GRADE * 100.0, MAX_STEP_M, MAX_BENCH_M]
            + " corridor at least %.1f m wide, climbing at least %.0f m" % [
                MIN_WIDTH_M, MIN_CLIMB_M]
        ),
        "why": (
            "the road is generated from a polyline, and the three ways that goes wrong — a leg"
            + " too steep to climb, a step where two legs meet, a corridor that has drifted off"
            + " the wall — all read as reasonable numbers in the layout file. The grade bound is"
            + " the rig's traction on gravel, not a highway standard: at 0.85 static friction"
            + " the tyres let go near 40%, and a road needing that much is not one a camera can"
            + " follow a truck up."
        ),
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var points: Array[Vector2] = ValleyLayout.ROAD_POINTS
    var worst_grade: float = 0.0
    var worst_grade_at: Vector2 = Vector2.ZERO
    var worst_step: float = 0.0
    var worst_step_at: Vector2 = Vector2.ZERO
    var worst_bench: float = 0.0
    var worst_bench_at: Vector2 = Vector2.ZERO
    var narrowest: float = INF
    var narrowest_at: Vector2 = Vector2.ZERO
    var length: float = 0.0

    var previous: Vector2 = points[0]
    var previous_y: float = ValleyShape.height_at_world(previous.x, previous.y)
    for index: int in points.size() - 1:
        var span: Vector2 = points[index + 1] - points[index]
        var steps: int = maxi(1, int(span.length()))
        var side: Vector2 = Vector2(-span.y, span.x).normalized()
        for step: int in range(1, steps + 1):
            var at: Vector2 = points[index] + span * (float(step) / float(steps))
            # The terrain's own height on the centre line, not the road's intended height: a
            # corridor that failed to cut would pass a check that asked the road what it is.
            var y: float = ValleyShape.height_at_world(at.x, at.y)
            var run: float = at.distance_to(previous)
            if run > 0.001:
                var rise: float = absf(y - previous_y)
                length += run
                if rise / run > worst_grade:
                    worst_grade = rise / run
                    worst_grade_at = at
                if rise > worst_step:
                    worst_step = rise
                    worst_step_at = at
            var bench: float = _bench_at(at, side)
            if bench > worst_bench:
                worst_bench = bench
                worst_bench_at = at
            var width: float = _width_at(at, side)
            if width < narrowest:
                narrowest = width
                narrowest_at = at
            previous = at
            previous_y = y

    var start: Vector2 = points[0]
    var end: Vector2 = points[points.size() - 1]
    var climb: float = (
        ValleyShape.height_at_world(end.x, end.y) - ValleyShape.height_at_world(start.x, start.y)
    )

    if worst_grade > MAX_GRADE:
        return fail("the road reaches %.1f%% at %v, over %.0f%%" % [
            worst_grade * 100.0, worst_grade_at, MAX_GRADE * 100.0], worst_grade)
    if worst_step > MAX_STEP_M:
        return fail("the road steps %.2f m at %v, over %.2f m" % [
            worst_step, worst_step_at, MAX_STEP_M], worst_step)
    if worst_bench > MAX_BENCH_M:
        return fail("the bench stands %.2f m off the wall at %v, over %.1f m" % [
            worst_bench, worst_bench_at, MAX_BENCH_M], worst_bench)
    if narrowest < MIN_WIDTH_M:
        return fail("the corridor is %.1f m wide at %v, under %.1f m" % [
            narrowest, narrowest_at, MIN_WIDTH_M], narrowest)
    if climb < MIN_CLIMB_M:
        return fail("the road climbs %.1f m, under %.0f m" % [climb, MIN_CLIMB_M], climb)
    return ok(
        "%.0f m of road climbing %.0f m: worst grade %.1f%% at %v, worst step %.2f m," % [
            length, climb, worst_grade * 100.0, worst_grade_at, worst_step]
        + " bench within %.2f m, narrowest %.1f m" % [worst_bench, narrowest],
        worst_grade
    )


## How far the terrain at the corridor's edges sits from the road surface there: the depth of the
## cut on one side and the height of the fill on the other.
func _bench_at(at: Vector2, side: Vector2) -> float:
    var road: float = ValleyShape.height_at_world(at.x, at.y)
    var worst: float = 0.0
    for edge: Vector2 in [
        at + side * ValleyLayout.ROAD_HALF_WIDTH_M,
        at - side * ValleyLayout.ROAD_HALF_WIDTH_M,
    ]:
        worst = maxf(worst, absf(ValleyShape.floor_y_at(edge.x, edge.y) - road))
    return worst


## How wide the corridor is at a point: walked out from the centre line on both sides until the
## terrain stops being the road.
##
## "Being the road" is the terrain agreeing with the road's own surface, not with the height on
## the centre line. On a hairpin the surface is not level across the corridor — the road's height
## varies along a path that is turning — and asking for level measured 6 m of a 10 m road.
func _width_at(at: Vector2, side: Vector2) -> float:
    return _reach(at, side) + _reach(at, -side)


## How far the terrain stays on the road's own surface in one direction, in metres.
func _reach(at: Vector2, direction: Vector2) -> float:
    var reach: float = 0.0
    for step: int in 60:
        var out: float = float(step) * 0.25
        var edge: Vector2 = at + direction * out
        var road: float = ValleyShape.road_height_at(edge.x, edge.y)
        if absf(ValleyShape.height_at_world(edge.x, edge.y) - road) > CORRIDOR_TOLERANCE_M:
            break
        reach = out
    return reach
