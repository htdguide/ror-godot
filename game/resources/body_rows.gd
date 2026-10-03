class_name BodyRows
extends RefCounted
## The rows that say what a vehicle looks like: its flexbodies, its props, its flares and the
## materials it declares for them.
##
## Split out of `TruckParser` when that file went over the source cap, and it is a real seam:
## none of these touches the rig. A node row or a beam row builds the thing that is simulated;
## these four build the thing that is drawn, and each is the same shape — hand a row reader the
## line, keep what it returns or record why it could not be kept.
##
## The collections are passed in rather than held here. An `Array` and a `Dictionary` are
## references in GDScript, so a reader can fill the parser's own lists without the parser having
## to ask for them back, and `truck.flexbodies` stays where every caller already looks for it.


## `flexbodies` rows are "ref,x,y, offsetx,offsety,offsetz, rotx,roty,rotz, mesh", each optionally
## followed by `forset <ranges>` lines naming the nodes the mesh may bind to.
static func flexbody(
    line: String, id_to_index: Dictionary, into: Array[Dictionary], errors: PackedStringArray
) -> void:
    if line.begins_with("forset"):
        if into.is_empty():
            errors.append("forset before any flexbody: %s" % line)
            return
        into[into.size() - 1]["forset"] = NodeIdRanges.resolve(
            line.substr("forset".length()), id_to_index
        )
        return
    var row: Dictionary = PlacementRows.head(TruckLexer.fields(line), id_to_index)
    if not keep("flexbody", row, line, into):
        return
    into[into.size() - 1]["forset"] = PackedInt32Array()


static func prop(
    line: String, id_to_index: Dictionary, into: Array[Dictionary], errors: PackedStringArray
) -> void:
    keep("prop", PlacementRows.prop(TruckLexer.fields(line), id_to_index), line, into, errors)


static func flare(
    line: String, id_to_index: Dictionary, into: Array[Dictionary], errors: PackedStringArray
) -> void:
    keep("flare", FlareRows.row(TruckLexer.fields(line), id_to_index), line, into, errors)


## A `managedmaterials` row names a material, the effect it is drawn with, and its textures.
static func managed_material(
    line: String, into: Dictionary, errors: PackedStringArray
) -> void:
    var row: Dictionary = MaterialRows.row(TruckLexer.fields(line))
    if (row["error"] as String) != "":
        errors.append("managedmaterial %s: %s" % [row["error"], line])
        return
    into[row["name"] as String] = {"effect": row["effect"], "textures": row["textures"]}


## Keeps a parsed row, or records why it could not be kept. True when it was kept.
static func keep(
    section: String, row: Dictionary, line: String, into: Array[Dictionary],
    errors: PackedStringArray = PackedStringArray()
) -> bool:
    if (row["error"] as String) != "":
        errors.append("%s %s: %s" % [section, row["error"], line])
        return false
    row.erase("error")
    into.append(row)
    return true
