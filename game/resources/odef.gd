class_name Odef
extends RefCounted
## Reads a Rigs of Rods object definition: which meshes a named object is, and how big.
##
## The format is positional at the top — an optional obsolete `LOD` line, a mesh filename, then a
## scale triple — and then a series of small blocks: `beginbox`/`endbox` gives the object a
## collision box, `beginmesh`/`endmesh` gives it a collision **mesh**, and a handful of one-word
## lines set flags.
##
## **`beginlodmesh` is the author's own distance geometry.** A block of `<distance>, <mesh>`
## lines says which mesh to draw from how far away, and Starling Island ships twelve of them
## across ten objects — its firehouse, police department, hospital, stores, office block, bus
## stop and road sign. Upstream's current parser ignores the block entirely, so nobody has drawn
## them for years; they are the cheapest distance geometry available to this project because the
## terrain's author already made it.
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
## **`beginbox` is the collision the author wrote down.** Its `boxcoords` line is six numbers —
## `minx, maxx, miny, maxy, minz, maxz` — in a Y-up frame, unlike the mesh, which is Z-up and gets
## pitched -90 degrees when it is placed. `road-slab.odef` is `boxcoords -5.01, 5.01, -3, 0.3,
## -5.01, 5.01`: a 10 m slab, 3.3 m thick, its top 0.3 m above the object's origin. That is the
## surface a truck drives on, and counting those boxes without building them is why a visible road
## had nothing under it. Port Starling places 189 of them and 139 `road-park`.
##
## A box marked `virtual` is an event zone and not solid — upstream gates every solid response on
## `!cbox->virt` — so it is read and marked rather than dropped.
##
## The flags beyond that are not read: `event`, `forcecamera`, `direction`, `stdfriction`.


## Reads an .odef. Returns {"error", "meshes", "collision_meshes", "lods", "scale", "boxes"},
## where a box is {"min", "max", "rotation", "virtual"} in the object's own Y-up frame and a lod
## is {"distance", "mesh"}.
static func read(path: String) -> Dictionary:
    var out: Dictionary = {
        "error": "",
        "meshes": PackedStringArray(),
        "collision_meshes": PackedStringArray(),
        "lods": [] as Array[Dictionary],
        "scale": Vector3.ONE,
        "boxes": [] as Array[Dictionary],
    }
    var text: String = RorText.read(path)
    if text.is_empty():
        out["error"] = "the object definition at %s could not be read" % path
        return out
    var meshes: PackedStringArray = PackedStringArray()
    var hulls: PackedStringArray = PackedStringArray()
    var lods: Array[Dictionary] = []
    var in_lod: bool = false
    var boxes: Array[Dictionary] = []
    var box: Dictionary = {}
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
        # `<distance>, <mesh>` inside a `beginlodmesh` block: the mesh to draw from that far
        # away. Taken before the keyword match because the line is data, not a keyword, and
        # before the positional header because it would otherwise be read as a scale.
        if in_lod and word != "endlodmesh":
            var fields: PackedStringArray = line.split(",")
            if fields.size() >= 2 and fields[0].strip_edges().is_valid_float():
                lods.append({
                    "distance": fields[0].strip_edges().to_float(),
                    "mesh": fields[1].strip_edges(),
                })
            continue
        match word:
            "beginmesh":
                in_mesh = true
                continue
            "endmesh":
                in_mesh = false
                continue
            "beginlodmesh":
                in_lod = true
                continue
            "endlodmesh":
                in_lod = false
                continue
            "beginbox":
                box = {
                    "min": Vector3.ZERO, "max": Vector3.ZERO,
                    "rotation": Vector3.ZERO, "virtual": false,
                }
                continue
            "endbox":
                if not box.is_empty():
                    boxes.append(box)
                box = {}
                continue
            "boxcoords":
                if not box.is_empty():
                    # minx, maxx, miny, maxy, minz, maxz — paired by axis, not by corner.
                    var n: PackedStringArray = (
                        line.substr(line.find(" ") + 1).replace(",", " ").split(" ", false)
                    )
                    if n.size() >= 6:
                        box["min"] = Vector3(n[0].to_float(), n[2].to_float(), n[4].to_float())
                        box["max"] = Vector3(n[1].to_float(), n[3].to_float(), n[5].to_float())
                continue
            "rotate":
                if not box.is_empty():
                    box["rotation"] = RorText.vector3(line.substr(line.find(" ") + 1))
                continue
            "virtual":
                if not box.is_empty():
                    box["virtual"] = true
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
    lods.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return (a["distance"] as float) < (b["distance"] as float)
    )
    out["lods"] = lods
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
