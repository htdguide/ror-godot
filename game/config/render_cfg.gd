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
## Raised so a sunlit light-coloured panel rolls off instead of clipping. At 6.0 the
## truck's own paint blew out to featureless white whenever the sun was behind the
## camera, which reads as the surface being transparent rather than over-exposed.
const WHITE: float = 12.0

## Auto-exposure is never used: its convergence is temporal, so a capture would depend on
## how many frames preceded it. Each camera preset carries a fixed exposure instead.
const AUTO_EXPOSURE: bool = false

## Scene-referred exposure applied before the tonemapper. The physical sky and a sun of
## unit energy together put the scene well above the range AgX maps to display white, and
## without this the sky washes out to grey and the ground blows out entirely.
const EXPOSURE: float = 0.7

## The sun's own angular size, in degrees, and what it does to a shadow's edge. The real sun is
## 0.53 degrees across and gives an edge that is sharp at the contact and soft a few metres away.
## Wider than life here, because this is a test park before it is a photograph and a hard edge on
## a box makes the box harder to judge.
const SUN_ANGULAR_DEG: float = 1.8
## How dark a shadow is allowed to be, as Godot's shadow opacity. Not one: a shadow with nothing
## in it is a hole, and everything a session is looking at — a ramp's face, a rock's shape, the
## suspension's geometry — lives on the side of the object the sun is not on.
const SHADOW_OPACITY: float = 0.72
## A second directional light, from the opposite side and casting nothing, so the shaded side of
## an object is lit by something with a direction rather than by flat ambient alone. This is the
## fill of a three-point rig, and it is what stops one side of the valley reading as black.
const FILL_ENERGY: float = 0.35
const FILL_COLOUR: Color = Color(0.72, 0.80, 0.95)

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

## --- Clouds -----------------------------------------------------------------------------------
##
## The gradient sky above is a dependable thing to measure lighting against and is not a sky
## anybody believes. Clouds are marched in `shaders/sky_clouds.gdshader`; these are what a
## session sees by default, and the panel moves them while it runs.
const CLOUDS_ENABLED: bool = true
## How much of the sky is cloud, and how solid each one is.
const CLOUD_COVERAGE: float = 0.50
const CLOUD_DENSITY: float = 1.1
## The slab they live in, in metres, and how big one is across.
const CLOUD_BOTTOM_M: float = 900.0
const CLOUD_TOP_M: float = 2300.0
const CLOUD_SCALE_M: float = 1600.0
const CLOUD_WIND: Vector2 = Vector2(1.0, 0.35)
## How fast the weather moves. Zero by default, because a gate captures two frames and compares
## them and a sky that moves between them is a sky that fails `capture_stability`. The play
## window turns it on — `CLOUD_WIND_SPEED_PLAYING` — because a still sky is a photograph.
const CLOUD_WIND_SPEED: float = 0.0
const CLOUD_WIND_SPEED_PLAYING: float = 0.006
## How much finer the erosion field is than the cloud shape, and how deeply it bites into it.
const CLOUD_DETAIL_SCALE: float = 5.0
const CLOUD_EROSION: float = 0.25
const CLOUD_LIT: Color = Color(1.0, 0.99, 0.96)
const CLOUD_SHADED: Color = Color(0.42, 0.46, 0.55)
## Steps through the slab for the visible pass, for the radiance pass that lights the scene, and
## toward the sun. The radiance pass is convolved into an irradiance map, so its detail is not
## seen and its cost is not worth paying.
const CLOUD_STEPS: int = 28
const CLOUD_RADIANCE_STEPS: int = 10
const CLOUD_LIGHT_STEPS: int = 4

## --- Distance ---------------------------------------------------------------------------------
##
## How far a session can see, and the haze that closes it. Distance fog rather than volumetric:
## the volumetric kind is a froxel grid with its own range and cost, and what a driver on a 4 km
## map wants is depth cueing to the horizon.
const FOG_ENABLED: bool = true
## Measured against the valley: at 0.0014 the far wall of a 2 km valley is gone, and a gate that
## counts how much of a frame is not sky called it sky. This still closes a 4 km horizon.
const FOG_DENSITY: float = 0.0006
const FOG_SKY_AFFECT: float = 0.35
const FOG_COLOUR: Color = Color(0.68, 0.72, 0.78)
## How far the camera draws. A Rigs of Rods terrain is 4 km across and its own horizon mesh
## stands at its edge, so the default far plane has to reach it.
const VIEW_DISTANCE_M: float = 6000.0
