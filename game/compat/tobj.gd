class_name Tobj
extends RefCounted
## Reads a Rigs of Rods terrain object file: where every prop on a terrain stands.
##
## A `.tobj` is mostly one line per object — six numbers and a name — with a few keyword lines
## mixed in for vegetation, procedural roads and hand-placed collision meshes. The keyword lines
## are kept as they are found rather than being interpreted here, so that a reader that does not
## yet draw grass still reports honestly that the terrain asks for it.
##
## The name on an object line is an object definition (`.odef`) rather than a mesh: one odef can
## place several meshes and a collision box, which is why a pole and its guy wires are one entry.

## Keyword lines this recognises. Everything else that is not six numbers and a name is reported
## as unread rather than dropped silently.
const VEGETATION: Array[String] = ["grass", "grass2"]


## Reads a .tobj. Returns {"error", "objects", "grass", "unread"}.
static func read(path: String) -> Dictionary:
    var out: Dictionary = {
        "error": "",
        "objects": [] as Array[Dictionary],
        "grass": [] as Array[Dictionary],
        "unread": PackedStringArray(),
    }
    var text: String = RorText.read(path)
    if text.is_empty():
        out["error"] = "the object file at %s could not be read" % path
        return out
    var objects: Array[Dictionary] = []
    var grass: Array[Dictionary] = []
    var unread: PackedStringArray = PackedStringArray()
    for raw_line: String in text.split("\n"):
        var line: String = RorText.strip_comment(raw_line)
        if line.is_empty():
            continue
        var keyword: String = line.get_slice(" ", 0).to_lower()
        if VEGETATION.has(keyword):
            grass.append(_grass(line))
            continue
        var fields: PackedStringArray = RorText.fields(line)
        if fields.size() < 7 or not fields[0].is_valid_float():
            unread.append(line)
            continue
        objects.append({
            "position": Vector3(
                fields[0].to_float(), fields[1].to_float(), fields[2].to_float()
            ),
            # Degrees about x, then y, then z, which is the order upstream builds the
            # rotation in.
            "rotation": Vector3(
                fields[3].to_float(), fields[4].to_float(), fields[5].to_float()
            ),
            "name": fields[6].strip_edges(),
        })
    out["objects"] = objects
    out["grass"] = grass
    out["unread"] = unread
    return out


## A vegetation line, kept whole. Its fields are a density map, a material and a dozen numbers
## for size and sway; nothing here draws it yet, and this is what says so.
static func _grass(line: String) -> Dictionary:
    var body: String = line.substr(line.find(" ") + 1)
    var fields: PackedStringArray = RorText.fields(body)
    return {
        "range_m": fields[0].to_float() if fields.size() > 0 else 0.0,
        "fields": fields,
        "line": line,
    }
