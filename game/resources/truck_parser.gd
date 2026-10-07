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
## Per-node friction multiplier, from the `setnode_defaults` in force. The hero truck asks
## for 0.65 on its bodywork and 1.06 on its tread, which is how a rig grips with its tyres
## and slides on its panels.
var node_friction: PackedFloat32Array = PackedFloat32Array()
## Nodes carrying the `l` option with no figure after it: they share the rig's cargo mass
## between them, so the share cannot be known until the file has been read.
var cargo_share_nodes: PackedInt32Array = PackedInt32Array()
## The index the generated wheel tread begins at: every node from here on is a tyre node,
## and tyre nodes are exempt from the rig's mass distribution and its minimass floor.
var generated_from: int = -1
## The beams, their rates and their limits. See `BeamTable`; these read through to it so that
## every caller can still ask a parsed truck for `beams` and `beam_spring` directly.
var beam_table: BeamTable = BeamTable.new()
var beams: PackedInt32Array:
    get: return beam_table.beams
var beam_spring: PackedFloat32Array:
    get: return beam_table.spring
var beam_damp: PackedFloat32Array:
    get: return beam_table.damp
var beam_deform: PackedFloat32Array:
    get: return beam_table.deform
var beam_strength: PackedFloat32Array:
    get: return beam_table.strength
var beam_plastic: PackedFloat32Array:
    get: return beam_table.plastic
## The body panels, kept per `submesh` group so each can be drawn with its own coordinates.
var submeshes: SubmeshRows = SubmeshRows.new()
## The material the `globals` line names, which is what a submesh panel is drawn with.
var cab_material: String = ""
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
## One entry per `flares` row: the vehicle's lamps. See FlareRows.
var flares: Array[Dictionary] = []
## Which of the vehicle's own materials each lamp lights up: material name -> flare indices, from
## `materialflarebindings`. This is the lamp's glass rather than the glow in front of it — see
## `FlareRows.binding`.
var material_flares: Dictionary = {}
var bounded_beams: Array[Dictionary]:
    get: return beam_table.bounded
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
## Every `ties` row: a rope anchored at one node whose other end is loose until a player hooks
## it onto something. Nothing acts on them yet; they are kept so that the rows are read rather
## than mistaken for beams. See `BeamRows.tie`.
var ties: Array[Dictionary] = []
## Every `slidenodes` row: a node that runs along a rail instead of being pinned to one place.
## Eight vehicles here declare them and all eight are strut cars. See `SlideNodeRows`.
var slide_nodes: Array[Dictionary] = []
var sections_seen: Dictionary = {}
var sections_parsed: Dictionary = {}
var errors: PackedStringArray = PackedStringArray()

## Node reference table: every node's index under its own number, and a named node under its
## name as well. See `_register`.
var node_id_to_index: Dictionary = {}
var _cameras: CameraRows = CameraRows.new()
var node_defaults: NodeRows.Defaults = NodeRows.Defaults.new()
## The structural rates in force where the file last set them. Public because a generated
## flexbody wheel builds its tread at these rather than at the tyre's — tread is carcass.
var beam_defaults: BeamDefaults = BeamDefaults.new()
var _section: String = ""


func parse_file(path: String) -> String:
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        return "cannot open '%s': %s" % [path, error_string(FileAccess.get_open_error())]
    var text: String = file.get_as_text()
    file.close()
    return parse_text(text)


## Reads a vehicle file in two passes: the file is cut into rows where it stands, and the rows
## are then walked in the order upstream spawns them.
##
## **The second pass is not a tidiness.** `cinecam` and the wheel sections append nodes, a
## numeric node reference is an index into that array, and upstream numbers those generated
## nodes by its own keyword order rather than by the file's layout — see `TruckDocument`. Walked
## in file order instead, 30 of this checkout's 70 actors reference a wheel node from a `props`
## or `flexbodies` row written above the wheel section, and every one of those rows was dropped.
func parse_text(text: String) -> String:
    var document: TruckDocument = TruckDocument.new()
    document.read(text)
    name = document.name
    var generated: bool = false
    var wheels_end: int = document.order_of(TruckDocument.LAST_NODE_GENERATOR)
    for row: Dictionary in document.in_spawn_order():
        # Every section ordered after the last wheel section may name a node the wheels
        # generated, so the tread has to exist before the first of them is read.
        if not generated and int(row["order"]) > wheels_end:
            _generate_wheels()
            generated = true
        _section = row["section"] as String
        if bool(row["header"]):
            _open_section()
            continue
        beam_defaults = row["beams"] as BeamDefaults
        node_defaults = row["nodes"] as NodeRows.Defaults
        _parse_row(row["line"] as String)
    if not generated:
        _generate_wheels()
    if nodes.is_empty():
        return "no nodes found; is '%s' a vehicle file?" % name
    _resolve_deferred()
    return ""


