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


## Roughness from a stated Blinn-Phong exponent.
##
## **The one thing the legacy format says about how polished a surface is.** An Ogre pass writes
## `specular <r> <g> <b> <shininess>`, and the exponent is the Blinn-Phong lobe's own width. Walter
## et al. (2007) give the equivalence between that lobe and a microfacet one:
##
##     alpha = sqrt(2 / (n + 2))
##
## and this project, like glTF and like Godot, stores `alpha = roughness^2`, so the roughness is the
## fourth root. Nothing in it is chosen: 10 converts to 0.639, 12.5 to 0.609, 33 to 0.489. What is
## chosen is the band it is held inside — see `MaterialCfg.SHININESS_ROUGHNESS_MIN`.
##
## This beats the class's own constant, because a class is what a material is guessed to be and
## this is what its author wrote down. A specular *map* still beats both, being per-pixel.
static func roughness_from_shininess(shininess: float) -> float:
    var alpha: float = sqrt(2.0 / (maxf(shininess, 0.0) + 2.0))
    return clampf(
        sqrt(alpha), MaterialCfg.SHININESS_ROUGHNESS_MIN, MaterialCfg.SHININESS_ROUGHNESS_MAX
    )


## Turns a legacy specular map into a roughness map.
##
## Specular intensity and roughness are opposites, so the value is inverted, then
## compressed into a plausible band: these maps are artists' intensity masks rather than
## measured reflectance, and taken literally they produce mirror-finish panels next to
## chalk.
static func roughness_from_specular(specular: Image) -> Image:
    # A block-compressed source has to be decompressed first. `get_pixel` on one returns black
    # and logs "Can't get_pixel() on compressed image, sorry." — per pixel, which for a single
    # 512-square map is a quarter of a million lines. Reading a `mesh_standard` material's
    # specular map from the slot upstream puts it in meant these maps arrived here compressed for
    # the first time, and one suite run wrote 72 MB of that before bash gave up allocating.
    if specular.is_compressed():
        specular = specular.duplicate() as Image
        if specular.decompress() != OK:
            return Image.create(1, 1, false, Image.FORMAT_R8)
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
