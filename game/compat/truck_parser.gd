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

var name: String = ""
var nodes: PackedVector3Array = PackedVector3Array()
var node_ids: PackedStringArray = PackedStringArray()
## Per-node mass in kilograms as the file states it, or -1.0 where it states none. The
## hero truck states one for all 250 of its nodes, so reading these is the difference
## between a 1.6 tonne truck and one where every node weighs the minimass floor.
var node_mass: PackedFloat32Array = PackedFloat32Array()
## Per-node friction multiplier, from the `set_node_defaults` in force. The hero truck asks
## for 0.65 on its bodywork and 1.06 on its tread, which is how a rig grips with its tyres
## and slides on its panels.
var node_friction: PackedFloat32Array = PackedFloat32Array()
## Nodes carrying the `l` option with no figure after it: they share the rig's cargo mass
## between them, so the share cannot be known until the file has been read.
var cargo_share_nodes: PackedInt32Array = PackedInt32Array()
## The index the generated wheel tread begins at: every node from here on is a tyre node,
## and tyre nodes are exempt from the rig's mass distribution and its minimass floor.
var generated_from: int = -1
var beams: PackedInt32Array = PackedInt32Array()
## Per-beam spring and damping, as set by the set_beam_defaults directives in force where
## each beam was declared. Using one global default instead makes a real rig explode: the
## files are written against the values they declare.
var beam_spring: PackedFloat32Array = PackedFloat32Array()
var beam_damp: PackedFloat32Array = PackedFloat32Array()
var cab_triangles: PackedInt32Array = PackedInt32Array()
var texcoord_nodes: PackedInt32Array = PackedInt32Array()
var texcoords: PackedVector2Array = PackedVector2Array()
var submesh_count: int = 0
## One entry per flexbody: {ref, nx, ny, offset: Vector3, rot_deg: Vector3, mesh: String,
## forset: PackedInt32Array}. A flexbody binds an external OGRE mesh to a subset of the
## rig's nodes, which is the path ADR 0002 covers.
var flexbodies: Array[Dictionary] = []
## One entry per prop: the flexbody head plus, for a dashboard, its steering wheel. A prop
## is rigid — it rides its node triad rather than being skinned to a node set — and it is
## where a cab's dashboard, steering wheel and seatbelts live.
var props: Array[Dictionary] = []
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
## Minimum node mass in kilograms, from the minimass section. Upstream uses it as a floor
## when distributing a vehicle's mass over its nodes.
var minimass_kg: float = 0.0
## The engine, gearbox, clutch and brakes, as the file states them. See DriveRows.
var drivetrain: Dictionary = DriveRows.empty()
## One entry per `hydros` row: {beam: int, factor: float}. `beam` indexes `beams`, so the
## solver can find the beam a steering ram actuates without re-deriving it.
var hydros: Array[Dictionary] = []
## Whether the rig declares an `axles` section. Upstream doubles a rig's drive torque when
## it does, for backwards compatibility, so it changes how hard the rig pulls.
var has_axles: bool = false
## Driver's eye position from the cinecam section, in rig space. Empty when the vehicle
## declares none.
var cinecam_position: Vector3 = Vector3.ZERO
var has_cinecam: bool = false
## Every cinecam the vehicle declares, in file order. A rig commonly lists several
## switchable views and only some of them sit inside the cab: the hero truck's first
## entry is a raised centre view 0.22 m above its own roof, and its second is the
## driver's eye. Which one a caller wants depends on what it is for, so the choice is
## left to the caller rather than made here.
var cinecams: PackedVector3Array = PackedVector3Array()
var sections_seen: Dictionary = {}
var sections_parsed: Dictionary = {}
var errors: PackedStringArray = PackedStringArray()

