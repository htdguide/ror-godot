class_name ValleyShape
extends RefCounted
## Turns `ValleyLayout` into a height and a surface at any point of the valley.
##
## Pure and static: the same grid coordinates give the same terrain on any machine, with no
## seed and no state. That is what lets the renderer, the solver's heightfield and the gates
## each ask independently and get the same answer — the heightmap Terrain3D draws and the
## surface map the tyres grip on are two reads of this one function, not two copies of a
## result.
##
## Everything is composed in a fixed order, and the order is the design: the valley profile
## first, then the features that modify the floor (the washout, then the water cuts in
## `ValleyWaterCut`), then the ones that cut into a wall (the rock shelf, the road). A cut wins
## over what it cuts into, which is why the road is last.
##
## Heights are metres. `x` and `z` arguments named `index` are terrain grid indices; everything
## else is world metres.

## How far outside its own extent a cut blends back into the terrain.
const FEATURE_BLEND_M: float = 12.0
## Lane count comes from the surface palette; the floor is divided evenly between them.
const LANE_COUNT: int = 9

## Surface indices, resolved once rather than per texel.
##
## `GroundModels.index_of` is a search through an array of names, and the surface map asks for
## one index per cell: at 4.2 M cells that search was most of what generating the valley cost.
## Measured, resolving the names once took the surface pass from 8.1 s to 1.9 s.
static var _road_index: int = GroundModels.index_of(ValleyLayout.ROAD_SURFACE)
static var _rock_index: int = GroundModels.index_of(ValleyLayout.ROCK_SURFACE)
static var _river_index: int = GroundModels.index_of(ValleyLayout.RIVER_SURFACE)
static var _ruts_index: int = GroundModels.index_of(ValleyLayout.RUTS_SURFACE)
static var _wall_index: int = GroundModels.index_of(ValleyLayout.WALL_SURFACE)
static var _ridge_index: int = GroundModels.index_of(ValleyLayout.RIDGE_SURFACE)
static var _lane_indices: PackedByteArray = _build_lane_indices()
## The band of z the road and its blend can reach, taken from the road's own control points.
## Every cell outside it skips the segment loop, which is what keeps a 4.2 M cell map affordable;
## deriving the band rather than writing it down is what stops the road being silently clipped
## when a control point moves, which cost the road's apron 2.5 m of its width.
static var _road_z_min: float = _road_z_extent(true)
static var _road_z_max: float = _road_z_extent(false)


## The world position of a terrain grid cell, in the x/z plane.
static func world_of(x_index: int, z_index: int) -> Vector2:
    return Vector2(
        TerrainCfg.ORIGIN.x + float(x_index) * TerrainCfg.VERTEX_SPACING,
        TerrainCfg.ORIGIN.z + float(z_index) * TerrainCfg.VERTEX_SPACING
    )


## The valley's height at a grid cell, in metres.
static func height_at(x_index: int, z_index: int) -> float:
    var world: Vector2 = world_of(x_index, z_index)
    return height_at_world(world.x, world.y)


## The valley's height at a world position on the x/z plane, in metres.
static func height_at_world(x: float, z: float) -> float:
    var y: float = across_y(z) + along_y(x) + _ripple(x, z)
    y += _ruts(x, z)
    y -= ValleyWaterCut.depth_at(x, z)
    y = _rock_shelf(x, z, y)
    return _road_bench(x, z, y)


## Which surface is at a grid cell, as an index into `GroundModels.ORDER`.
static func surface_at(x_index: int, z_index: int) -> int:
    var world: Vector2 = world_of(x_index, z_index)
    return surface_at_world(world.x, world.y)


## Which surface is at a world position, as an index into `GroundModels.ORDER`.
##
## The order mirrors the height composition: whatever cut the terrain last is what a tyre is
## on. A surface that disagreed with the shape would be gravel painted down the middle of a
## river.
static func surface_at_world(x: float, z: float) -> int:
    if road_distance(x, z) <= ValleyLayout.ROAD_HALF_WIDTH_M:
        return _road_index
    if _on_rock_shelf(x, z):
        return _rock_index
    if ValleyWaterCut.depth_at(x, z) > 0.05:
        return _river_index
    var on_floor: bool = absf(z) <= ValleyLayout.FLOOR_HALF_WIDTH_M
    if on_floor and x >= ValleyLayout.RUTS_WEST_M and x <= ValleyLayout.RUTS_EAST_M:
        return _ruts_index
    if on_floor:
        return _lane_indices[_lane_of(z)]
    if absf(z) <= ValleyLayout.WALL_END_M:
        return _wall_index
    return _ridge_index


