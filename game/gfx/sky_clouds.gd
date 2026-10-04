class_name SkyClouds
extends RefCounted
## Builds the sky a session looks at: a gradient with marched clouds in it.
##
## The gradient is the same one `RenderCfg` states and the weather presets override, so the light
## the scene is graded against does not move when the clouds do. What is added is a cloud slab —
## `shaders/sky_clouds.gdshader` — which is also what the radiance map is convolved from, so an
## overcast sky lights the scene like an overcast sky rather than only looking like one.
##
## Every parameter is a uniform on the material, which is what lets the environment panel move
## the weather while a session runs.

const SHADER_PATH: String = "res://game/shaders/sky_clouds.gdshader"


## The sky material for a weather preset, or null when the shader is missing.
static func material(weather: Dictionary) -> ShaderMaterial:
    var shader: Shader = load(SHADER_PATH) as Shader
    if shader == null:
        return null
    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter(
        "sky_top", weather.get("sky_top", RenderCfg.SKY_TOP) as Color
    )
    material.set_shader_parameter(
        "sky_horizon", weather.get("sky_horizon", RenderCfg.SKY_HORIZON) as Color
    )
    material.set_shader_parameter("ground_colour", RenderCfg.GROUND_HORIZON)
    # How much of the sky's brightness reaches the radiance map every glossy surface reflects.
    # A night states a fraction here: see the uniform's own note in the shader.
    material.set_shader_parameter(
        "radiance_scale", float(weather.get("radiance_scale", 1.0))
    )
    # The stars, which an hour of the day turns up as its sky goes out.
    material.set_shader_parameter("stars", float(weather.get("stars", 0.0)))
    # How much light is on the clouds. A preset that says nothing is a daylight one.
    material.set_shader_parameter(
        "cloud_light", float(weather.get("cloud_light", 1.0))
    )
    # How bright the disc of whatever is up is drawn. A moon is not scaled by the night sky's
    # own four ten-thousandths or there is no moon.
    material.set_shader_parameter(
        "disc_energy", float(weather.get("disc_energy", 1.0))
    )
    material.set_shader_parameter("sky_curve", RenderCfg.SKY_CURVE)
    material.set_shader_parameter(
        "sky_energy", float(weather.get("sky_energy", RenderCfg.SKY_ENERGY))
    )
    material.set_shader_parameter("cloud_colour", RenderCfg.CLOUD_LIT)
    material.set_shader_parameter("cloud_shadow", RenderCfg.CLOUD_SHADED)
    material.set_shader_parameter(
        "coverage", float(weather.get("cloud_coverage", RenderCfg.CLOUD_COVERAGE))
    )
    material.set_shader_parameter(
        "density", float(weather.get("cloud_density", RenderCfg.CLOUD_DENSITY))
    )
    material.set_shader_parameter("cloud_bottom_m", RenderCfg.CLOUD_BOTTOM_M)
    material.set_shader_parameter("cloud_top_m", RenderCfg.CLOUD_TOP_M)
    material.set_shader_parameter("cloud_scale_m", RenderCfg.CLOUD_SCALE_M)
    material.set_shader_parameter("detail_scale", RenderCfg.CLOUD_DETAIL_SCALE)
    material.set_shader_parameter("erosion", RenderCfg.CLOUD_EROSION)
    material.set_shader_parameter("wind", RenderCfg.CLOUD_WIND)
    material.set_shader_parameter("wind_speed", RenderCfg.CLOUD_WIND_SPEED)
    material.set_shader_parameter("steps", RenderCfg.CLOUD_STEPS)
    material.set_shader_parameter("radiance_steps", RenderCfg.CLOUD_RADIANCE_STEPS)
    material.set_shader_parameter("light_steps", RenderCfg.CLOUD_LIGHT_STEPS)
    return material


## How cloudy the sky in an environment is, and how solid, for a panel to move. Returns {} when
## the sky is not a cloud sky.
static func settings(environment: Environment) -> Dictionary:
    var material: ShaderMaterial = _material_of(environment)
    if material == null:
        return {}
    return {
        "coverage": material.get_shader_parameter("coverage") as float,
        "density": material.get_shader_parameter("density") as float,
        "wind_speed": material.get_shader_parameter("wind_speed") as float,
    }


## Changes one of them on a live sky.
static func set_parameter(environment: Environment, name: String, value: float) -> void:
    var material: ShaderMaterial = _material_of(environment)
    if material == null:
        return
    material.set_shader_parameter(name, value)


static func _material_of(environment: Environment) -> ShaderMaterial:
    if environment == null or environment.sky == null:
        return null
    return environment.sky.sky_material as ShaderMaterial
