class_name ValleyRoutes
extends RefCounted
## The three routes PLAN M1 acceptance 7 names, as waypoints on the valley's x/z plane.
##
## They are derived from the layout rather than written down beside it: the ford route crosses
## where the river crosses, the washout route runs through where the corrugations are, and the
## climb follows the road's own control points. Move a feature and its route moves with it, which
## is the only way a scenario stays a test of the thing it is named after.

## How far apart the waypoints on a straight run are. Close enough that the driver steers rather
## than aims, far enough that it is not following a rail.
const STRAIGHT_STEP_M: float = 30.0
## And on the climb, where the road turns.
const ROAD_STEP_M: float = 35.0


## Along the valley floor and through the ford, starting well clear of the channel.
static func ford_crossing() -> Array[Vector2]:
    return _along_centre_line(
        ValleyLayout.RIVER_CROSS_X_M + 160.0, ValleyLayout.RIVER_CROSS_X_M - 140.0
    )


## Along the valley floor and through the corrugations.
static func rut_traverse() -> Array[Vector2]:
    return _along_centre_line(
        ValleyLayout.RUTS_WEST_M - 70.0, ValleyLayout.RUTS_EAST_M + 70.0
    )


## Up the switchbacks, following the road's own centre line.
static func switchback_climb() -> Array[Vector2]:
    var out: Array[Vector2] = []
    var points: Array[Vector2] = ValleyLayout.ROAD_POINTS
    out.append(points[0])
    for index: int in points.size() - 1:
        var span: Vector2 = points[index + 1] - points[index]
        var steps: int = maxi(1, int(span.length() / ROAD_STEP_M))
        for step: int in range(1, steps + 1):
            out.append(points[index] + span * (float(step) / float(steps)))
    return out


## A straight run down the middle of the valley floor, in whichever direction the ends imply.
static func _along_centre_line(from_x: float, to_x: float) -> Array[Vector2]:
    var out: Array[Vector2] = []
    var span: float = to_x - from_x
    var steps: int = maxi(1, int(absf(span) / STRAIGHT_STEP_M))
    for step: int in steps + 1:
        out.append(Vector2(from_x + span * (float(step) / float(steps)), 0.0))
    return out
