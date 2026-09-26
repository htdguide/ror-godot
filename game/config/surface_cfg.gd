class_name SurfaceCfg
extends RefCounted
## What each driving surface looks like.
##
## These exist to give the ground high-frequency detail, which is what a driver reads speed
## from: a flat-tinted plane slides past the eye with nothing to track, and the vehicle feels
## stationary however fast it is going. Optical flow needs texture, not photographs.
##
## The textures are generated rather than sourced, which keeps the CLI-only rule and needs no
## third-party assets. They are placeholders in the sense that M2's material work will replace
## them, and not placeholders in the sense that they are chosen per surface: gravel is coarse
## and high-contrast, asphalt is fine and flat, ice is nearly smooth. Grain size is the part a
## driver actually perceives.

## One noise texture per surface, at this resolution. Big enough not to read as a pattern from
## a cab, small enough that nine of them generate in well under a second.
const TEXTURE_SIZE: int = 256

## Per surface: [noise frequency, contrast, uv scale in metres, roughness].
##
## Frequency sets the grain of the noise image; uv scale sets how many metres it covers on the
## ground. Both matter and they are not the same knob — a coarse grain tiled small reads as
## fizz, a fine grain tiled large reads as mud.
const DETAIL: Dictionary = {
    "concrete": [0.05, 0.25, 4.0, 0.85],
    "asphalt": [0.09, 0.30, 3.0, 0.75],
    "gravel": [0.18, 0.85, 1.5, 0.95],
    "rock": [0.04, 0.70, 8.0, 0.90],
    "ice": [0.02, 0.15, 10.0, 0.20],
    "snow": [0.06, 0.20, 5.0, 0.55],
    "metal": [0.03, 0.20, 6.0, 0.35],
    "grass": [0.22, 0.55, 2.0, 0.90],
    "sand": [0.14, 0.35, 2.5, 0.80],
}
## How much each surface's texture is rotated and shifted per tile, to break up the
## repetition. A texture that repeats every few metres reads as a fixed pattern at speed
## rather than as ground going past, which defeats the point of having texture at all.
const DETILE_ROTATION: float = 0.4
const DETILE_SHIFT: float = 0.3
## How deep the generated normal maps read. Enough to catch the sun at a low angle without the
## ground looking like corrugated iron.
const NORMAL_DEPTH: float = 0.6
## Noise below this in the height channel is flattened, so a surface has areas of plain ground
## rather than being uniformly busy.
const DETAIL_FLOOR: float = 0.15
## What the noise averages to, before the surface's colour is multiplied over it.
##
## Near white, not mid grey. Terrain3D multiplies a texture by its albedo colour, so noise
## centred on 0.5 halves every surface: the lanes rendered at 0.006 to 0.324 luminance instead
## of 0.249 to 0.672, and a ground that should read as sand came out nearly black. The noise
## is a variation around the surface's own colour, so it belongs near the top of the range
## with the variation hanging below it.
const DETAIL_BASE: float = 0.88