var _node_id_to_index: Dictionary = {}
var _camera_ids: PackedStringArray = PackedStringArray()
var _node_defaults: NodeRows.Defaults = NodeRows.Defaults.new()
## Upstream's defaults from SimConstants, in force until a directive changes them.
var _beam_spring: float = 9000000.0
var _beam_damp: float = 12000.0
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
        var line: String = TruckLexer.strip(raw)
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
    # A wheel states axle nodes and a radius; the tread it stands on follows from those.
    generated_from = nodes.size()
    WheelRig.generate(self)
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


## Opens the section this line names. Which lines count as headers, directives or data is
## TruckLexer's job; what to do about them is this parser's.
func _begin_section(line: String) -> bool:
    if not TruckLexer.is_section_header(line, _section):
        return false
    _section = line.to_lower()
    if _section == "submesh":
        submesh_count += 1
    return true


func _parse_row(line: String) -> void:
    if TruckLexer.is_metadata(line):
        return
    var directive: String = TruckLexer.directive_of(line)
    if directive != "":
        var arguments: PackedStringArray = TruckLexer.directive_fields(line, directive)
        if directive == "set_beam_defaults":
            _parse_beam_defaults(arguments)
        elif directive == "set_node_defaults":
            _node_defaults = NodeRows.parse_defaults(arguments, _node_defaults)
        # Every other directive is recognised so that it is not mistaken for data. Acting
        # on them is a separate job; being silently parsed as geometry is the bug.
        return
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
        "props":
            _parse_prop(line)
        "managedmaterials":
            _parse_managed_material(line)
        "meshwheels2", "meshwheels":
            _parse_mesh_wheel(line)
        "cameras":
            _parse_cameras(line)
        "minimass":
            _parse_minimass(line)
        "cinecam":
            _parse_cinecam(line)
        "axles", "interaxles":
            has_axles = true
        _:
            if DriveRows.handles(_section):
                var error: String = DriveRows.read(_section, TruckLexer.fields(line), drivetrain)
                if error != "":
                    errors.append(error)
                    return
            elif BeamRows.handles(_section):
                _parse_joint(line)
            else:
                return
    sections_parsed[_section] = int(sections_parsed.get(_section, 0)) + 1


func _parse_node(line: String) -> void:
    var row: Dictionary = NodeRows.row(TruckLexer.fields(line), _node_defaults)
    if (row["error"] as String) != "":
        errors.append("node %s: %s" % [row["error"], line])
        return
    if bool(row["loaded"]) and not bool(row["has_mass"]):
        cargo_share_nodes.append(nodes.size())
    _node_id_to_index[row["id"] as String] = nodes.size()
    node_ids.append(row["id"] as String)
    nodes.append(row["position"] as Vector3)
    node_mass.append(row["mass"] as float if bool(row["has_mass"]) else -1.0)
    node_friction.append(row["friction"] as float)


func _node_index(id: String) -> int:
    return int(_node_id_to_index.get(id, -1))


func _parse_beam(line: String) -> void:
    var fields: PackedStringArray = TruckLexer.fields(line)
    if fields.size() < 2:
        return
    var a: int = _node_index(fields[0])
    var b: int = _node_index(fields[1])
    if a < 0 or b < 0:
        errors.append("beam references unknown node: %s" % line)
        return
    beams.append(a)
    beams.append(b)
    beam_spring.append(_beam_spring)
    beam_damp.append(_beam_damp)


## "set_beam_defaults spring, damp, ...". A negative value means "keep upstream's default".
func _parse_beam_defaults(fields: PackedStringArray) -> void:
    if fields.size() >= 1 and fields[0].to_float() >= 0.0:
        _beam_spring = fields[0].to_float()
    if fields.size() >= 2 and fields[1].to_float() >= 0.0:
        _beam_damp = fields[1].to_float()


func _parse_texcoord(line: String) -> void:
    var row: Dictionary = CabRows.texcoord(TruckLexer.fields(line), _node_id_to_index)
    if (row["error"] as String) != "":
        errors.append("texcoord %s: %s" % [row["error"], line])
        return
    texcoord_nodes.append(row["node"] as int)
    texcoords.append(row["uv"] as Vector2)


