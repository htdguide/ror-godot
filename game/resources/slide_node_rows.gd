class_name SlideNodeRows
extends RefCounted
## The `slidenodes` section: a node held against a rail rather than to a point.
##
## **It is a suspension, not a curiosity.** A MacPherson strut is a hub that slides along a fixed
## travel, and a rig that writes one as beams alone cannot stop the hub rotating about them. Eight
## vehicles in this checkout declare `slidenodes` — the Mazda 626, the Spacewagon and all six
## Gavril Zetas — and every one of them is a strut car. Without it the Mazda's front hubs have
## nothing locating them and lean 37 degrees, which a window reported as a stance car.
##
## A row is a node, then the nodes of the rail it runs on, then options which are a letter and a
## number stuck together: `s` a spring rate, `b` a break force, `t` a tolerance, `r` an attachment
## rate, `d` an attachment distance, `c` a constraint, `g` a `railgroups` id. Upstream's
## `ParseSlidenodes` takes any field starting with one of those letters for an option, and the rail
## node list ends at the first one — there is no separator. Excavators and dozers run their track
## rollers on a rail group: 1238 corpus rows name one, and none was read.
##
## The rail itself, a chain of the rig's own beams, is built by the solver (`ror_slidenode.cpp`).

## Upstream's `SlideNode` constructor defaults, for a row that states none of its own.
const DEFAULT_SPRING: float = 9000000.0
const DEFAULT_TOLERANCE_M: float = 0.0
## Upstream's default break force is infinite: a slide node does not come off its rail unless the
## file says what it takes.
const DEFAULT_BREAK_FORCE: float = INF


## Reads one row of `section` into `truck`, or returns why it could not be read.
static func read(truck: TruckParser, section: String, line: String) -> String:
    if section == "railgroups":
        return _rail_group(truck, TruckLexer.fields(line))
    var parsed: Dictionary = row(TruckLexer.fields(line), truck.node_id_to_index, truck.rail_groups)
    if (parsed["error"] as String) != "":
        return parsed["error"] as String
    parsed.erase("error")
    truck.slide_nodes.append(parsed)
    return ""


## Upstream's `ParseRailGroups`: an id and at least two nodes.
static func _rail_group(truck: TruckParser, fields: PackedStringArray) -> String:
    if fields.size() < 3:
        return "row has %d fields, expected at least 3" % fields.size()
    var nodes: PackedInt32Array = _nodes(fields.slice(1), truck.node_id_to_index)
    if nodes.size() < 2:
        return "row names %d known rail nodes, needs at least 2" % nodes.size()
    truck.rail_groups[fields[0].to_int()] = nodes
    return ""


## Node references in order up to the first unknown one, as upstream's `CollectNodesFromRanges`
## stops there and builds the rail from what it has.
static func _nodes(fields: PackedStringArray, id_to_index: Dictionary) -> PackedInt32Array:
    var out: PackedInt32Array = PackedInt32Array()
    for field: String in fields:
        var node: int = int(id_to_index.get(field, -1))
        if node < 0:
            break
        out.append(node)
    return out


## One row. Returns {"error", "node", "rail", "spring", "break_force", "tolerance"}.
static func row(fields: PackedStringArray, id_to_index: Dictionary, rail_groups: Dictionary = {}) -> Dictionary:
    if fields.size() < 2:
        return {"error": "row has %d fields, expected at least 2" % fields.size()}
    var node: int = int(id_to_index.get(fields[0], -1))
    if node < 0:
        return {"error": "row references an unknown node"}
    var rail: PackedInt32Array = PackedInt32Array()
    var out: Dictionary = {
        "error": "",
        "node": node,
        "spring": DEFAULT_SPRING,
        "break_force": DEFAULT_BREAK_FORCE,
        "tolerance": DEFAULT_TOLERANCE_M,
    }
    var listed: PackedStringArray = PackedStringArray()
    var in_rail: bool = true
    var group: int = -1
    var names_group: bool = false
    for at: int in range(1, fields.size()):
        var field: String = fields[at]
        var option: String = field.substr(0, 1).to_lower()
        if option.is_empty() or not "sbtrgdc".contains(option):
            if in_rail:
                listed.append(field)
            continue
        in_rail = false
        var value: float = field.substr(1).to_float()
        if option == "s":
            out["spring"] = absf(value)
        elif option == "b":
            out["break_force"] = absf(value)
        elif option == "t":
            out["tolerance"] = absf(value)
        elif option == "g":
            group = int(value)
            names_group = true
    if names_group:
        # Upstream's spawner takes the rail group over any listed nodes, and skips the slide node
        # when no group has that id.
        if not rail_groups.has(group):
            return {"error": "names rail group %d, which the file does not declare" % group}
        rail = rail_groups[group]
    else:
        rail = _nodes(listed, id_to_index)
    if rail.size() < 2:
        return {"error": "row names %d rail nodes, needs at least 2" % rail.size()}
    out["rail"] = rail
    return out

