class_name WaterCfg
extends RefCounted
## What the water looks like. Tunables only — the meshes are built in `world/valley_water.gd`
## and the shading is `res://shaders/water.gdshader`.
##
## This is the staged water PLAN §0.5 asks for: a depth-faded, refracting surface with scrolling
## ripples, built now rather than waiting for the FFT solver at M8. The surface generation is
## what M8 replaces; the material, the depth fade and the water-height query stay.

## The colour of water a few centimetres deep, and of water at FADE_DEPTH_M or more. Two colours
## and a depth is what makes a shoreline read as a shoreline: uniformly tinted water looks like
## coloured glass laid over the ground.
const SHALLOW_COLOUR: Color = Color(0.30, 0.48, 0.46)
const DEEP_COLOUR: Color = Color(0.04, 0.12, 0.17)
## How deep water has to be to reach DEEP_COLOUR.
const FADE_DEPTH_M: float = 2.5
## Over how much depth the surface fades in from transparent at the water's edge. A hard edge is
## the classic placeholder-water tell: real water thins to nothing up a beach.
const EDGE_DEPTH_M: float = 0.35

## Ripples. The normal map is generated rather than sourced, like the ground textures, so the
## scene needs no third-party asset.
const RIPPLE_PIXELS: int = 256
const RIPPLE_FREQUENCY: float = 0.06
## How many metres of world space one tile of the ripple map covers. Two tiles are sampled at
## different scales and drift in different directions, because one scrolling tile reads as a
## sheet of plastic sliding over the surface.
const RIPPLE_SCALE_M: float = 6.0
const RIPPLE_SCALE_FINE_M: float = 1.7
## Metres per second, in world x/z. Slow: water that scrolls at a walking pace looks like a
## conveyor belt.
const RIPPLE_DRIFT: Vector2 = Vector2(0.09, 0.05)
const RIPPLE_DRIFT_FINE: Vector2 = Vector2(-0.05, 0.11)
const RIPPLE_STRENGTH: float = 0.35

## How far the refracted view of the bed is displaced, in screen space at one metre of depth.
const REFRACTION: float = 0.035
## Water is smooth, so the sun is a highlight rather than a sheen; the ripples roughen it.
const ROUGHNESS: float = 0.06
## Not metal, but reflective at a glancing angle, which is what a fresnel term gives.
const SPECULAR: float = 0.5

## Mesh resolution. The depth under each vertex is baked into the mesh, so this is also how
## finely the shoreline fade follows the bed.
const LAKE_CELL_M: float = 4.0
const RIVER_CELL_M: float = 2.0
## How far past the shoreline the lake's mesh extends, so the ripple's wobble cannot reveal an
## edge. Beyond the shore the surface is under the ground and is never drawn.
const LAKE_MARGIN_M: float = 60.0
