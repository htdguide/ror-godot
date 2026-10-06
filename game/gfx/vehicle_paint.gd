class_name VehiclePaint
extends RefCounted
## The layered surfaces Godot's own material cannot draw: coated paint, and cloth.
##
## `StandardMaterial3D` covers metallic-roughness, and for most of a vehicle that is the whole
## answer — a tyre, a rim, a pane of glass is one layer and the built-in material draws it. Two of
## the classes `MaterialCfg` states are not one layer, and this is where those go.
##
## **A clear coat.** Godot has the property and it does not layer. Measured on one ball under the
## project's own noon at a fixed exposure, with nothing changing but the coat
## (`harness/dev/paint_probe.gd`), the built-in material trades the paint away for the highlight —
## a full coat keeps 0.840 of the paint head-on where a film at IOR 1.5 reflects 4% and should keep
## 0.96. This shader keeps 0.965. That difference is what `MaterialCfg` records as panels reading
## "half transparent", and why the project's car paint sits at a coat of 0.25: a number picked to
## hide an artefact rather than to describe a surface.
##
## **A sheen.** `StandardMaterial3D` in 4.7 has no such property at all, so the sheen
## `MaterialCfg` has stated for seats and tyres since it was written has never been read by
## anything.
##
## Everything else keeps the built-in material, which matters for more than tidiness: a lamp's lens
## is switched between authored frames by `MaterialFlares`, and that reaches into
## `albedo_texture` and `emission_enabled`.

const SHADER_PATH: String = "res://game/shaders/vehicle_paint.gdshader"
## Where the class the material was built from is kept, for anything that needs to ask later.
const BUILT_AS: StringName = &"material_class"


## Whether a material class needs this shader rather than the built-in material.
static func wants(class_key: String) -> bool:
    var params: Dictionary = MaterialCfg.CLASSES.get(
        class_key, MaterialCfg.CLASSES["default"]
    ) as Dictionary
    return float(params["clearcoat"]) > 0.0 or float(params["sheen"]) > 0.0


## The same surface, as a layered material.
##
## Translated from the built-in material rather than built beside it, so that there is one place
## where a legacy material becomes a Godot one and this is a step on the end of it. Whatever
## `MeshAssembler` learns to read next arrives here without being read twice.
static func from_standard(standard: StandardMaterial3D, class_key: String) -> ShaderMaterial:
    var params: Dictionary = MaterialCfg.CLASSES.get(
        class_key, MaterialCfg.CLASSES["default"]
    ) as Dictionary
    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = load(SHADER_PATH) as Shader
    material.set_shader_parameter("albedo", standard.albedo_color)
    material.set_shader_parameter("metallic", standard.metallic)
    material.set_shader_parameter("roughness", standard.roughness)
    material.set_shader_parameter("clearcoat", float(params["clearcoat"]))
    material.set_shader_parameter("clearcoat_roughness", MaterialCfg.CLEARCOAT_ROUGHNESS)
    material.set_shader_parameter("sheen", float(params["sheen"]))
    material.set_shader_parameter("sheen_roughness", MaterialCfg.SHEEN_ROUGHNESS)
    material.set_shader_parameter("emission_energy", (
        standard.emission_energy_multiplier if standard.emission_enabled else 0.0
    ))
    if standard.albedo_texture != null:
        material.set_shader_parameter("albedo_texture", standard.albedo_texture)
        material.set_shader_parameter("albedo_textured", true)
    if standard.roughness_texture != null:
        material.set_shader_parameter("roughness_texture", standard.roughness_texture)
        material.set_shader_parameter("roughness_textured", true)
    material.set_meta(BUILT_AS, class_key)
    # Whatever the built-in material was carrying for other code to find — which surface of the
    # mod this came from, for one. See `MeshAssembler.material_for`.
    for key: StringName in standard.get_meta_list():
        material.set_meta(key, standard.get_meta(key))
    return material


## Whether a material is one of these.
static func is_paint(material: Material) -> bool:
    var shaded: ShaderMaterial = material as ShaderMaterial
    return (
        shaded != null and shaded.shader != null
        and shaded.shader.resource_path == SHADER_PATH
    )


## What a vehicle surface's albedo is, whichever kind of material it turned out to be. For the
## checks and tools that read a built surface back: a facing check redraws every surface in its own
## shader and keeps the albedo, and it has no business knowing how the surface was put together.
static func albedo_colour(material: Material) -> Color:
    if is_paint(material):
        return (material as ShaderMaterial).get_shader_parameter("albedo") as Color
    var standard: BaseMaterial3D = material as BaseMaterial3D
    return Color.WHITE if standard == null else standard.albedo_color


static func albedo_map(material: Material) -> Texture2D:
    if is_paint(material):
        return (material as ShaderMaterial).get_shader_parameter("albedo_texture") as Texture2D
    var standard: BaseMaterial3D = material as BaseMaterial3D
    return null if standard == null else standard.albedo_texture


## The roughness map a surface carries, which for a legacy mod is its own specular map inverted.
static func roughness_map(material: Material) -> Texture2D:
    if is_paint(material):
        return (material as ShaderMaterial).get_shader_parameter("roughness_texture") as Texture2D
    var standard: BaseMaterial3D = material as BaseMaterial3D
    return null if standard == null else standard.roughness_texture
