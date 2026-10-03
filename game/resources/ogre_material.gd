class_name OgreMaterial
extends RefCounted
## Reads Ogre material scripts: which texture a named material draws with, and how.
##
## A terrain's meshes name materials, and the materials live in `.material` scripts beside them.
## The format is a brace language with inheritance — `material lapaz-pole: RoR/Managed_Mats/Base`
## — and the parents are Rigs of Rods' own core resources, which a terrain does not ship. So what
## can be read from a terrain's own files is the leaf: its texture, whether it blends, and
## whether it is lit.
##
## That is enough to draw with. The parents set up Ogre techniques and shader parameters that
## mean nothing here anyway; what matters is that a pole is drawn with the pole's texture and
## that a horizon painted on an alpha-blended card is not drawn as an opaque wall.

## Blend modes that mean the material has transparency.
const ALPHA_BLENDS: Array[String] = ["alpha_blend", "alpha_rejection"]
## The alias a managed material sets for the texture it draws with. Rigs of Rods' own
## `RoR/Managed_Mats/*` templates declare the `texture_unit` and leave the file to the leaf, which
## names it with `set_texture_alias diffuse_tex <file>` and no `texture` line anywhere. 23 of the
## 328 inheriting materials in this checkout are textured only this way, `tracks/master` among
## them, and every one of them drew untextured.
const DIFFUSE_ALIAS: String = "diffuse_tex"


## Reads every .material script in a directory. Returns name -> {"textures", "alpha", "lit",
## "scale"}.
static func read_directory(directory: String) -> Dictionary:
    var out: Dictionary = {}
    for file: String in DirAccess.get_files_at(directory):
        if file.get_extension().to_lower() != "material":
            continue
        var script: Dictionary = read(directory.path_join(file))
        for name: String in script.keys():
            out[name] = script[name]
    return out


## Reads one .material script.
static func read(path: String) -> Dictionary:
    var text: String = RorText.read(path)
    if text.is_empty():
        return {}
    var out: Dictionary = {}
    var current: String = ""
    for raw_line: String in text.split("\n"):
        var line: String = RorText.strip_comment(raw_line)
        if line.is_empty():
            continue
        if line.to_lower().begins_with("material "):
            # `material <name> : <parent>` — the parent is a core resource a terrain does not
            # ship, so only the name is kept.
            current = line.substr(9).get_slice(":", 0).strip_edges()
            out[current] = {
                "textures": PackedStringArray(),
                "alpha": false,
                "lit": true,
                "scale": Vector2.ONE,
                # What the material is painted when it has no texture. A fixed-function Ogre
                # pass is allowed to be a plain colour, and 18 materials in this checkout are:
                # Starling Island's `rey_si_dark` is 0.13 grey and drew at 0.72, five and a half
                # times too bright, which is most of what "the map is all white" looked like.
                # White here means "not stated", so an undeclared material keeps the loader's own
                # placeholder instead of being painted white by this default.
                "diffuse": Color.WHITE,
                "has_diffuse": false,
            }
            continue
        if current.is_empty():
            continue
        _take(out[current] as Dictionary, line)
    return out


## One line inside a material block.
static func _take(material: Dictionary, line: String) -> void:
    # Split on whitespace, not on spaces. Ogre scripts are written with tabs as often as not and
    # Russia's vegetation uses them throughout: `texture\tRussia-Grass1.png` read as a single
    # word matched no keyword, so three grass materials declared a texture apiece and this
    # project found none of them. Reported from a window as "grass is still white textures".
    var words: PackedStringArray = line.replace("\t", " ").split(" ", false)
    if words.is_empty():
        return
    match words[0].to_lower():
        "texture":
            if words.size() > 1:
                var textures: PackedStringArray = material["textures"] as PackedStringArray
                textures.append(words[1])
                material["textures"] = textures
        # `anim_texture <base> <frames> <duration>` names a flipbook, and the base is **not a
        # file**: Ogre expands it to `base_0.ext`, `base_1.ext` and so on. The Mazda 626 declares
        # its headlights, indicators, brake and fog lights this way, naming
        # `mazda626gf-sd-lights.dds` while shipping `mazda626gf-sd-lights_0.dds` and `_1.dds`, so
        # taking the name as written finds nothing and the lamp draws untextured. The first frame
        # is what a still picture should show.
        "anim_texture":
            if words.size() > 2:
                var textures: PackedStringArray = material["textures"] as PackedStringArray
                textures.append("%s_0.%s" % [words[1].get_basename(), words[1].get_extension()])
                material["textures"] = textures
        # `set_texture_alias <alias> <file>` — the leaf of a managed material, see DIFFUSE_ALIAS.
        "set_texture_alias":
            if words.size() > 2 and words[1] == DIFFUSE_ALIAS:
                var aliased: PackedStringArray = material["textures"] as PackedStringArray
                # Front, because the first texture is the albedo everywhere this is read.
                aliased.insert(0, words[2])
                material["textures"] = aliased
        # `diffuse <r> <g> <b> [a]`, or `diffuse vertexcolour`, which states no colour.
        "diffuse":
            if words.size() > 3 and words[1].is_valid_float():
                material["diffuse"] = Color(
                    words[1].to_float(), words[2].to_float(), words[3].to_float(),
                    words[4].to_float() if words.size() > 4 else 1.0
                )
                material["has_diffuse"] = true
                # Ogre's fixed-function alpha lives in the diffuse colour, and `train_rails`
                # declares `invisible` as `diffuse 0 0 0 0` with `scene_blend alpha_blend`. Drawn
                # opaque it is a grey box standing where nothing should be.
                if (material["diffuse"] as Color).a < 1.0:
                    material["alpha"] = true
        "scene_blend":
            if words.size() > 1 and ALPHA_BLENDS.has(words[1].to_lower()):
                material["alpha"] = true
        "alpha_rejection":
            material["alpha"] = true
        "lighting":
            if words.size() > 1:
                material["lit"] = words[1].to_lower() != "off"
        "scale":
            if words.size() > 2:
                material["scale"] = Vector2(words[1].to_float(), words[2].to_float())
