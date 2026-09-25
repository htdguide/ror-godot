class_name RenderCfg
extends RefCounted
## Renderer settings. Data only.
##
## Tonemapping: AgX, not ACES or Filmic. ACES over-saturates and hue-shifts bright
## vehicle paint and headlight cores; Filmic crushes the shadow ramp that makes suspension
## geometry readable. AgX holds highlight hue and gives a neutral base to grade from. The
## alternatives stay reachable here so comparison shots are one config change away.

const TONEMAP_AGX: int = Environment.TONE_MAPPER_AGX
const TONEMAP_ACES: int = Environment.TONE_MAPPER_ACES
const TONEMAP_FILMIC: int = Environment.TONE_MAPPER_FILMIC

const TONEMAP: int = TONEMAP_AGX
## White point in scene-referred units. Raising it darkens the image and holds more
## highlight detail before the curve rolls off.
const WHITE: float = 6.0

## Auto-exposure is never used: its convergence is temporal, so a capture would depend on
## how many frames preceded it. Each camera preset carries a fixed exposure instead.
const AUTO_EXPOSURE: bool = false

## Scene-referred exposure applied before the tonemapper. The physical sky and a sun of
## unit energy together put the scene well above the range AgX maps to display white, and
## without this the sky washes out to grey and the ground blows out entirely.
const EXPOSURE: float = 1.0

## Sky-based image lighting. The radiance map is what gives metal something to reflect and
## shadowed surfaces something other than flat ambient.
const SKY_RADIANCE_SIZE: int = Sky.RADIANCE_SIZE_256
const AMBIENT_FROM_SKY: float = 1.0
const REFLECTION_FROM_SKY: float = 1.0

## Sky colours, stated rather than simulated.
##
## PhysicalSkyMaterial was tried first and rendered colourless here: sampled under linear
## tonemapping it came out (104, 110, 111), and setting its scattering coefficients and
## colours explicitly did not change the hue. Rather than keep hunting, the sky is built
## from stated colours, which is predictable, controllable per weather preset, and still
## supplies image-based lighting. A grey sky lights every surface in the scene grey, so
## this is not a cosmetic detail.
const SKY_TOP: Color = Color(0.16, 0.33, 0.66)
const SKY_HORIZON: Color = Color(0.62, 0.72, 0.84)
const SKY_CURVE: float = 0.12
const GROUND_HORIZON: Color = Color(0.45, 0.42, 0.38)
const SUN_ANGLE_MAX_DEG: float = 12.0
const SUN_CURVE: float = 0.08

const GROUND_COLOR: Color = Color(0.15, 0.14, 0.13)
const SKY_ENERGY: float = 1.0
