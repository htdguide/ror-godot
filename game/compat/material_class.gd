class_name MaterialClass
extends RefCounted
## Assigns a material class to a legacy material, and builds the PBR material for it.
##
## Sources, in descending order of trust (ADR 0001):
##   1. the managedmaterials declaration — an explicit transparency effect, and a specular
##      map, are authored data rather than a guess
##   2. the material and texture names
##   3. the class table's default
##
## What is deliberately not derived: normal maps, ambient occlusion, and metallic. Each is
## a guess whose failure looks worse than the absence it replaces.


## Returns {"class": String, "reason": String}.
static func classify(material_name: String, declared: Dictionary) -> Dictionary:
    var effect: String = (declared.get("effect", "") as String).to_lower()
    if effect.contains("transparent"):
        # Upstream said transparent. That is a statement about the surface, not a hint.
        var lowered_name: String = material_name.to_lower()
        if lowered_name.contains("light") or lowered_name.contains("flare"):
            return {"class": "lamp", "reason": "declared transparent, named as a light"}
        return {"class": "glass", "reason": "declared transparent"}

    var haystack: String = material_name.to_lower()
    for texture: String in declared.get("textures", PackedStringArray()) as PackedStringArray:
        haystack += " " + texture.to_lower()
    for hint: Array in MaterialCfg.NAME_HINTS:
        if haystack.contains(hint[0] as String):
            return {"class": hint[1] as String, "reason": "named '%s'" % hint[0]}

    # A body material with a specular map is a painted panel more often than anything else,
    # and the paint class is what the specular map is most useful for.
    if (declared.get("textures", PackedStringArray()) as PackedStringArray).size() > 2:
        return {"class": "car_paint", "reason": "supplies a specular map"}
    return {"class": "default", "reason": "unrecognised"}


## Applies a class to a Godot material.
static func apply(material: StandardMaterial3D, class_name_key: String) -> void:
    var params: Dictionary = MaterialCfg.CLASSES.get(
        class_name_key, MaterialCfg.CLASSES["default"]
    ) as Dictionary
    material.metallic = float(params["metallic"])
    material.roughness = float(params["roughness"])
    if float(params["clearcoat"]) > 0.0:
        material.clearcoat_enabled = true
        material.clearcoat = float(params["clearcoat"])
    if float(params["emission"]) > 0.0:
        material.emission_enabled = true
        material.emission_energy_multiplier = float(params["emission"])
    # Culling stays as authored. Disabling it globally was tried, to stop single-sided
    # panels reading as transparent when seen from behind, and it made the vehicle worse:
    # the inside faces of the far panels then draw over the near ones, and from the sides
    # the truck renders as a smooth white shell with no detail. A panel that is invisible
    # from its back face is what the mod actually is.
    if bool(params["transmission"]):
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        material.cull_mode = BaseMaterial3D.CULL_DISABLED


## Turns a legacy specular map into a roughness map.
##
## Specular intensity and roughness are opposites, so the value is inverted, then
## compressed into a plausible band: these maps are artists' intensity masks rather than
## measured reflectance, and taken literally they produce mirror-finish panels next to
## chalk.
static func roughness_from_specular(specular: Image) -> Image:
    var out: Image = Image.create(
        specular.get_width(), specular.get_height(), false, Image.FORMAT_R8
    )
    var span: float = MaterialCfg.SPEC_ROUGHNESS_MAX - MaterialCfg.SPEC_ROUGHNESS_MIN
    for y: int in specular.get_height():
        for x: int in specular.get_width():
            var intensity: float = specular.get_pixel(x, y).get_luminance()
            var roughness: float = MaterialCfg.SPEC_ROUGHNESS_MIN + (1.0 - intensity) * span
            out.set_pixel(x, y, Color(roughness, roughness, roughness))
    return out
