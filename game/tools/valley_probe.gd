extends SceneTree
## Reports what the valley's shape actually is, feature by feature.
##
##   godot --path game --headless --script res://tools/valley_probe.gd
##
## The shape is generated from `ValleyLayout` by `ValleyShape`, so every number a layout change
## moves — the road's grade, the ford's depth, the shelf's crossfall, where the shoreline lands
## — is a consequence rather than a setting. This prints them, which is what makes a layout
## edit reviewable without opening a window.


func _initialize() -> void:
    _floor()
    _road()
    _water()
    _features()
    _surfaces()
    quit(0)


func _floor() -> void:
    var lowest: float = INF
    var highest: float = -INF
    for step: int in 601:
        var x: float = ValleyLayout.TRACK_WEST_M + float(step)
        var y: float = ValleyShape.height_at_world(x, 0.0)
        lowest = minf(lowest, y)
        highest = maxf(highest, y)
    print("track centre line: %.2f m to %.2f m over %.0f m" % [
        lowest, highest, ValleyLayout.TRACK_EAST_M - ValleyLayout.TRACK_WEST_M])
    print("spawn: %.3f m; valley floor at the lake shore: %.2f m; at the east end: %.2f m" % [
        ValleyShape.height_at_world(0.0, 0.0),
        ValleyShape.height_at_world(ValleyLayout.LAKE_SHORE_X_M, 0.0),
        ValleyShape.height_at_world(950.0, 0.0)])
    print("wall: %.1f m at the shoulder, %.1f m at the top, ridge %.1f m" % [
        ValleyShape.across_y(ValleyLayout.SHOULDER_END_M),
        ValleyShape.across_y(ValleyLayout.WALL_END_M),
        ValleyShape.across_y(ValleyLayout.WALL_END_M + 120.0)])


## Walks the road's centre line at a metre a step, segment by segment: the grade each leg
## achieves, and how deep a cut or how high a fill the bench needs against the wall either side.
func _road() -> void:
    var points: Array[Vector2] = ValleyLayout.ROAD_POINTS
    var total_length: float = 0.0
    var total_climb: float = 0.0
    var worst_grade: float = 0.0
    var worst_cut: float = 0.0
    for index: int in points.size() - 1:
        var span: Vector2 = points[index + 1] - points[index]
        var steps: int = maxi(1, int(span.length()))
        var side: Vector2 = Vector2(-span.y, span.x).normalized()
        var previous: Vector2 = points[index]
        var previous_y: float = ValleyShape.road_height_at(previous.x, previous.y)
        var grade: float = 0.0
        var cut: float = 0.0
        var climb: float = 0.0
        var length: float = 0.0
        for step: int in range(1, steps + 1):
            var at: Vector2 = points[index] + span * (float(step) / float(steps))
            var y: float = ValleyShape.road_height_at(at.x, at.y)
            var run: float = at.distance_to(previous)
            if run > 0.001:
                grade = maxf(grade, absf(y - previous_y) / run)
                climb += y - previous_y
                length += run
            for edge: Vector2 in [
                at + side * ValleyLayout.ROAD_HALF_WIDTH_M,
                at - side * ValleyLayout.ROAD_HALF_WIDTH_M,
            ]:
                var wall: float = ValleyShape.across_y(edge.y) + ValleyShape.along_y(edge.x)
                cut = maxf(cut, absf(wall - y))
            previous = at
            previous_y = y
        total_length += length
        total_climb += maxf(0.0, climb)
        worst_grade = maxf(worst_grade, grade)
        worst_cut = maxf(worst_cut, cut)
        print("  road leg %2d %v to %v: %4.0f m, %+6.1f m, worst grade %5.1f%%, cut %.2f m" % [
            index, points[index], points[index + 1], length, climb, grade * 100.0, cut])
    print("road: %.0f m long, climbs %.1f m, worst grade %.1f%%, worst cut or fill %.2f m" % [
        total_length, total_climb, worst_grade * 100.0, worst_cut])


func _water() -> void:
    var cross_x: float = ValleyLayout.RIVER_CROSS_X_M
    # Against the floor at the same place rather than a neighbouring one: the ripple moves the
    # floor by more than the ford is deep, so a bank sampled a few metres away is not a datum.
    var ford_bed: float = ValleyShape.height_at_world(cross_x, 0.0)
    var channel_bed: float = ValleyShape.height_at_world(cross_x, 60.0)
    var floor_y: float = ValleyShape.floor_y_at(cross_x, 0.0)
    print("ford: bed %.2f m under a floor of %.2f m, so carved %.2f m deep;" % [
        ford_bed, floor_y, floor_y - ford_bed]
        + " channel bed %.2f m, %.2f m deep; water over the ford %.2f m" % [
            channel_bed, ValleyShape.floor_y_at(cross_x, 60.0) - channel_bed,
            ValleyLayout.RIVER_WATER_DEPTH_M])
    var deepest: float = INF
    var shore_at: float = 0.0
    for step: int in 260:
        var x: float = ValleyLayout.LAKE_SHORE_X_M + 20.0 - float(step)
        var bed: float = ValleyShape.height_at_world(x, 0.0)
        deepest = minf(deepest, bed)
        if bed <= ValleyShape.lake_water_y() and shore_at == 0.0:
            shore_at = x
    print("lake: water %.2f m, deepest bed %.2f m, so %.2f m deep; shoreline at x %.0f m" % [
        ValleyShape.lake_water_y(), deepest, ValleyShape.lake_water_y() - deepest, shore_at])


func _features() -> void:
    var lowest: float = INF
    var highest: float = -INF
    for step: int in 2400:
        var x: float = ValleyLayout.RUTS_WEST_M + float(step) * 0.1
        # The corrugation alone: the floor it rides on, ripple and grade, taken back off.
        var y: float = (
            ValleyShape.height_at_world(x, 0.0)
            - ValleyShape.along_y(x)
            - ValleyLayout.RIPPLE_HEIGHT_M * sin(x / ValleyLayout.RIPPLE_WAVELENGTH_M * TAU)
        )
        lowest = minf(lowest, y)
        highest = maxf(highest, y)
    print("washout: %.3f m peak to trough, wavelength %.1f m" % [
        highest - lowest, ValleyLayout.RUTS_WAVELENGTH_M])

    var mid_x: float = 0.5 * (ValleyLayout.ROCK_WEST_M + ValleyLayout.ROCK_EAST_M)
    var inner: float = ValleyShape.height_at_world(mid_x, ValleyLayout.ROCK_INNER_Z_M + 20.0)
    var outer: float = ValleyShape.height_at_world(mid_x, ValleyLayout.ROCK_OUTER_Z_M - 20.0)
    var run: float = (ValleyLayout.ROCK_OUTER_Z_M - 20.0) - (ValleyLayout.ROCK_INNER_Z_M + 20.0)
    print("rock shelf: %.1f m across, rising %.2f m, so %.1f%% crossfall" % [
        run, outer - inner, (outer - inner) / run * 100.0])


## Every surface the valley lays down, and where the first patch of each one is.
func _surfaces() -> void:
    var found: Dictionary = {}
    var size: int = TerrainCfg.MAP_SIZE
    for x_index: int in range(0, size, 16):
        for z_index: int in range(0, size, 16):
            var index: int = ValleyShape.surface_at(x_index, z_index)
            if not found.has(index):
                found[index] = ValleyShape.world_of(x_index, z_index)
    for index: int in GroundModels.ORDER.size():
        var name: String = GroundModels.ORDER[index]
        if found.has(index):
            print("surface %-9s first at %v" % [name, found[index]])
        else:
            print("surface %-9s MISSING from the whole map" % name)