## What colour the ground is drawn at a point: the surface's own tint, which is what the terrain's
## colour map carries. The park overrides this to draw a grid; the valley has nothing to add.
static func tint_at(x: float, z: float) -> Color:
    var surface: String = GroundModels.name_of(surface_at_world(x, z))
    return TerrainCfg.SURFACE_COLOURS.get(surface, Color.GRAY) as Color


## The valley before any feature cut into it: the profile, the grade and the ripple. This is the
## datum a carve is measured against — the floor's ripple moves it by more than the ford is deep,
## so a depth taken against the ground a few metres away is not a depth.
static func floor_y_at(x: float, z: float) -> float:
    return across_y(z) + along_y(x) + _ripple(x, z)


## The across-valley profile: flat floor, shoulder, wall, ridge. Metres above the floor.
static func across_y(z: float) -> float:
    var across: float = absf(z)
    if across <= ValleyLayout.FLOOR_HALF_WIDTH_M:
        return 0.0
    if across <= ValleyLayout.SHOULDER_END_M:
        var shoulder: float = (
            (across - ValleyLayout.FLOOR_HALF_WIDTH_M)
            / (ValleyLayout.SHOULDER_END_M - ValleyLayout.FLOOR_HALF_WIDTH_M)
        )
        # Squared, so the shoulder leaves the floor tangentially rather than at a kerb.
        return ValleyLayout.SHOULDER_RISE_M * shoulder * shoulder
    if across <= ValleyLayout.WALL_END_M:
        return _wall_y(across - ValleyLayout.SHOULDER_END_M)
    var ridge: float = _wall_y(ValleyLayout.WALL_END_M - ValleyLayout.SHOULDER_END_M)
    var wave: float = across / ValleyLayout.RIDGE_WAVELENGTH_M * TAU
    return ridge + ValleyLayout.RIDGE_UNDULATION_M * sin(wave)


## The along-valley profile: level across the test track, falling west and climbing east.
static func along_y(x: float) -> float:
    if x < ValleyLayout.TRACK_WEST_M:
        return (x - ValleyLayout.TRACK_WEST_M) * ValleyLayout.VALLEY_GRADE
    if x > ValleyLayout.TRACK_EAST_M:
        return (x - ValleyLayout.TRACK_EAST_M) * ValleyLayout.VALLEY_GRADE
    return 0.0


## How far a point is from the road's centre line, in metres across the ground plane.
##
## The road is a polyline and this is the distance to the nearest segment of it. Measured in
## the x/z plane and not in three dimensions: the road is a corridor on the map, and its height
## is whatever the wall's height is where the corridor runs.
static func road_distance(x: float, z: float) -> float:
    # Outside the road's own extent there is nothing to measure against, and skipping the
    # segment loop there is what keeps a 4.2 M texel map affordable to generate.
    if z < _road_z_min or z > _road_z_max:
        return INF
    var point: Vector2 = Vector2(x, z)
    var best: float = INF
    var points: Array[Vector2] = ValleyLayout.ROAD_POINTS
    for index: int in points.size() - 1:
        var from: Vector2 = points[index]
        var to: Vector2 = points[index + 1]
        # A cheap rejection first: a segment whose z range is far from this row cannot be the
        # nearest one, and most segments are far from most rows.
        var reach: float = ValleyLayout.ROAD_HALF_WIDTH_M + ValleyLayout.ROAD_BLEND_M
        if z > maxf(from.y, to.y) + reach or z < minf(from.y, to.y) - reach:
            continue
        best = minf(best, _distance_to_segment(point, from, to))
    return best