## A wheel states axle nodes and a radius; the tread it stands on follows from those.
func _generate_wheels() -> void:
    generated_from = nodes.size()
    WheelRig.generate(self)


## Sections that name nodes may appear before the nodes section itself, so their
## references are resolved once the whole file has been read.
func _resolve_deferred() -> void:
    cinecams = _cameras.positions
    if not cinecams.is_empty():
        cinecam_position = cinecams[0]
        has_cinecam = true
    var resolved: Dictionary = _cameras.resolve(node_id_to_index)
    if (resolved["error"] as String) != "":
        errors.append(resolved["error"] as String)
        return
    camera_nodes = resolved["nodes"] as Dictionary


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


## What opening a section does, for the two that are bookkeeping rather than data. Which lines
## count as headers, directives or data is `TruckLexer`'s job and cutting the file into them is
## `TruckDocument`'s; what to do about one is this parser's.
func _open_section() -> void:
    if _section == "submesh":
        submesh_count += 1
        submeshes.begin()
    elif _section == "backmesh":
        submeshes.backmesh()


func _parse_row(line: String) -> void:
    sections_seen[_section] = int(sections_seen.get(_section, 0)) + 1
    match _section:
        "nodes", "nodes2":
            _parse_node(line)
        "beams":
            _parse_beam(line)
        "texcoords":
            _note("texcoord", submeshes.read_texcoord(
                TruckLexer.fields(line), node_id_to_index
            ), line)
        "cab":
            _note("cab", submeshes.read_cab(
                TruckLexer.fields(line), node_id_to_index
            ), line)
        "flexbodies":
            BodyRows.flexbody(line, node_id_to_index, flexbodies, errors)
        "props":
            BodyRows.prop(line, node_id_to_index, props, errors)
        # `globals` is dry mass, cargo mass and the material the body panels are drawn with.
        "globals":
            var fields: PackedStringArray = TruckLexer.fields(line)
            if fields.size() > 2:
                cab_material = fields[2]
        "managedmaterials":
            BodyRows.managed_material(line, managed_materials, errors)
        # Five sections, five field orders, and two of them generate twice as many nodes as the
        # other three. `WheelRows` holds the layouts; this only has to name the section, because
        # which section a row came from is part of reading it.
        "wheels", "wheels2", "meshwheels", "meshwheels2", "flexbodywheels":
            _note(_section, WheelRig.read_row(self, _section, line), line)
        "cameras":
            _cameras.read_cameras(TruckLexer.fields(line))
        "minimass":
            _parse_minimass(line)
        "cinecam":
            _parse_cinecam(line)
        "axles", "interaxles":
            has_axles = true
        "flares", "flares2":
            BodyRows.flare(line, node_id_to_index, flares, errors, _section)
        "materialflarebindings":
            _parse_material_flare(line)
        "ties":
            _parse_tie(line)
        "slidenodes":
            _note("slidenode", SlideNodeRows.read(self, line), line)
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
    var row: Dictionary = NodeRows.row(TruckLexer.fields(line), node_defaults)
    if (row["error"] as String) != "":
        errors.append("node %s: %s" % [row["error"], line])
        return
    if bool(row["loaded"]) and not bool(row["has_mass"]):
        cargo_share_nodes.append(nodes.size())
    _register(row["id"] as String)
    node_ids.append(row["id"] as String)
    nodes.append(row["position"] as Vector3)
    node_mass.append(row["mass"] as float if bool(row["has_mass"]) else -1.0)
    node_friction.append(row["friction"] as float)


