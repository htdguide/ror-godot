class_name SkyHdri
extends RefCounted
## The captured skies, and what each one is worth as light.
##
## A weather preset names a panorama and states its energy; everything else about how it is drawn
## is in `shaders/sky_hdri.gdshader`. The maps are Poly Haven's, CC0, 2k Radiance HDR — see
## `THIRD_PARTY.md` — and they are "pure sky" captures with no ground in them, because this
## project's ground is a terrain a mod author shipped and a second horizon in the sky is a seam
## nobody can unsee.

const SHADER_PATH: String = "res://game/shaders/sky_hdri.gdshader"
const DIRECTORY: String = "res://assets/hdri"


## The sky material for a weather preset, or null when it names no map or the map is absent.
static func material(weather: Dictionary) -> ShaderMaterial:
    var file: String = weather.get("hdri", "") as String
    if file.is_empty():
        return null
    var panorama: Texture2D = texture(file)
    if panorama == null:
        return null
    var shader: Shader = load(SHADER_PATH) as Shader
    if shader == null:
        return null
    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("panorama", panorama)
    material.set_shader_parameter(
        "energy", float(weather.get("sky_energy", RenderCfg.SKY_ENERGY))
    )
    material.set_shader_parameter(
        "radiance_scale", float(weather.get("radiance_scale", 1.0))
    )
    material.set_shader_parameter(
        "radiance_clamp", float(weather.get("radiance_clamp", RenderCfg.SKY_SUN_CLAMP))
    )
    # See the uniform: the engine exposes a sky's light twice and a lamp's once.
    material.set_shader_parameter("light_exposure", PhysicalCamera.exposure_scale(weather))
    return material


## One panorama, or null when the file is not in the checkout. Absent rather than fatal: the maps
## are 17 MB of captured sky and a gate that needs one says so and skips.
static func texture(file: String) -> Texture2D:
    var path: String = DIRECTORY.path_join(file)
    if not ResourceLoader.exists(path):
        return null
    return load(path) as Texture2D


## Whether this checkout has the captured skies in it.
static func present(weather: Dictionary) -> bool:
    var file: String = weather.get("hdri", "") as String
    return not file.is_empty() and ResourceLoader.exists(DIRECTORY.path_join(file))
