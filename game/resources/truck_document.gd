class_name TruckDocument
extends RefCounted
## A vehicle file cut into rows, each one carrying the section it belongs to and the defaults in
## force where it was written, ready to be walked in the order upstream spawns in.
##
## **The file's order is not the spawn order, and node numbers depend on the spawn order.**
## Upstream reads a file into a document and then processes it keyword by keyword in one fixed
## sequence (`ActorSpawnerFlow.cpp`): declared nodes first, then `cinecam`, then the five wheel
## sections, and only then everything that references a node. Each of those generating sections
## appends nodes, and a numeric node reference is an *index* into that array — `RegisterNode`
## throws a declared number away and keeps the order of appearance. So what number a tyre's
## nodes have is decided by the keyword order and not by where the author wrote the section.
##
## **It is not a rare layout.** Of the 70 actors in this checkout, 30 write `props` or
## `flexbodies` above the wheel section whose nodes those rows name. Read in file order they
## reference nodes that do not exist yet: the Mazda lost its brake discs and all four hubcaps,
## and every Gavril lost all four tyres, which are flexbodies bound to the wheel nodes.
##
## **Defaults follow the file even though spawning does not.** `set_beam_defaults` applies to the
## rows below it where it is written, so a row's rates have to be captured as the row is read
## rather than looked up when it is spawned — upstream gives every parsed row a pointer to the
## defaults in force. Here the defaults object is replaced rather than mutated when a directive
## arrives, so a row keeps exactly what stood above it.

## Upstream's spawn order, section by section, from `ActorSpawnerFlow.cpp`. Sections upstream
## auto-imports into another sit with their target: `flares` with `flares2`, `commands` with
## `commands2`, `nodes2` with `nodes`. `texcoords`, `cab` and `backmesh` belong to `submesh` and
## share its place, which keeps a file's several submeshes in the order they were written.
##
## A section absent from this list keeps its place at the end, in file order. Nothing in it is
## read yet, so where it sits cannot matter; when something does read it, it belongs here.
const SPAWN_ORDER: PackedStringArray = [
    "minimass", "managedmaterials", "globals", "help",
    "nodes",
    "engine", "turbojets", "pistonprops", "turboprops2", "screwprops",
    "engoption", "engturbo", "torquecurve", "brakes", "guisettings",
    "cinecam",
    "wheels", "wheels2", "meshwheels", "meshwheels2", "flexbodywheels",
    "wheeldetachers",
    "beams", "shocks", "shocks2", "shocks3", "commands2", "hydros", "triggers",
    "ropes", "antilockbrakes", "flares2", "flares3", "materialflarebindings",
    "axles", "transfercase", "interaxles",
    "submesh",
    "contacters", "cameras", "hooks", "ties", "ropables", "animators", "fusedrag", "props",
    "tractioncontrol", "rotators", "rotators2", "lockgroups", "railgroups", "slidenodes",
    "particles", "cruisecontrol", "speedlimiter", "collisionboxes", "exhausts", "camerarail",
    "fixes", "flexbodies", "wings", "airbrakes", "soundsources", "soundsources2",
]
## Sections upstream has no step of its own for, because it folds them into another: a
## `texcoords` or `cab` row belongs to the `submesh` above it, and `flares` and `commands` are
## auto-imported into their numbered successors.
##
## **They have to share one place, not sit next to each other.** Given places of their own, every
## `submesh` header sorted ahead of every `texcoords` row, so 29 groups were opened and then all
## 210 coordinates and 154 triangles landed in the last of them: the Starling firetruck built one
## panel out of 29, and five more vehicles the same way. Sharing a place keeps a file's own
## interleaving, which is the whole of what a group is.
const SHARES_A_PLACE_WITH: Dictionary = {
    "nodes2": "nodes",
    "texcoords": "submesh",
    "cab": "submesh",
    "backmesh": "submesh",
    "flares": "flares2",
    "commands": "commands2",
    "turboprops": "turboprops2",
}

