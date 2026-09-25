class_name TruckParser
extends RefCounted
## Reads the Rigs of Rods vehicle format well enough to measure and render a real rig.
##
## Not the production parser: the plan keeps upstream's own RigDef parser, wrapped in the
## GDExtension, because fifteen years of tolerance for malformed files lives in it. This
## reads the structural sections so real vehicle data can be loaded, measured and
## rendered before the C++ side exists, and so the eventual C++ path has something to be
## checked against.
##
## Sections that are not understood are counted rather than skipped silently, so the
## parser can report how much of a file it actually accounted for.

const COMMENT_PREFIXES: Array[String] = [";", "//"]

var name: String = ""
var nodes: PackedVector3Array = PackedVector3Array()
var node_ids: PackedStringArray = PackedStringArray()
var beams: PackedInt32Array = PackedInt32Array()
var cab_triangles: PackedInt32Array = PackedInt32Array()
var texcoord_nodes: PackedInt32Array = PackedInt32Array()
var texcoords: PackedVector2Array = PackedVector2Array()
var submesh_count: int = 0
## One entry per flexbody: {ref, nx, ny, offset: Vector3, rot_deg: Vector3, mesh: String,
## forset: PackedInt32Array}. A flexbody binds an external OGRE mesh to a subset of the
## rig's nodes, which is the path ADR 0002 covers.
var flexbodies: Array[Dictionary] = []
## name -> {effect, textures: PackedStringArray}. The legacy material declaration, which
## carries more than it is usually credited with: an explicit transparency effect, and a
## specular map that is a real roughness source rather than a guess from diffuse luma.
var managed_materials: Dictionary = {}
## One entry per meshwheels2 wheel: {tire_radius, rim_radius, width, rays, node1, node2,
## side, mesh, material}. The rim is an external mesh posed by the axle nodes; the tyre is
## swept procedurally, which is why it needs the radii and ray count rather than a file.
var wheels: Array[Dictionary] = []
## Reference nodes for the actor's own frame: {centre, dir, roll}. Upstream uses these to
## place the camera; the bridge uses them to give the vehicle an orientation, which it
## otherwise does not have.
var camera_nodes: Dictionary = {}
var sections_seen: Dictionary = {}
var sections_parsed: Dictionary = {}
var errors: PackedStringArray = PackedStringArray()

var _node_id_to_index: Dictionary = {}
var _camera_ids: PackedStringArray = PackedStringArray()
var _section: String = ""


func parse_file(path: String) -> String:
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        return "cannot open '%s': %s" % [path, error_string(FileAccess.get_open_error())]
    var text: String = file.get_as_text()
    file.close()
    return parse_text(text)


func parse_text(text: String) -> String:
    var started: bool = false
    for raw: String in text.split("\n"):
        var line: String = _strip(raw)
        if line.is_empty():
            continue
        # The first content line is the vehicle name, before any section keyword.
        if not started:
            name = line
            started = true
            continue
        if _begin_section(line):
            continue
        _parse_row(line)
    if nodes.is_empty():
        return "no nodes found; is '%s' a vehicle file?" % name
    _resolve_deferred()
    return ""


## Sections that name nodes may appear before the nodes section itself, so their
## references are resolved once the whole file has been read.
func _resolve_deferred() -> void:
    if _camera_ids.size() < 3:
        return
    var centre: int = _node_index(_camera_ids[0])
    var dir: int = _node_index(_camera_ids[1])
    var roll: int = _node_index(_camera_ids[2])
    if centre < 0 or dir < 0 or roll < 0:
        errors.append("cameras references unknown node: %s" % ", ".join(_camera_ids))
        return
    camera_nodes = {"centre": centre, "dir": dir, "roll": roll}


## Share of content lines that landed in a section this parser understands.
func coverage() -> float:
    var parsed: int = 0
    var seen: int = 0
    for key: String in sections_seen.keys():
        seen += int(sections_seen[key])
        parsed += int(sections_parsed.get(key, 0))
    if seen == 0:
        return 0.0
    return float(parsed) / float(seen)


func bounds() -> AABB:
    if nodes.is_empty():
        return AABB()
    var box: AABB = AABB(nodes[0], Vector3.ZERO)
    for node: Vector3 in nodes:
        box = box.expand(node)
    return box


func _strip(raw: String) -> String:
    var line: String = raw.strip_edges()
    for prefix: String in COMMENT_PREFIXES:
        var at: int = line.find(prefix)
        if at == 0:
            return ""
        if at > 0:
            line = line.substr(0, at).strip_edges()
    return line


## A section keyword is a bare word on its own line; anything with separators is data.
func _begin_section(line: String) -> bool:
    if line.contains(",") or line.contains(" ") or line.contains("\t"):
        return false
    _section = line.to_lower()
    if _section == "submesh":
        submesh_count += 1
    return true


func _parse_row(line: String) -> void:
    sections_seen[_section] = int(sections_seen.get(_section, 0)) + 1
    match _section:
        "nodes", "nodes2":
            _parse_node(line)
        "beams":
            _parse_beam(line)
        "texcoords":
            _parse_texcoord(line)
        "cab":
            _parse_cab(line)
        "flexbodies":
            _parse_flexbody(line)
        "managedmaterials":
            _parse_managed_material(line)
        "meshwheels2", "meshwheels":
            _parse_mesh_wheel(line)
        "cameras":
            _parse_cameras(line)
        _:
            return
    sections_parsed[_section] = int(sections_parsed.get(_section, 0)) + 1


func _fields(line: String) -> PackedStringArray:
    var normalised: String = line.replace("\t", ",").replace(" ", ",")
    var out: PackedStringArray = PackedStringArray()
    for field: String in normalised.split(","):
        var trimmed: String = field.strip_edges()
        if not trimmed.is_empty():
            out.append(trimmed)
    return out