## The height of the road surface at a point, in metres.
##
## The road is a contour traverse: its height is the wall's own height at the nearest point of
## the centre line. So the bench cut into the wall is bounded by the corridor's half width
## times the wall grade — about 1.2 m — rather than by whatever a table of heights said, and
## the grade the road achieves is a property of the path. `road_is_drivable` measures it.
static func road_height_at(x: float, z: float) -> float:
    var point: Vector2 = Vector2(x, z)
    var best: float = INF
    var nearest: Vector2 = point
    var points: Array[Vector2] = ValleyLayout.ROAD_POINTS
    for index: int in points.size() - 1:
        var on_segment: Vector2 = _closest_on_segment(point, points[index], points[index + 1])
        var distance: float = point.distance_to(on_segment)
        if distance < best:
            best = distance
            nearest = on_segment
    return across_y(nearest.y) + along_y(nearest.x)


## The lake's water level, in metres. Flat, because water is.
static func lake_water_y() -> float:
    return ValleyLayout.LAKE_WATER_Y_M


## How deep the water is at a point of the lake, in metres; zero outside it.
static func lake_depth_at(x: float, z: float) -> float:
    var bed: float = height_at_world(x, z)
    return maxf(0.0, lake_water_y() - bed) if x <= ValleyLayout.LAKE_SHORE_X_M else 0.0


## --- The features ---------------------------------------------------------------------------


## The floor's undulation, faded out across the shoulder so that the walls, the ridge and the
## benched road are not rippled by it.
static func _ripple(x: float, z: float) -> float:
    var across: float = absf(z)
    if across >= ValleyLayout.SHOULDER_END_M:
        return 0.0
    var fade: float = 1.0
    if across > ValleyLayout.FLOOR_HALF_WIDTH_M:
        fade = 1.0 - (
            (across - ValleyLayout.FLOOR_HALF_WIDTH_M)
            / (ValleyLayout.SHOULDER_END_M - ValleyLayout.FLOOR_HALF_WIDTH_M)
        )
    var wave: float = x / ValleyLayout.RIPPLE_WAVELENGTH_M * TAU
    return ValleyLayout.RIPPLE_HEIGHT_M * sin(wave) * fade


## The washout: transverse corrugations across the floor, fading in and out at both ends so
## that neither is a step.
static func _ruts(x: float, z: float) -> float:
    if x < ValleyLayout.RUTS_WEST_M - ValleyLayout.RUTS_FADE_M:
        return 0.0
    if x > ValleyLayout.RUTS_EAST_M + ValleyLayout.RUTS_FADE_M:
        return 0.0
    if not _on_floor(z):
        return 0.0
    var fade: float = minf(
        ramp(x - ValleyLayout.RUTS_WEST_M + ValleyLayout.RUTS_FADE_M, ValleyLayout.RUTS_FADE_M),
        ramp(ValleyLayout.RUTS_EAST_M + ValleyLayout.RUTS_FADE_M - x, ValleyLayout.RUTS_FADE_M)
    )
    var wave: float = x / ValleyLayout.RUTS_WAVELENGTH_M * TAU
    return ValleyLayout.RUTS_AMPLITUDE_M * sin(wave) * fade


## The rock traverse: an off-camber shelf cut into the south wall. Returns the height with the
## shelf applied, blended into the wall at its edges.
static func _rock_shelf(x: float, z: float, y: float) -> float:
    var weight: float = _rock_weight(x, z)
    if weight <= 0.0:
        return y
    var inner: float = ValleyLayout.ROCK_INNER_Z_M
    var shelf: float = (
        across_y(inner)
        + along_y(x)
        + (absf(z) - inner) * ValleyLayout.ROCK_CROSSFALL
        + ValleyLayout.ROCK_BUMP_M * sin(x / ValleyLayout.ROCK_BUMP_WAVELENGTH_M * TAU)
        * cos(z / ValleyLayout.ROCK_BUMP_WAVELENGTH_M * TAU)
    )
    return lerpf(y, shelf, weight)


