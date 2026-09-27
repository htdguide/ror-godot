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
            }
            continue
        if current.is_empty():
            continue
        _take(out[current] as Dictionary, line)
    return out


## One line inside a material block.
static func _take(material: Dictionary, line: String) -> void:
    var words: PackedStringArray = line.split(" ", false)
    if words.is_empty():
        return
    match words[0].to_lower():
        "texture":
            if words.size() > 1:
                var textures: PackedStringArray = material["textures"] as PackedStringArray
                textures.append(words[1])
                material["textures"] = textures
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