func _parse_node(line: String) -> void:
    var fields: PackedStringArray = _fields(line)
    if fields.size() < 4:
        errors.append("node row with %d fields: %s" % [fields.size(), line])
        return
    _node_id_to_index[fields[0]] = nodes.size()
    node_ids.append(fields[0])
    nodes.append(Vector3(fields[1].to_float(), fields[2].to_float(), fields[3].to_float()))


func _node_index(id: String) -> int:
    return int(_node_id_to_index.get(id, -1))


func _parse_beam(line: String) -> void:
    var fields: PackedStringArray = _fields(line)
    if fields.size() < 2:
        return
    var a: int = _node_index(fields[0])
    var b: int = _node_index(fields[1])
    if a < 0 or b < 0:
        errors.append("beam references unknown node: %s" % line)
        return
    beams.append(a)
    beams.append(b)


func _parse_texcoord(line: String) -> void:
    var fields: PackedStringArray = _fields(line)
    if fields.size() < 3:
        return
    var node: int = _node_index(fields[0])
    if node < 0:
        errors.append("texcoord references unknown node: %s" % line)
        return
    texcoord_nodes.append(node)
    texcoords.append(Vector2(fields[1].to_float(), fields[2].to_float()))


## Rows are "centre_node, direction_node, roll_node". Only the first is kept: it is the
## actor's main camera, and one frame per actor is what the bridge needs.
func _parse_cameras(line: String) -> void:
    if not _camera_ids.is_empty():
        return
    var fields: PackedStringArray = _fields(line)
    if fields.size() < 3:
        return
    # Resolution is deferred: a cameras section may appear before the nodes it names, as
    # it does in upstream's own DAF semi, and resolving eagerly rejects a valid file.
    _camera_ids = PackedStringArray([fields[0], fields[1], fields[2]])


## Rows are "tire_radius, rim_radius, width, rays, node1, node2, snode, braked, propulsed,
## arm, mass, spring, damping, side, meshname material".
func _parse_mesh_wheel(line: String) -> void:
    if line.begins_with("set_"):
        return  # Inline defaults directives, not wheel rows.
    var fields: PackedStringArray = _fields(line)
    if fields.size() < 16:
        errors.append("meshwheel row with %d fields: %s" % [fields.size(), line])
        return
    var node1: int = _node_index(fields[4])
    var node2: int = _node_index(fields[5])
    if node1 < 0 or node2 < 0:
        errors.append("meshwheel references unknown node: %s" % line)
        return
    wheels.append({
        "tire_radius": fields[0].to_float(),
        "rim_radius": fields[1].to_float(),
        "width": fields[2].to_float(),
        "rays": fields[3].to_int(),
        "node1": node1,
        "node2": node2,
        "side": fields[13].to_lower(),
        "mesh": fields[14],
        "material": fields[15],
    })


## Rows are "name effect texture...". A "-" stands for an absent texture.
func _parse_managed_material(line: String) -> void:
    var fields: PackedStringArray = _fields(line)
    if fields.size() < 3:
        errors.append("managedmaterial row with %d fields: %s" % [fields.size(), line])
        return
    var textures: PackedStringArray = PackedStringArray()
    for i: int in range(2, fields.size()):
        if fields[i] != "-":
            textures.append(fields[i])
    managed_materials[fields[0]] = {"effect": fields[1], "textures": textures}


## Rows are "ref,x,y, offsetx,offsety,offsetz, rotx,roty,rotz, mesh", each optionally
## followed by "forset <ranges>" lines naming the nodes the mesh may bind to.
func _parse_flexbody(line: String) -> void:
    if line.begins_with("forset"):
        if flexbodies.is_empty():
            errors.append("forset before any flexbody: %s" % line)
            return
        var last: Dictionary = flexbodies[flexbodies.size() - 1]
        last["forset"] = _parse_forset(line.substr("forset".length()))
        return
    var fields: PackedStringArray = _fields(line)
    if fields.size() < 10:
        errors.append("flexbody row with %d fields: %s" % [fields.size(), line])
        return
    var ref: int = _node_index(fields[0])
    var nx: int = _node_index(fields[1])
    var ny: int = _node_index(fields[2])
    if ref < 0 or nx < 0 or ny < 0:
        errors.append("flexbody references unknown node: %s" % line)
        return
    flexbodies.append({
        "ref": ref,
        "nx": nx,
        "ny": ny,
        "offset": Vector3(fields[3].to_float(), fields[4].to_float(), fields[5].to_float()),
        "rot_deg": Vector3(fields[6].to_float(), fields[7].to_float(), fields[8].to_float()),
        "mesh": fields[9],
        "forset": PackedInt32Array(),
    })


## "0-91", "0,5,7-9": ranges are inclusive and refer to node ids, not indices.
func _parse_forset(spec: String) -> PackedInt32Array:
    var out: PackedInt32Array = PackedInt32Array()
    for part: String in spec.replace(" ", ",").split(","):
        var token: String = part.strip_edges()
        if token.is_empty():
            continue
        var dash: int = token.find("-", 1)
        if dash > 0:
            var first: int = _node_index(token.substr(0, dash))
            var last: int = _node_index(token.substr(dash + 1))
            if first < 0 or last < 0:
                continue
            for i: int in range(first, last + 1):
                out.append(i)
        else:
            var single: int = _node_index(token)
            if single >= 0:
                out.append(single)
    return out


func _parse_cab(line: String) -> void:
    var fields: PackedStringArray = _fields(line)
    if fields.size() < 3:
        return
    for i: int in 3:
        var node: int = _node_index(fields[i])
        if node < 0:
            errors.append("cab references unknown node: %s" % line)
            return
        cab_triangles.append(node)
