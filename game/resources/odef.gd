class_name Odef
extends RefCounted
## Reads a Rigs of Rods object definition: which meshes a named object is, and how big.
##
## The format is positional at the top — an optional obsolete `LOD` line, a mesh filename, then a
## scale triple — and then a series of small blocks: `beginbox`/`endbox` gives the object a
## collision box, `beginmesh`/`endmesh` gives it a collision **mesh**, and a handful of one-word
## lines set flags.
##
## **`beginmesh` is not more geometry to draw.** Upstream puts it straight into
## `collision_meshes` — `ODefFileFormat.cpp`, at `endmesh`:
##
##     m_def->collision_meshes.emplace_back(
##         m_ctx.cbox_mesh_name, m_ctx.header_scale, m_ctx.cbox_groundmodel_name);
##
## so the only thing an object draws is its header mesh. Read as drawn geometry instead, those
## hulls were rendered: Starling Island's `firehousebox.mesh`, `store02box.mesh`,
## `townhouse01box.mesh`, `haus5Kol.mesh` and `haus6Kol.mesh` stood over their buildings as
## untextured shells — a house with no texture, or half a one where the hull covered part of it —
## and every building on the map paid for a second mesh it should never have drawn.
##
## Only the geometry is read here. Collision boxes are counted so that a terrain's solid parts can
## be counted honestly; the flags are not read at all.


## Reads an .odef. Returns {"error", "meshes", "collision_meshes", "scale", "boxes"}.
static func read(path: String) -> Dictionary:
    var out: Dictionary = {
        "error": "",
        "meshes": PackedStringArray(),
        "collision_meshes": PackedStringArray(),
        "scale": Vector3.ONE,
        "boxes": 0,
    }
    var text: String = RorText.read(path)
    if text.is_empty():
        out["error"] = "the object definition at %s could not be read" % path
        return out
    var meshes: PackedStringArray = PackedStringArray()
    var hulls: PackedStringArray = PackedStringArray()
    var boxes: int = 0
    var seen: int = 0
    var in_mesh: bool = false
    for raw_line: String in text.split("\n"):
        var line: String = RorText.strip_comment(raw_line)
        if line.is_empty():
            continue
        # A bare `LOD` line before the header. Upstream reads it and throws it away —
        # `ODefFileFormat.cpp`: `if (strcmp(m_cur_line, "LOD") == 0) return true; // 'LOD line' =
        # obsolete`. Taken as the header's mesh name instead, it consumed the slot and the real
        # mesh on the next line was dropped: Starling Island's firehouse, office block and bus
        # stop drew their collision box and nothing else. 7 objects in this checkout start this
        # way.
        if seen == 0 and line.strip_edges() == "LOD":
            continue
        var word: String = line.get_slice(" ", 0).to_lower()
        match word:
            "beginmesh":
                in_mesh = true
                continue
            "endmesh":
                in_mesh = false
                continue
            "beginbox":
                boxes += 1
                continue
            "mesh":
                if in_mesh:
                    hulls.append(line.substr(line.find(" ") + 1).strip_edges())
                continue
        if seen == 0:
            meshes.append(line)
            seen += 1
            continue
        if seen == 1 and line.contains(","):
            out["scale"] = RorText.vector3(line)
            seen += 1
    out["meshes"] = _drawable(meshes)
    out["collision_meshes"] = _drawable(hulls)
    out["boxes"] = boxes
    if (out["meshes"] as PackedStringArray).is_empty():
        out["error"] = "%s names no mesh" % path.get_file()
    return out


## `null.mesh` is the format's own placeholder for "this block adds nothing", and every object
## in a terrain that has no second mesh names it. Drawing it puts a stray triangle at the origin
## of every prop on the map.
static func _drawable(meshes: PackedStringArray) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    for mesh: String in meshes:
        if mesh.to_lower() == "null.mesh" or mesh.is_empty():
            continue
        out.append(mesh)
    return out
