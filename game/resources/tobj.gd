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
## A terrain's forests. Read the same way and kept apart, because a tree is a mesh and a blade of
## grass is a card: Russia asks for two fir species and got neither for as long as `trees` was
## filed under "lines nothing reads".
const WOODLAND: String = "trees"
## An object line's seventh field is a name, and what follows it on the same line is a type and
## an instance name — upstream reads all three with one `sscanf`, `TObjFileFormat.cpp`:
##
##     sscanf(m_cur_line, "%f, %f, %f, %f, %f, %f, %s %s %s",
##         &pos.x, &pos.y, &pos.z, &rot.x, &rot.y, &rot.z,
##         odef.GetBuffer(), type.GetBuffer(), instance_name.GetBuffer());
##
## Taking the whole field as the name asked for an object definition called
## `marina sale Marina_Wells`, which no file is.
##
## Some of those names are not object definitions at all. Upstream sorts them before anything
## else is done with them — `IsActor()` and `IsRoad()` over the same list:
const ACTOR_NAMES: Array[String] = ["truck", "truck2", "load", "machine", "boat"]
const ROAD_NAMES: Array[String] = [
    "road", "roadborderleft", "roadborderright", "roadborderboth",
    "roadbridgenopillar", "roadbridge",
]
## And a block of road points, which are not object lines however much they look like them.
## Upstream reads one as ten fields — `TObjFileFormat.cpp`, `ProcessProceduralLine`:
##
##     sscanf(m_cur_line, "%f, %f, %f, %f, %f, %f, %f, %f, %f, %s",
##         &point.position.x, &point.position.y,  &point.position.z,
##         &rot.x, &rot.y, &rot.z,
##         &point.width, &point.bwidth, &point.bheight, obj_name.GetBuffer());
##
## so a line reading `1170, 256.3, 895, 0, 0, 0, 8, 1, 0.2, both` is an 8 m carriageway with a
## 1 m border 0.2 m high, kerbed on both sides. 374 of Port Starling's 1502 "objects" were points
## inside one of these, asking for object definitions named `0`, `8` and `10`.
## What a road point is when its line does not say — `ImportProceduralPoint`'s own figures.
const DEFAULT_WIDTH_M: float = 8.0
const DEFAULT_BORDER_WIDTH_M: float = 1.4
const DEFAULT_BORDER_HEIGHT_M: float = 0.2
const ROADS_BEGIN: String = "begin_procedural_roads"
const ROADS_END: String = "end_procedural_roads"


## Reads a .tobj. Returns {"error", "objects", "grass", "trees", "actors", "roads", "unread"}.
static func read(path: String) -> Dictionary:
    var out: Dictionary = {
        "error": "",
        "objects": [] as Array[Dictionary],
        "grass": [] as Array[Dictionary],
        "trees": [] as Array[Dictionary],
        "actors": [] as Array[Dictionary],
        "roads": [] as Array[Dictionary],
        "unread": PackedStringArray(),
    }
    var text: String = RorText.read(path)
    if text.is_empty():
        out["error"] = "the object file at %s could not be read" % path
        return out
    var objects: Array[Dictionary] = []
    var grass: Array[Dictionary] = []
    var trees: Array[Dictionary] = []
    var actors: Array[Dictionary] = []
    var roads: Array[Dictionary] = []
    var unread: PackedStringArray = PackedStringArray()
    var in_roads: bool = false
    var group: int = -1
    for raw_line: String in text.split("\n"):
        var line: String = RorText.strip_comment(raw_line)
        if line.is_empty():
            continue
        var keyword: String = line.get_slice(" ", 0).to_lower()
        if keyword == ROADS_BEGIN:
            in_roads = true
            group += 1
            continue
        if keyword == ROADS_END:
            in_roads = false
            continue
        if VEGETATION.has(keyword):
            grass.append(_grass(line))
            continue
        if keyword == WOODLAND:
            trees.append(_grass(line))
            continue
        var fields: PackedStringArray = RorText.fields(line)
        if fields.size() < 7 or not fields[0].is_valid_float():
            unread.append(line)
            continue
        var entry: Dictionary = {
            "position": Vector3(
                fields[0].to_float(), fields[1].to_float(), fields[2].to_float()
            ),
            # Degrees about x, then y, then z, which is the order upstream builds the
            # rotation in.
            "rotation": Vector3(
                fields[3].to_float(), fields[4].to_float(), fields[5].to_float()
            ),
            # The name alone. A type and an instance name may follow it on the same line.
            "name": fields[6].strip_edges().get_slice(" ", 0),
            "type": fields[6].strip_edges().get_slice(" ", 1),
        }
        var named: String = (entry["name"] as String).to_lower()
        if in_roads:
            roads.append(_road_point(fields, entry, group))
        elif ROAD_NAMES.has(named):
            # A road placed as an object becomes a point too, with upstream's own defaults —
            # `ImportProceduralPoint`: width 8, border 1.4 wide and 0.2 high.
            roads.append(_road_point(PackedStringArray(), entry, -1))
        elif ACTOR_NAMES.has(named):
            actors.append(entry)
        else:
            objects.append(entry)
    out["objects"] = objects
    out["actors"] = actors
    out["roads"] = roads
    out["grass"] = grass
    out["trees"] = trees
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


## One point of a procedural road: where it is, which way it runs, and the cross-section it
## carries there. `fields` are the ten the block form states; an empty set takes upstream's own
## defaults for a road placed as an object.
static func _road_point(
    fields: PackedStringArray, entry: Dictionary, group: int
) -> Dictionary:
    var out: Dictionary = {
        "position": entry["position"],
        "rotation": entry["rotation"],
        "width": DEFAULT_WIDTH_M,
        "bwidth": DEFAULT_BORDER_WIDTH_M,
        "bheight": DEFAULT_BORDER_HEIGHT_M,
        "kind": "automatic",
        "group": group,
    }
    if fields.size() >= 10:
        out["width"] = fields[6].to_float()
        out["bwidth"] = fields[7].to_float()
        out["bheight"] = fields[8].to_float()
        out["kind"] = fields[9].strip_edges().get_slice(" ", 0).to_lower()
    return out