## "x, y, z, node1..node8, spring, damp" — only the position is needed here.
func _parse_cinecam(line: String) -> void:
    var fields: PackedStringArray = TruckLexer.fields(line)
    if fields.size() < 3:
        return
    var position: Vector3 = Vector3(
        fields[0].to_float(), fields[1].to_float(), fields[2].to_float()
    )
    cinecams.append(position)
    if has_cinecam:
        return
    cinecam_position = position
    has_cinecam = true


func _parse_minimass(line: String) -> void:
    var fields: PackedStringArray = TruckLexer.fields(line)
    if fields.size() >= 1:
        minimass_kg = fields[0].to_float()


## Rows are "centre_node, direction_node, roll_node". Only the first is kept: it is the
## actor's main camera, and one frame per actor is what the bridge needs.
func _parse_cameras(line: String) -> void:
    if not _camera_ids.is_empty():
        return
    var fields: PackedStringArray = TruckLexer.fields(line)
    if fields.size() < 3:
        return
    # Resolution is deferred: a cameras section may appear before the nodes it names, as
    # it does in upstream's own DAF semi, and resolving eagerly rejects a valid file.
    _camera_ids = PackedStringArray([fields[0], fields[1], fields[2]])


func _parse_mesh_wheel(line: String) -> void:
    if line.begins_with("set_"):
        return  # Inline defaults directives, not wheel rows.
    var row: Dictionary = WheelRig.parse_row(TruckLexer.fields(line), _node_id_to_index)
    if (row["error"] as String) != "":
        errors.append("meshwheel %s: %s" % [row["error"], line])
        return
    row.erase("error")
    # The tread this row implies is generated after the whole file is read, by which time
    # the directives in force here are long gone. The hero truck states
    # `set_node_defaults -1, 1.06` immediately above its front wheels and `-1, 1.12` above
    # its rear pair, and those two numbers are the grip its tyres have.
    row["friction"] = _node_defaults.friction
    wheels.append(row)


## Rows are "name effect texture...". A "-" stands for an absent texture.
func _parse_managed_material(line: String) -> void:
    var fields: PackedStringArray = TruckLexer.fields(line)
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
        last["forset"] = NodeIdRanges.resolve(
            line.substr("forset".length()), _node_id_to_index
        )
        return
    var row: Dictionary = PlacementRows.head(TruckLexer.fields(line), _node_id_to_index)
    if (row["error"] as String) != "":
        errors.append("flexbody %s: %s" % [row["error"], line])
        return
    row.erase("error")
    row["forset"] = PackedInt32Array()
    flexbodies.append(row)


func _parse_prop(line: String) -> void:
    var row: Dictionary = PlacementRows.prop(TruckLexer.fields(line), _node_id_to_index)
    if (row["error"] as String) != "":
        errors.append("prop %s: %s" % [row["error"], line])
        return
    row.erase("error")
    props.append(row)


## Sections that declare a beam without being called `beams`.
func _parse_joint(line: String) -> void:
    if not BeamRows.handles(_section):
        return
    var row: Dictionary = BeamRows.joint(
        _section, TruckLexer.fields(line), _node_id_to_index, _beam_spring, _beam_damp
    )
    if (row["error"] as String) != "":
        errors.append("%s %s: %s" % [_section, row["error"], line])
        return
    if _section == "hydros" and (row["factor"] as float) != 0.0:
        hydros.append({"beam": beams.size() / 2, "factor": row["factor"] as float})
    beams.append(row["a"] as int)
    beams.append(row["b"] as int)
    beam_spring.append(row["spring"] as float)
    beam_damp.append(row["damp"] as float)


func _parse_cab(line: String) -> void:
    var row: Dictionary = CabRows.triangle(TruckLexer.fields(line), _node_id_to_index)
    if (row["error"] as String) != "":
        errors.append("cab %s: %s" % [row["error"], line])
        return
    cab_triangles.append_array(row["nodes"] as PackedInt32Array)
