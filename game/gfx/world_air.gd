class_name WorldAir
extends RefCounted
## What stands between a surface and the light: the haze across the distance, the air that catches
## a headlight, and how much of the sky a surface can actually see.
##
## Split out of `BlockoutWorld` when ambient occlusion took that file over its source cap. It is a
## seam worth having on its own: these three decide what an hour looks like beyond where its
## lights are, and none of them touches the sun, the sky or the camera.


## Everything about the air an hour of the day decides.
static func grade(env: Environment, weather: Dictionary) -> void:
    _occlusion(env, weather)
    _haze(env, weather)


## How much of the sky a surface can actually see.
##
## **Ambient light arrives from every direction and geometry does not.** Without this the floor of
## a truck bed is lit as brightly as the roof over it — measured at 0.0633 against 0.0680, which
## is what a session saw as the moon shining through the vehicle. The term is applied to the
## ambient light and to the sky's reflection, and only lightly to direct light, which has shadow
## maps of its own.
static func _occlusion(env: Environment, weather: Dictionary) -> void:
    env.ssao_enabled = bool(weather.get("occlusion", RenderCfg.SSAO_ENABLED))
    env.ssao_radius = RenderCfg.SSAO_RADIUS_M
    env.ssao_intensity = RenderCfg.SSAO_INTENSITY
    env.ssao_power = RenderCfg.SSAO_POWER
    env.ssao_detail = RenderCfg.SSAO_DETAIL
    env.ssao_horizon = RenderCfg.SSAO_HORIZON
    env.ssao_sharpness = RenderCfg.SSAO_SHARPNESS
    env.ssao_light_affect = RenderCfg.SSAO_LIGHT_AFFECT
    env.ssao_ao_channel_affect = RenderCfg.SSAO_REFLECTION_AFFECT


## The haze across the distance, and whether the air catches light.
##
## **Both were built once and never graded, which is why a night was a grey day.** The haze was
## set in `_build_environment` from constants, so switching the weather left a daylight fog —
## a pale grey 0.68, 0.72, 0.78 — hanging over a moonlit sky, and the horizon glowed through
## the dark. An hour of the day states its own air or keeps the default one.
##
## Volumetric fog is the froxel grid, and it is off everywhere but the night presets that ask
## for it. It costs a pass and it buys exactly one thing: a headlight beam you can see as a
## shaft in the air rather than only as a pool on the road.
static func _haze(env: Environment, weather: Dictionary) -> void:
    env.fog_enabled = RenderCfg.FOG_ENABLED
    env.fog_density = float(weather.get("fog_density", RenderCfg.FOG_DENSITY))
    env.fog_light_color = weather.get("fog_colour", RenderCfg.FOG_COLOUR) as Color
    env.fog_sky_affect = RenderCfg.FOG_SKY_AFFECT
    env.volumetric_fog_enabled = bool(weather.get("volumetric", false))
    env.volumetric_fog_density = RenderCfg.VOLUMETRIC_DENSITY
    env.volumetric_fog_albedo = weather.get("fog_colour", RenderCfg.FOG_COLOUR) as Color
    env.volumetric_fog_length = RenderCfg.VOLUMETRIC_LENGTH_M
    # The sky must not pour light into the froxels: an ambient term in the air is a grey wash
    # over the whole frame, and what a beam has to stand out against at night is darkness.
    env.volumetric_fog_ambient_inject = 0.0
    env.volumetric_fog_gi_inject = 0.0