## The last section that appends nodes. Everything ordered after this may reference what the
## wheel sections generated, so the generated nodes have to exist by then.
const LAST_NODE_GENERATOR: String = "flexbodywheels"

## The vehicle's own name: the file's first content line, before any section header.
var name: String = ""
## Every content line, in file order: {"section", "line", "header", "order", "beams", "nodes"}.
## `header` marks the bare word that opened a section, which `submesh` and `backmesh` act on.
var rows: Array[Dictionary] = []

var _order: Dictionary = {}


func _init() -> void:
    for index: int in SPAWN_ORDER.size():
        _order[SPAWN_ORDER[index]] = index
    for folded: String in SHARES_A_PLACE_WITH:
        _order[folded] = _order[SHARES_A_PLACE_WITH[folded] as String]


## Cuts `text` into rows. The reading itself cannot fail: a line this does not understand is
## still recorded under whatever section was open, and it is the sections' own readers that
## say what they could not use.
func read(text: String) -> void:
    var section: String = ""
    var beams: BeamDefaults = BeamDefaults.new()
    # `enable_advanced_deformation` works forwards from where it stands, which upstream records as
    # an artefact of its own on-the-fly parser that it keeps on purpose. It lets a file mean a
    # yield stress below upstream's 400 kN floor — see `BeamDefaults.CREAK`.
    var advanced: bool = false
    var node_defaults: NodeRows.Defaults = NodeRows.Defaults.new()
    var started: bool = false
    for raw: String in text.split("\n"):
        var line: String = TruckLexer.strip(raw)
        if line.is_empty():
            continue
        if not started:
            name = line
            started = true
            continue
        # **Directives are tested before section headers, because some of them are a bare word.**
        # `enable_advanced_deformation` has no arguments, so a reader that asks "is this a lone
        # word?" first files it as a section and never acts on it. 56 of this checkout's 69
        # vehicles declare it, and it is what lets a file mean a yield stress below upstream's
        # 400 kN floor — swallowed, every one of them had its bodywork welded solid.
        var directive: String = TruckLexer.directive_of(line)
        if directive == "":
            if TruckLexer.is_section_header(line, section):
                section = line.to_lower()
                _append(section, line, true, beams, node_defaults)
                continue
            if TruckLexer.is_metadata(line):
                continue
        if directive != "":
            var arguments: PackedStringArray = TruckLexer.directive_fields(line, directive)
            # Replaced rather than mutated: the rows already recorded hold this object and
            # must keep the rates they were written under.
            if directive == "enable_advanced_deformation":
                advanced = true
            elif directive == "set_beam_defaults":
                beams = beams.copy()
                beams.set_advanced_deformation(advanced)
                beams.read_defaults(arguments)
            elif directive == "set_beam_defaults_scale":
                beams = beams.copy()
                beams.read_scale(arguments)
            elif directive == "set_node_defaults":
                node_defaults = NodeRows.parse_defaults(arguments, node_defaults)
            # Every other directive is recognised so that it is not mistaken for data. Acting
            # on them is a separate job; being silently parsed as geometry is the bug.
            continue
        _append(section, line, false, beams, node_defaults)


## The rows in the order upstream spawns them, with the file's order kept inside each section.
func in_spawn_order() -> Array[Dictionary]:
    var out: Array[Dictionary] = rows.duplicate()
    # A stable sort, so two rows of the same section — or of two sections that share a place,
    # as a submesh's `texcoords` and `cab` do — stay in the order the file wrote them.
    out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if int(a["order"]) != int(b["order"]):
            return int(a["order"]) < int(b["order"])
        return int(a["at"]) < int(b["at"])
    )
    return out


## Where a section sits in the spawn order. An unlisted section sorts after every listed one.
func order_of(section: String) -> int:
    return int(_order.get(section, SPAWN_ORDER.size()))


func _append(
    section: String, line: String, header: bool, beams: BeamDefaults,
    node_defaults: NodeRows.Defaults
) -> void:
    rows.append({
        "section": section,
        "line": line,
        "header": header,
        "order": order_of(section),
        "at": rows.size(),
        "beams": beams,
        "nodes": node_defaults,
    })