## Gives a new node its place in the reference table.
##
## **A numbered node's number is thrown away and its order of appearance is kept.** That is
## upstream's `RegisterNode`: a numeric node reference is an index into the node array,
## bounds-checked and nothing more, and a declared number that disagrees with its position is
## reported as a duplicate and overridden. Keying on the declared number instead agrees on all
## 70 actors here — every one numbers from 0 with no gaps — and disagrees the moment a file does
## not. A named node keeps its name too, since that is the only way a file can reach it.
func _register(id: String) -> void:
    var index: int = nodes.size()
    if not id.is_valid_int():
        node_id_to_index[id] = index
    node_id_to_index[str(index)] = index


## Registers a node this project generated: a cinecam's own node, or a wheel's tread and rim.
##
## Generated nodes are referenced by number like any other — the Mazda's hubcaps name the first
## rim node of each wheel — so they go in the same table at the same index. `id` is only a label
## for a reader; nothing can reach a node by it.
func register_generated(id: String) -> void:
    node_id_to_index[str(nodes.size())] = nodes.size()
    node_ids.append(id)


func _parse_cinecam(line: String) -> void:
    var row: Dictionary = _cameras.read_cinecam(TruckLexer.fields(line))
    if (row["error"] as String) != "":
        errors.append("cinecam %s: %s" % [row["error"], line])
        return
    CinecamMount.build(self, row)


## `ties`: a rope with one end loose. See `BeamRows.tie` for why it is not a beam row.
func _parse_tie(line: String) -> void:
    var row: Dictionary = BeamRows.tie(TruckLexer.fields(line), node_id_to_index)
    if (row["error"] as String) != "":
        errors.append("tie %s: %s" % [row["error"], line])
        return
    row.erase("error")
    ties.append(row)


func _parse_beam(line: String) -> void:
    var row: Dictionary = BeamRows.plain(
        TruckLexer.fields(line), node_id_to_index, beam_defaults
    )
    if (row["error"] as String) != "":
        errors.append("beam %s: %s" % [row["error"], line])
        return
    beam_table.record(row)


## `materialflarebindings`: which material a given lamp lights up.
func _parse_material_flare(line: String) -> void:
    var row: Dictionary = FlareRows.binding(TruckLexer.fields(line))
    if (row["error"] as String) != "":
        errors.append("materialflarebinding %s: %s" % [row["error"], line])
        return
    var material: String = row["material"] as String
    var bound: PackedInt32Array = material_flares.get(material, PackedInt32Array())
    bound.append(row["flare"] as int)
    material_flares[material] = bound


func _parse_minimass(line: String) -> void:
    var fields: PackedStringArray = TruckLexer.fields(line)
    if fields.size() >= 1:
        minimass_kg = fields[0].to_float()


## Sections that declare a beam without being called `beams`.
func _parse_joint(line: String) -> void:
    if not BeamRows.handles(_section):
        return
    var fields: PackedStringArray = TruckLexer.fields(line)
    var row: Dictionary = BeamRows.joint(
        _section, fields, node_id_to_index, beam_defaults, _joint_length(fields)
    )
    if (row["error"] as String) != "":
        errors.append("%s %s: %s" % [_section, row["error"], line])
        return
    if _section == "hydros" and (row["factor"] as float) != 0.0:
        hydros.append({"beam": beams.size() / 2, "factor": row["factor"] as float})
    beam_table.record(row)


## The rest length of the beam a row declares, for the rows that state their travel in metres
## rather than as a fraction of it.
func _joint_length(fields: PackedStringArray) -> float:
    if fields.size() < 2:
        return 0.0
    var a: int = int(node_id_to_index.get(fields[0], -1))
    var b: int = int(node_id_to_index.get(fields[1], -1))
    if a < 0 or b < 0:
        return 0.0
    return nodes[a].distance_to(nodes[b])


## Records a row reader's error against the line it came from, or does nothing.
func _note(section: String, error: String, line: String) -> void:
    if error != "":
        errors.append("%s %s: %s" % [section, error, line])
