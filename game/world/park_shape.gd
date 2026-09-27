class_name ParkShape
extends RefCounted
## The test park's ground: flat, except where a segment is deliberately not.
##
## The same shape interface `ValleyShape` has — `height_at`, `surface_at`, both pure functions of a
## grid cell — so the terrain builder, the collision bridge and the gates take either without
## knowing which they have. That is the whole reason the interface is two static functions and not
## a node.
##
## What is here is what a heightfield can hold: a washboard, a pair of ruts, two dips and a hump.
## Everything with a face — ramps, walls, kerbs, rocks — is a box in `world/park_props.gd`, because
## ground that is a function of x and z cannot have a wall in it.


## The park's height at a terrain grid cell, in metres.
static func height_at(x_index: int, z_index: int) -> float:
    var world: Vector2 = ValleyShape.world_of(x_index, z_index)
    return height_at_world(world.x, world.y)


## The park's height at a world position, in metres. Flat ground is zero.
static func height_at_world(x: float, z: float) -> float:
    var y: float = 0.0
    y += _washboard(x, z)
    y += _ruts(x, z)
    y += _dips_and_hump(x, z)
    return y


## Which surface is at a grid cell, as an index into `GroundModels.ORDER`.
static func surface_at(x_index: int, z_index: int) -> int:
    var world: Vector2 = ValleyShape.world_of(x_index, z_index)
    return surface_at_world(world.x, world.y)


## Which surface is at a world position.
##
## The road first, then what is let into it, then the skid pad, then the ground everything else
## stands on. A patch is only a patch where there is road to let it into.
static func surface_at_world(x: float, z: float) -> int:
    if Vector2(x, z).distance_to(ParkCfg.SKID_PAD_CENTRE) <= ParkCfg.SKID_PAD_RADIUS_M:
        return GroundModels.index_of(ParkCfg.SKID_PAD_SURFACE)
    if _on_road(x, z):
        var patch: String = _patch_surface(x)
        if patch != "":
            return GroundModels.index_of(patch)
        if x >= ParkCfg.RUTS_WEST_M and x <= ParkCfg.RUTS_EAST_M:
            return GroundModels.index_of("gravel")
        return GroundModels.index_of(ParkCfg.ROAD_SURFACE)
    return GroundModels.index_of(ParkCfg.GROUND_SURFACE)


## What colour the ground is drawn at a point.
##
## The test areas — the road, the patches let into it, the skid pad — are drawn as what they are.
## Everything else is the dev grid's floor: one flat workshop grey.
##
## The grid's *lines* are deliberately not here. This function is what the terrain's colour map is
## baked from, and a colour map is one texel per metre and filtered, so a 0.45 m line stored in it
## arrives as a smear — which is what a session reported as the grid being too blurry. The lines
## are drawn per pixel by `world/park_grid.gd` on an overlay above this floor.
static func tint_at(x: float, z: float) -> Color:
    if is_test_area(x, z):
        var surface: String = GroundModels.name_of(surface_at_world(x, z))
        return TerrainCfg.SURFACE_COLOURS.get(surface, Color.GRAY) as Color
    return ParkCfg.GRID_BASE


## Whether a point is part of something being tested, and so drawn as itself rather than as grid.
##
## The single answer to that question: the colour map is baked from it and the grid overlay's mask
## is baked from it, so the floor and the lines cannot disagree about where the road is.
static func is_test_area(x: float, z: float) -> bool:
    if _on_road(x, z):
        return true
    return Vector2(x, z).distance_to(ParkCfg.SKID_PAD_CENTRE) <= ParkCfg.SKID_PAD_RADIUS_M


## Whether a point is on the main straight.
static func _on_road(x: float, z: float) -> bool:
    if x < ParkCfg.ROAD_WEST_M or x > ParkCfg.ROAD_EAST_M:
        return false
    return absf(z) <= ParkCfg.ROAD_HALF_WIDTH_M


## Which surface is let into the road at a point along it, or "" for the road itself.
static func _patch_surface(x: float) -> String:
    var pitch: float = ParkCfg.PATCH_LENGTH_M + ParkCfg.PATCH_GAP_M
    var along: float = x - ParkCfg.PATCH_FIRST_X_M
    if along < 0.0:
        return ""
    var index: int = int(along / pitch)
    if index >= ParkCfg.PATCH_SURFACES.size():
        return ""
    if along - float(index) * pitch > ParkCfg.PATCH_LENGTH_M:
        return ""
    return ParkCfg.PATCH_SURFACES[index]


## --- The shaped ground ---------------------------------------------------------------------


## Corrugations across the road: the section that shakes a vehicle rather than tilting it.
static func _washboard(x: float, z: float) -> float:
    if x < ParkCfg.WASHBOARD_WEST_M or x > ParkCfg.WASHBOARD_EAST_M:
        return 0.0
    var fade: float = minf(
        ValleyShape.ramp(x - ParkCfg.WASHBOARD_WEST_M, ParkCfg.FEATURE_FADE_M),
        ValleyShape.ramp(ParkCfg.WASHBOARD_EAST_M - x, ParkCfg.FEATURE_FADE_M)
    ) * _road_fade(z)
    if fade <= 0.0:
        return 0.0
    return ParkCfg.WASHBOARD_AMPLITUDE_M * sin(x / ParkCfg.WASHBOARD_WAVELENGTH_M * TAU) * fade


## Two ruts a wheel track apart, for one side of the rig to drop into.
static func _ruts(x: float, z: float) -> float:
    if x < ParkCfg.RUTS_WEST_M or x > ParkCfg.RUTS_EAST_M:
        return 0.0
    var fade: float = minf(
        ValleyShape.ramp(x - ParkCfg.RUTS_WEST_M, ParkCfg.FEATURE_FADE_M),
        ValleyShape.ramp(ParkCfg.RUTS_EAST_M - x, ParkCfg.FEATURE_FADE_M)
    )
    if fade <= 0.0:
        return 0.0
    var across: float = absf(absf(z) - ParkCfg.RUT_TRACK_M * 0.5) / ParkCfg.RUT_HALF_WIDTH_M
    if across >= 1.0:
        return 0.0
    # Parabolic, so a wheel rides into it rather than falling off a step.
    return -ParkCfg.RUT_DEPTH_M * (1.0 - across * across) * fade


## Bowls to drop a wheel into, and a hump to lift one over.
static func _dips_and_hump(x: float, z: float) -> float:
    var y: float = 0.0
    for centre: float in ParkCfg.DIP_CENTRES_X:
        var distance: float = Vector2(x - centre, z).length() / ParkCfg.DIP_RADIUS_M
        if distance < 1.0:
            y -= ParkCfg.DIP_DEPTH_M * (1.0 - distance * distance)
    var hump: float = Vector2(x - ParkCfg.HUMP_X_M, z).length() / ParkCfg.HUMP_RADIUS_M
    if hump < 1.0:
        y += ParkCfg.HUMP_HEIGHT_M * (1.0 - hump * hump)
    return y


## How much of a road-width feature applies across the road, fading out at its edges.
static func _road_fade(z: float) -> float:
    var across: float = absf(z)
    if across > ParkCfg.ROAD_HALF_WIDTH_M:
        return 0.0
    return 1.0
