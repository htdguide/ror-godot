class_name WingRows
extends RefCounted
## Reads `wings` rows: upstream's `ParseWing`, and the airfoil each names.
##
##   8 nodes, 8 texture coordinates [, control surface, chord point, min deflection,
##   max deflection, airfoil, efficacy]
##
## Upstream skips a wing that names no airfoil (`ProcessWing`), and finds the airfoil file as any
## resource: the vehicle's own, or the game's (`resources/airfoils`). One it cannot find leaves the
## wing with an all-zero polar, which pushes nothing.

const GAME_AIRFOILS: String = "vendor/rigs-of-rods/resources/airfoils"
## Upstream's `GetArgWingSurface`: anything else falls back to `n`.
const SURFACES: String = "nabferSTcdghUVij"


## {nodes, type, chord_point, min_deflection, max_deflection, airfoil, efficacy} or {error}.
static func read(fields: PackedStringArray, id_to_index: Dictionary) -> Dictionary:
    if fields.size() < 16:
        return {"error": "row has %d fields, expected at least 16" % fields.size()}
    var nodes: PackedInt32Array = PackedInt32Array()
    for i: int in 8:
        var node: int = int(id_to_index.get(fields[i], -1))
        if node < 0:
            return {"error": "row references an unknown node"}
        nodes.append(node)
    var surface: String = fields[16].substr(0, 1) if fields.size() > 16 else "n"
    if not SURFACES.contains(surface) or surface.is_empty():
        surface = "n"
    return {
        "error": "", "nodes": nodes, "type": surface,
        "chord_point": fields[17].to_float() if fields.size() > 17 else -1.0,
        "min_deflection": fields[18].to_float() if fields.size() > 18 else -1.0,
        "max_deflection": fields[19].to_float() if fields.size() > 19 else -1.0,
        "airfoil": fields[20] if fields.size() > 20 else "",
        "efficacy": fields[21].to_float() if fields.size() > 21 else 1.0,
    }


## Builds `wings` into `solver`, reading each airfoil from `mod_dir` or the game's own.
static func build(solver: RefCounted, wings: Array[Dictionary], mod_dir: String) -> void:
    var texts: Dictionary = {}
    for wing: Dictionary in wings:
        var name: String = wing["airfoil"]
        if name == "":
            continue
        if not texts.has(name):
            texts[name] = airfoil_text(name, mod_dir)
        solver.add_wing(wing["nodes"], wing["type"], wing["chord_point"], wing["min_deflection"], wing["max_deflection"],
                texts[name], wing["efficacy"])
    solver.finish_wings()


## The airfoil file `name`'s text, from the vehicle's folder or the game's; "" when neither has it.
static func airfoil_text(name: String, mod_dir: String) -> String:
    for dir: String in [mod_dir, SourceScan.repo_root().path_join(GAME_AIRFOILS)]:
        if dir == "":
            continue
        for file: String in DirAccess.get_files_at(dir):
            if file.to_lower() == name.to_lower():
                return FileAccess.get_file_as_string(dir.path_join(file))
    return ""
