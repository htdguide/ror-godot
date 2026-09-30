class_name MaterialRows
extends RefCounted
## Parses the `managedmaterials` section: a vehicle's own material declarations.
##
## A row is "name effect texture...", with "-" standing for an absent texture. It carries more
## than it is usually credited with. The effect names the transparency the material needs
## outright, so glass does not have to be guessed at from a name; and a specular map, where a
## mod supplies one, is a real roughness source rather than a guess from diffuse luma.
##
## See ADR 0001 for what is derived from these and why.


static func handles(section: String) -> bool:
    return section == "managedmaterials"


## Returns {"error", "name", "effect", "textures"}.
static func row(fields: PackedStringArray) -> Dictionary:
    if fields.size() < 3:
        return {"error": "row has %d fields, expected at least 3" % fields.size()}
    var textures: PackedStringArray = PackedStringArray()
    for i: int in range(2, fields.size()):
        if fields[i] != "-":
            textures.append(fields[i])
    return {"error": "", "name": fields[0], "effect": fields[1], "textures": textures}
