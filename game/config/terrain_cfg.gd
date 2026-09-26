class_name TerrainCfg
extends RefCounted
## The terrain's shape and resolution. Tunables only — the building is in world/, the
## height query in compat/.
##
## The heightmap is generated from these numbers rather than authored, which is what the
## CLI-only rule requires: there is no editor session in this project's loop, so a terrain
## has to be a reproducible artifact of code. Real elevation data replaces the generator
## later; the seam it plugs into is the same either way.

## One Terrain3D region, in vertices. Regions tile on a grid of this size and an import is
## snapped to it, so a map that is not a whole number of regions across, placed at an origin
## that is not on the grid, lands somewhere other than where it was asked for: importing a
## 256-wide map at -128 put it in the region spanning -256 to 0, leaving everything from the
## world origin outward with no height at all.
const REGION_SIZE: int = 256
const VERTEX_SPACING: float = 1.0
## The whole map, in vertices: two regions square, so the valley surrounds the world origin
## the rig spawns at rather than starting at a corner of it.
const MAP_SIZE: int = 512
## Region-aligned, and half the map either side of the origin.
const ORIGIN: Vector3 = Vector3(-256.0, 0.0, -256.0)

## Height of the valley walls above the floor, in metres.
const WALL_HEIGHT_M: float = 18.0
## How much of the region's width is flat floor before the walls start, as a fraction.
const FLOOR_WIDTH: float = 0.35
## Gentle undulation along the valley, so the floor is drivable but not a table.
const RIPPLE_HEIGHT_M: float = 1.2
const RIPPLE_WAVELENGTH_M: float = 90.0

## The valley floor is laid out as lanes, one surface each, running the length of the valley.
## Driving along a lane stays on one surface; driving across them crosses every surface in
## turn, which is the case that matters — a rig with two wheels on asphalt and two on sand.
##
## The floor is 2 * FLOOR_WIDTH of the map wide, which at 512 m is 179 m, so nine lanes come
## out at about 20 m each: wide enough to put a whole truck on one and still have room to turn.
const LANE_SURFACES: Array[String] = [
    "asphalt", "concrete", "gravel", "rock", "sand", "grass", "snow", "ice", "metal",
]
## What the walls either side of the floor are made of.
const WALL_SURFACE: String = "rock"

## Roughly what each surface looks like, for the terrain's colour map. Not a material — the
## PBR ground work is M2 — but enough that a driver can see which lane they are on, which
## matters more for a test track than for scenery.
const SURFACE_COLOURS: Dictionary = {
    "asphalt": Color(0.20, 0.20, 0.22),
    "concrete": Color(0.58, 0.57, 0.54),
    "gravel": Color(0.45, 0.42, 0.38),
    "rock": Color(0.38, 0.35, 0.32),
    "sand": Color(0.76, 0.68, 0.47),
    "grass": Color(0.30, 0.42, 0.20),
    "snow": Color(0.92, 0.93, 0.95),
    "ice": Color(0.70, 0.82, 0.88),
    "metal": Color(0.50, 0.52, 0.56),
}


## Which surface is at a point on the terrain grid, as an index into GroundModels.ORDER.
static func surface_at(_x: int, z: int) -> int:
    var across: float = absf(float(z) / float(MAP_SIZE) - 0.5) * 2.0
    if across > FLOOR_WIDTH:
        return GroundModels.index_of(WALL_SURFACE)
    # Position across the floor, 0 at one edge and 1 at the other. `across` is the *doubled*
    # distance from the centre line, so the floor spans half of FLOOR_WIDTH either side of it
    # and the divisor here is FLOOR_WIDTH, not half of it. Halving it too mapped the floor
    # onto the middle of the lane range and four of the nine surfaces were never laid at all.
    var along_floor: float = (float(z) / float(MAP_SIZE) - 0.5) / FLOOR_WIDTH + 0.5
    var lane: int = clampi(
        int(along_floor * float(LANE_SURFACES.size())), 0, LANE_SURFACES.size() - 1
    )
    return GroundModels.index_of(LANE_SURFACES[lane])


## Collision is Terrain3D's mode 0. Rigs of Rods' own collision stays authoritative and Godot
## physics never touches the terrain: the solver is handed the heights and resolves contact
## itself, which is the whole premise of the integration.
const COLLISION_DISABLED: int = 0


## The valley's height at a point on the terrain grid, in metres above the origin.
##
## A flat floor in the middle, walls rising as a smooth curve either side of it, and a long
## ripple along its length. Deterministic and seedless: the same grid coordinates always give
## the same terrain, on any machine.
static func height_at(x: int, z: int) -> float:
    var across: float = absf(float(z) / float(MAP_SIZE) - 0.5) * 2.0
    var wall: float = 0.0
    if across > FLOOR_WIDTH:
        var climb: float = (across - FLOOR_WIDTH) / maxf(1.0 - FLOOR_WIDTH, 0.001)
        # Squared, so the wall leaves the floor tangentially instead of at a crease the
        # suspension would read as a kerb.
        wall = WALL_HEIGHT_M * climb * climb
    var along: float = float(x) * VERTEX_SPACING / RIPPLE_WAVELENGTH_M
    return wall + RIPPLE_HEIGHT_M * sin(along * TAU)
