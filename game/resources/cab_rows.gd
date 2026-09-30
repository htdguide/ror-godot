class_name CabRows
extends RefCounted
## Parses the `texcoords` and `cab` sections: the node-indexed triangle hull.
##
## On the hero truck this is collision geometry and nothing else — it declares no
## texcoords at all, its material is `tracks/trans`, and every triangle is flagged `c`.
## Other rigs use the same sections for visible bodywork, which is what a texcoord list
## turns them into, so both are read and what they mean is left to the caller.


## Returns {"error": String, "node": int, "uv": Vector2}.
static func texcoord(fields: PackedStringArray, id_to_index: Dictionary) -> Dictionary:
    if fields.size() < 3:
        return {"error": "row has %d fields, expected 3" % fields.size()}
    var node: int = int(id_to_index.get(fields[0], -1))
    if node < 0:
        return {"error": "row references an unknown node"}
    return {
        "error": "",
        "node": node,
        "uv": Vector2(fields[1].to_float(), fields[2].to_float()),
    }


## Returns {"error": String, "nodes": PackedInt32Array} for one triangle. Trailing flags
## (`c` for contacter, `b` for buoyant, and the rest) follow the three node ids.
static func triangle(fields: PackedStringArray, id_to_index: Dictionary) -> Dictionary:
    if fields.size() < 3:
        return {"error": "row has %d fields, expected at least 3" % fields.size()}
    var out: PackedInt32Array = PackedInt32Array()
    for i: int in 3:
        var node: int = int(id_to_index.get(fields[i], -1))
        if node < 0:
            return {"error": "row references an unknown node"}
        out.append(node)
    return {"error": "", "nodes": out}
