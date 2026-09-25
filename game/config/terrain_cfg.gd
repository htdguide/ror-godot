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