## How much of the rock shelf applies at a point: one inside it, zero outside, ramped between.
static func _rock_weight(x: float, z: float) -> float:
    if z <= 0.0:
        return 0.0
    if x < ValleyLayout.ROCK_WEST_M - FEATURE_BLEND_M:
        return 0.0
    if x > ValleyLayout.ROCK_EAST_M + FEATURE_BLEND_M:
        return 0.0
    if z < ValleyLayout.ROCK_INNER_Z_M - FEATURE_BLEND_M:
        return 0.0
    if z > ValleyLayout.ROCK_OUTER_Z_M + FEATURE_BLEND_M:
        return 0.0
    return minf(
        minf(
            ramp(x - ValleyLayout.ROCK_WEST_M + FEATURE_BLEND_M, FEATURE_BLEND_M),
            ramp(ValleyLayout.ROCK_EAST_M + FEATURE_BLEND_M - x, FEATURE_BLEND_M)
        ),
        minf(
            ramp(z - ValleyLayout.ROCK_INNER_Z_M + FEATURE_BLEND_M, FEATURE_BLEND_M),
            ramp(ValleyLayout.ROCK_OUTER_Z_M + FEATURE_BLEND_M - z, FEATURE_BLEND_M)
        )
    )


static func _on_rock_shelf(x: float, z: float) -> bool:
    return _rock_weight(x, z) >= 0.5


## The road's bench: flat across the corridor, blending into the wall outside it.
static func _road_bench(x: float, z: float, y: float) -> float:
    var distance: float = road_distance(x, z)
    if distance > ValleyLayout.ROAD_HALF_WIDTH_M + ValleyLayout.ROAD_BLEND_M:
        return y
    var road: float = road_height_at(x, z)
    if distance <= ValleyLayout.ROAD_HALF_WIDTH_M:
        return road
    var blend: float = (distance - ValleyLayout.ROAD_HALF_WIDTH_M) / ValleyLayout.ROAD_BLEND_M
    return lerpf(road, y, smoothstep(0.0, 1.0, blend))


## --- Small shared pieces --------------------------------------------------------------------


static func _on_floor(z: float) -> bool:
    return absf(z) <= ValleyLayout.FLOOR_HALF_WIDTH_M


## How far the road's corridor and blend reach across the valley, in z.
static func _road_z_extent(lowest: bool) -> float:
    var reach: float = ValleyLayout.ROAD_HALF_WIDTH_M + ValleyLayout.ROAD_BLEND_M
    var found: float = ValleyLayout.ROAD_POINTS[0].y
    for point: Vector2 in ValleyLayout.ROAD_POINTS:
        found = minf(found, point.y) if lowest else maxf(found, point.y)
    return found - reach if lowest else found + reach


## The surface index of each lane across the floor, in lane order.
static func _build_lane_indices() -> PackedByteArray:
    var out: PackedByteArray = PackedByteArray()
    for lane: String in TerrainCfg.LANE_SURFACES:
        out.append(GroundModels.index_of(lane))
    return out


## Which surface lane a point across the floor is on. Lane 4 is the centre line, which is where
## the rig spawns, so changing the lane order moves what it spawns on.
static func _lane_of(z: float) -> int:
    var width: float = 2.0 * ValleyLayout.FLOOR_HALF_WIDTH_M / float(LANE_COUNT)
    var lane: int = int(floor((z + ValleyLayout.FLOOR_HALF_WIDTH_M) / width))
    return clampi(lane, 0, LANE_COUNT - 1)


## The wall's height a given distance up from the shoulder, with a rounded toe so the wall
## leaves the shoulder at the shoulder's own slope instead of at a crease.
static func _wall_y(up: float) -> float:
    var toe: float = ValleyLayout.WALL_TOE_M
    if up <= toe:
        return ValleyLayout.SHOULDER_RISE_M + ValleyLayout.WALL_GRADE * up * up / (2.0 * toe)
    return (
        ValleyLayout.SHOULDER_RISE_M
        + ValleyLayout.WALL_GRADE * toe * 0.5
        + ValleyLayout.WALL_GRADE * (up - toe)
    )


## A 0-to-1 ramp over `width`, clamped at both ends and smooth at both. Shared with
## `ValleyWaterCut`, which shapes its banks and shores with the same ramp.
static func ramp(distance: float, width: float) -> float:
    return smoothstep(0.0, 1.0, clampf(distance / width, 0.0, 1.0))


static func _closest_on_segment(point: Vector2, from: Vector2, to: Vector2) -> Vector2:
    var span: Vector2 = to - from
    var length_squared: float = span.length_squared()
    if length_squared <= 0.0:
        return from
    var along: float = clampf((point - from).dot(span) / length_squared, 0.0, 1.0)
    return from + span * along


static func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
    return point.distance_to(_closest_on_segment(point, from, to))
