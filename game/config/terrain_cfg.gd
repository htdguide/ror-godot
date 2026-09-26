class_name TerrainCfg
extends RefCounted
## The terrain's resolution and its surface palette. Tunables only — the valley's shape is
## `world/valley_one_layout.gd` and `world/valley_shape.gd`, the building is `world/`, and the
## height query is `compat/`.
##
## The heightmap is generated rather than authored, which is what the CLI-only rule requires:
## there is no editor session in this project's loop, so a terrain has to be a reproducible
## artifact of code. Real elevation data replaces the generator later; the seam it plugs into
## is the same either way.

## One Terrain3D region, in vertices. Regions tile on a grid of this size and an import is
## snapped to it, so a map that is not a whole number of regions across, placed at an origin
## that is not on the grid, lands somewhere other than where it was asked for: importing a
## 256-wide map at -128 put it in the region spanning -256 to 0, leaving everything from the
## world origin outward with no height at all.
const REGION_SIZE: int = 512
const VERTEX_SPACING: float = 1.0
## The whole map, in vertices, and so 2.0 km across at a metre per vertex: the size PLAN §0.5
## asks Valley One to be. Four regions square, with the origin on a region boundary.
##
## Generating it costs about 3.9 s — 0.6 s of height and colour, 1.6 s of surface painting and
## 1.6 s for the collision bridge to copy it back out, measured by `tools/terrain_cost_probe.gd`
## at several sizes before the map was grown. A metre per vertex is kept rather than traded for
## extent: a rut and a bench cut are metre-scale features and a 2 m lattice cannot hold them.
const MAP_SIZE: int = 2048
## Region-aligned, and half the map either side of the origin, so the valley surrounds the
## spawn point rather than starting at a corner of it.
const ORIGIN: Vector3 = Vector3(-1024.0, 0.0, -1024.0)

## The valley floor is laid out as lanes, one surface each, running the length of the valley.
## Driving along a lane stays on one surface; driving across them crosses every surface in
## turn, which is the case that matters — a rig with two wheels on asphalt and two on sand.
##
## The floor is 180 m wide, so nine lanes come out at 20 m each: wide enough to put a whole
## truck on one and still have room to turn.
const LANE_SURFACES: Array[String] = [
    "asphalt", "concrete", "gravel", "rock", "sand", "grass", "snow", "ice", "metal",
]

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

## Collision is Terrain3D's mode 0. Rigs of Rods' own collision stays authoritative and Godot
## physics never touches the terrain: the solver is handed the heights and resolves contact
## itself, which is the whole premise of the integration.
const COLLISION_DISABLED: int = 0
