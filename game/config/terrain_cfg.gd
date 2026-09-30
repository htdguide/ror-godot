class_name TerrainCfg
extends RefCounted
## How a terrain is put into Terrain3D. Tunables only — a terrain's shape is its author's files,
## the reading is `world/ror_terrain.gd` and `compat/`, and the building is `world/`.
##
## What used to be here as well was a surface palette, a map size, a vertex spacing and a lane
## layout, for the two worlds this project generated for itself. Those are gone: a terrain brings
## its own extent, its own lattice and its own textures, so the only numbers left are Terrain3D's
## own.

## One Terrain3D region, in vertices. Regions tile on a grid of this size and an import is
## snapped to it, so a map that is not a whole number of regions across, placed at an origin
## that is not on the grid, lands somewhere other than where it was asked for: importing a
## 256-wide map at -128 put it in the region spanning -256 to 0, leaving everything from the
## world origin outward with no height at all.
const REGION_SIZE: int = 512

## Collision is Terrain3D's mode 0. Rigs of Rods' own collision stays authoritative and Godot
## physics never touches the terrain: the solver is handed the heights and resolves contact
## itself, which is the whole premise of the integration.
const COLLISION_DISABLED: int = 0
