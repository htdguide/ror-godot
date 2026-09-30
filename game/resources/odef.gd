class_name Odef
extends RefCounted
## Reads a Rigs of Rods object definition: which meshes a named object is, and how big.
##
## The format is positional at the top — mesh filename, then a scale triple — and then a series
## of small blocks: `beginmesh`/`endmesh` adds another mesh to the same object, `beginbox`/
## `endbox` gives it a collision box, and a handful of one-word lines set flags.
##
## Only the geometry is read here. Collision boxes are reported so that a terrain's solid parts
## can be counted honestly and left for the work that will hand them to the solver; the flags
## are not read at all.


## Reads an .odef. Returns {"error", "meshes", "scale", "boxes"}.
static func read(path: String) -> Dictionary:
    var out: Dictionary = {
        "error": "",
        "meshes": PackedStringArray(),
        "scale": Vector3.ONE,
        "boxes": 0,
    }
    var text: String = RorText.read(path)
    if text.is_empty():
        out["error"] = "the object definition at %s could not be read" % path
        return out
    var meshes: PackedStringArray = PackedStringArray()
    var boxes: int = 0
    var seen: int = 0
    var in_mesh: bool = false
    for raw_line: String in text.split("\n"):
        var line: String = RorText.strip_comment(raw_line)
        if line.is_empty():
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
                    meshes.append(line.substr(line.find(" ") + 1).strip_edges())
                continue
        if seen == 0:
            meshes.append(line)
            seen += 1
            continue
        if seen == 1 and line.contains(","):
            out["scale"] = RorText.vector3(line)
            seen += 1
    out["meshes"] = _drawable(meshes)
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
