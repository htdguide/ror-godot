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

## A trim on the tonemapper, and it is 1.0 because it has nothing left to do.
##
## It used to be the exposure: 0.7, then 1.05, then 3.4 as the sky changed under it, each value
## compensating for a scene whose lights were in arbitrary units. With physical light units the
## exposure is the camera's — aperture, shutter, ISO — and this stays at unity unless something
## genuinely wants a grade on top. A number here that is not 1.0 means the camera is wrong.
const EXPOSURE: float = 1.0

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
const FILL_ENERGY: float = 1.0
const FILL_COLOUR: Color = Color(0.72, 0.80, 0.95)

## Sky-based image lighting. The radiance map is what gives metal something to reflect and
## shadowed surfaces something other than flat ambient.
const SKY_RADIANCE_SIZE: int = Sky.RADIANCE_SIZE_256
## Where a captured sky stops being sky and starts being the sun in it, in the panorama's own
## units. Measured over the four maps this project ships: the clear afternoon's solar disc is 80
## pixels of two million and 91% of all the light in the map, the night map's moon 47 pixels and
## 86%, and no part of the sky itself reaches 6. Anything above this is a disc, and a disc is the
## `DirectionalLight3D`'s job because a disc in a radiance map casts no shadow.
const SKY_SUN_CLAMP: float = 50.0
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
## Real-world illuminance, now that lights are in physical units.
##
## A surface facing a clear midday sun receives about 100 klx; the same scene at golden dusk is
## a tenth of that and redder. These are measurements of daylight, not dials: the sun-to-sky
## balance that `daylight_shadows_are_readable` checks should now fall out of the atmosphere
## model rather than being set by hand, because `PhysicalSkyMaterial` scatters a sun whose
## intensity is finally in the same units the sky is calibrated against.
const SUN_LUX_NOON: float = 100000.0
const SUN_LUX_DUSK: float = 12000.0
## The fill light, which is not physical. Daylight has no second sun; this exists because
## `shadows_are_not_black` found one side of everything reading as black.
##
## It did **not** shrink when the sun and sky became real, which was the hope. Measured at ISO 25,
## raising it from 6 000 to 20 000 lux moved the shadow from 0.0479 to 0.0578 against a floor of
## 0.085 — it cannot reach the floor at any value, because the fill casts its own shadow and so
## barely lights the region the gate measures. What actually meets the floor is exposure, which
## is why `CAMERA_ISO` ended up being set by a shadow gate rather than by the sun.
const FILL_LUX: float = 12000.0

## How sensitive the camera is, in ISO. With physical light units the exposure comes from the
## aperture, the shutter and this — the three numbers a photographer would set — rather than from
## a multiplier on the tonemapper.
## 32, and it is lower than a photographer would expect for daylight because `EXPOSURE` is no
## longer doing half the job: with physical light units the aperture, the shutter and this are
## the whole of the exposure. f/8 at 1/125 and ISO 32 is about EV 14.6, roughly half a stop under
## the sunny-16 rule, which is what a bright desert wants.
##
## It is also the tightest of three constraints rather than a free choice, and the constraints do
## not all point the same way. `shadows_are_not_black` wants the shadow at or above 0.085
## displayed; above ISO 40 La Paz's pale ground bleaches; and `daylight_shadows_are_readable`
## wants the shaded surface above 0.05. 32 satisfies all three with the shadow at 0.0950 and 3.5x
## displayed contrast against a 4x ceiling — tight, and the tightness is the finding below.
const CAMERA_ISO: float = 45.0

const SKY_ENERGY: float = 1.0

## The atmosphere, for `PhysicalSkyMaterial`. Rayleigh scattering is what makes a clear sky blue
## and the horizon pale; Mie is the forward-scattering haze around the sun. These are Godot's own
## defaults except where noted, because they are a fit to real daylight and this project has no
## better measurement of the sky than the model does.
##
## Why a physical sky rather than the two-colour gradient this project used: the gradient's
## irradiance is whatever its colours happen to integrate to, so the balance between sun and sky
## was a pair of numbers somebody chose. `daylight_shadows_are_readable` measured the consequence
## — the scene ran at about 3:1 sun-to-sky where clear daylight is nearer 14:1, so its shadows
## were filled by roughly three times too much skylight. An atmosphere model produces that ratio
## instead of being told it.
const RAYLEIGH_COEFFICIENT: float = 2.0
const RAYLEIGH_COLOR: Color = Color(0.26, 0.41, 0.58)
const MIE_COEFFICIENT: float = 0.005
const MIE_ECCENTRICITY: float = 0.8
const MIE_COLOR: Color = Color(0.63, 0.77, 0.92)
## Clear air. Turbidity is the haze dial: 2 is a clean day, 10 is industrial murk, and it moves
## the sun-to-sky ratio directly because haze is what fills a shadow.
const TURBIDITY: float = 2.0
const SUN_DISK_SCALE: float = 1.0
## What the sky sees below the horizon. Not black: a sky dome whose lower half is black halves
## the ambient a surface receives, and the ground does reflect.
const SKY_GROUND_COLOR: Color = Color(0.1, 0.07, 0.034)

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

## --- Occlusion ------------------------------------------------------------------------------
##
## **Ambient light arrives from every direction and geometry does not.** The ambient term and the
## sky's radiance reach a surface regardless of what is standing in front of it, so the floor of a
## truck bed, the inside of a wheel arch and the top of an axle are lit exactly as brightly as the
## roof above them. Measured at a quarter past six in the evening: the bed floor read 0.0633 and
## the open roof 0.0680 — an enclosed surface at 93% of one facing the sky. Reported from a window
## as the moon's light coming through the truck and landing in its bed.
##
## Screen-space ambient occlusion is the answer to that, and it is the thing a session means by
## "ambient occlusion": for each pixel, how much of the sky it can actually see, applied to the
## light that comes from everywhere.
const SSAO_ENABLED: bool = true
## How far out a surface looks for something blocking its sky, in metres, and how hard the
## darkening is. A metre reaches across a wheel arch and under a bumper without reaching across
## a street.
const SSAO_RADIUS_M: float = 1.0
const SSAO_INTENSITY: float = 2.4
const SSAO_POWER: float = 1.6
const SSAO_DETAIL: float = 0.6
const SSAO_HORIZON: float = 0.06
const SSAO_SHARPNESS: float = 0.98
## How much of it also lands on direct light. Direct light has shadow maps of its own, so this is
## small: an occlusion term applied twice to the same sunbeam is a dark smear under every object.
const SSAO_LIGHT_AFFECT: float = 0.15
## And how much of it lands on the sky's reflection, which is the other half of a bed floor
## lighting itself: a surface that cannot see the sky cannot reflect it either.
const SSAO_REFLECTION_AFFECT: float = 1.0

## --- Air that catches light --------------------------------------------------------------------
##
## The froxel grid, used only by the hours that ask for it. A headlight is a shaft as well as a
## pool, and the shaft is the air in front of the lamp scattering the beam back; with no
## participating medium a beam at night is a bright patch of road under an invisible lamp.
## Thin enough that it reads as clear night air rather than as fog.
const VOLUMETRIC_DENSITY: float = 0.010
## How far out the grid reaches. Past this a beam stops being a shaft, which is well beyond
## where a headlight has anything left to scatter.
const VOLUMETRIC_LENGTH_M: float = 96.0
