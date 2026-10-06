class_name WorldSky
extends RefCounted
## What is above a scene, and how much of the light in the picture comes from it.
##
## Split out of `BlockoutWorld` when that file went over the source cap, and it is a seam rather
## than a slice: every function here answers that one question, and what is left in
## `BlockoutWorld` is geometry, lights and grading.


## Tells the sky what the camera is now, after a live exposure change.
##
## The sky is built from the hour, and the hour states its exposure, so a world and its camera
## agree when they are made. A session that moves the exposure afterwards — or a check that
## photographs one scene on several films — would otherwise leave the sky metered for the camera
## it was built with, and the sky would start following the camera again. See
## `PhysicalCamera.exposure_scale`.
static func reexpose(root: Node3D, camera: Camera3D) -> void:
    var holder: WorldEnvironment = root.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    if holder == null or holder.environment == null:
        return
    var scale: float = maxf(PhysicalCamera.exposure_scale_of(camera), 0.000001)
    holder.environment.ambient_light_energy = (
        float(holder.environment.get_meta(STATED_AMBIENT, 0.0)) * scale
    )
    if holder.environment.sky == null:
        return
    var shaded: ShaderMaterial = holder.environment.sky.sky_material as ShaderMaterial
    if shaded != null:
        shaded.set_shader_parameter("light_exposure", scale)


## Where an environment keeps the ambient the hour stated, before the camera was applied to it.
const STATED_AMBIENT: StringName = &"stated_ambient_energy"


## Whether this world's sky has weather in it.
##
## Off by default, and a session turns it on. The reason is the light: a cloud sky is a different
## sky, and every lighting gate in this project is graded against the stated gradient — measured,
## swapping the sky under them took the hero truck from 2.27x brighter lit from the front to
## 1.02x and stopped the tunnel being darker inside than out. So the gates keep the sky they were
## written against, the window gets the one with weather in it, and `the_sky_has_weather_in_it`
## asks for clouds explicitly. That the two are not the same sky is a real gap, and it is the
## same gap as the project's sun-to-sky balance: both want the HDRI work in M2.
##
## Threaded as a parameter rather than held in a `static var`, which is what it was: a build
## option smuggled through process-global state, so the sky a world got depended on what the
## last world to be built had asked for. Invisible with one world per process and an
## order-dependent bug the moment there is not — which is what D0's containers exist to stop.
static func of(weather: Dictionary, clouds: bool) -> Sky:
    # An hour may ask for this project's own sky shader whatever the session is doing. The night
    # does, because it is the only sky with a radiance scale — see the uniform in
    # `sky_clouds.gdshader` — and a gate and a window have to be looking at the same night.
    # A captured sky where the hour names one and the checkout has it. First, because it is the
    # only sky here that carries a real sun-to-sky balance rather than stating one.
    var captured: ShaderMaterial = SkyHdri.material(weather)
    if captured != null:
        return _new(captured)
    if bool(weather.get("sky_shader", false)) or (clouds and RenderCfg.CLOUDS_ENABLED):
        var clouded: ShaderMaterial = SkyClouds.material(weather)
        if clouded != null:
            return _new(clouded)
    return _new(
        _physical(weather) if bool(weather.get("physical_sky", false))
        else _gradient(weather)
    )


## A sky with its radiance map built once and built properly.
##
## **`process_mode` is the whole of this function's reason to exist.** Left at its default the
## radiance map is approximated across frames, and a scene that is not moving at all then renders
## two different images on alternate frames: measured on the hero truck's drop, a band of distant
## ground alternated between 0.6703 and 0.9906 luminance — the far half of the checker washing to
## pure white and back, every other frame, long after the truck had come to rest. The ground is
## rough and takes its specular from the sky's radiance map, so an unconverged map lands there
## first and lands hardest at grazing angles, which is why it was the distance that flickered.
##
## It was reported by eye before any gate caught it, and both skies had the same omission — the
## clouded one built its own `Sky` — which is why they now share one constructor.
static func _new(material: Material) -> Sky:
    var sky: Sky = Sky.new()
    sky.process_mode = Sky.PROCESS_MODE_QUALITY
    sky.radiance_size = RenderCfg.SKY_RADIANCE_SIZE as Sky.RadianceSize
    sky.sky_material = material
    return sky


## A clear sky from an atmosphere model: Rayleigh scattering for the blue and the pale horizon,
## Mie for the haze around the sun, turbidity for how clean the air is.
##
## This is what `physical_sky` in a weather preset has always claimed and did not do — the flag
## selected a two-colour gradient. The difference that matters is not the look, it is where the
## irradiance comes from: a gradient's is whatever its colours integrate to, so the sun-to-sky
## balance was two numbers somebody chose, and it came out around 3:1 where clear daylight is
## nearer 14:1. A model produces the ratio rather than being told it.
##
## The sun direction is not set here. `PhysicalSkyMaterial` takes it from the first
## `DirectionalLight3D` in the world, which is `BlockoutWorld`'s, so the sky and the sun agree about
## where the sun is by construction instead of by two configs matching.
static func _physical(weather: Dictionary) -> PhysicalSkyMaterial:
    var material: PhysicalSkyMaterial = PhysicalSkyMaterial.new()
    material.rayleigh_coefficient = RenderCfg.RAYLEIGH_COEFFICIENT
    material.rayleigh_color = RenderCfg.RAYLEIGH_COLOR
    material.mie_coefficient = RenderCfg.MIE_COEFFICIENT
    material.mie_eccentricity = RenderCfg.MIE_ECCENTRICITY
    material.mie_color = RenderCfg.MIE_COLOR
    material.turbidity = float(weather.get("turbidity", RenderCfg.TURBIDITY))
    material.sun_disk_scale = RenderCfg.SUN_DISK_SCALE
    material.ground_color = RenderCfg.SKY_GROUND_COLOR
    # **This material is not a radiance source and cannot be made into one.** Godot's physical sky
    # is a Preetham model with a tone curve on the end of it, and the curve is applied to the
    # sun's own energy: measured on one unchanged scene at a fixed exposure, doubling the sun's
    # lux brightened the sky by 1.54 rather than by 2, four times in a row — a response of
    # `light ^ 0.625`. Under physical light units the light it is handed already carries the
    # camera's exposure, so the sky moves with the film as well, and no multiplier on the outside
    # can undo a power applied on the inside. M2's HDRI sky is what replaces it; until then a
    # daylight preset's sky is a picture rather than a measurement, and
    # `the_sky_does_not_follow_the_camera` holds the claim for the sky this project draws itself.
    material.energy_multiplier = float(weather.get("sky_energy", RenderCfg.SKY_ENERGY))
    return material


## The two-colour gradient, kept for the presets that are not a clear daylight sky — a night or a
## stated-colour preset has no atmosphere to model and a gradient is the honest way to say so.
static func _gradient(weather: Dictionary) -> ProceduralSkyMaterial:
    var material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
    material.sky_top_color = weather.get("sky_top", RenderCfg.SKY_TOP) as Color
    material.sky_horizon_color = weather.get("sky_horizon", RenderCfg.SKY_HORIZON) as Color
    material.sky_curve = RenderCfg.SKY_CURVE
    material.ground_bottom_color = RenderCfg.GROUND_COLOR
    material.ground_horizon_color = RenderCfg.GROUND_HORIZON
    material.sun_angle_max = RenderCfg.SUN_ANGLE_MAX_DEG
    material.sun_curve = RenderCfg.SUN_CURVE
    material.energy_multiplier = float(weather.get("sky_energy", RenderCfg.SKY_ENERGY))
    return material
