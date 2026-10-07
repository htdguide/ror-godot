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
## rate, `g` a railgroup id. The rail node list ends at the first option, which is how upstream
## tells the two apart — there is no separator.

## Upstream's `SlideNode` constructor defaults, for a row that states none of its own.
const DEFAULT_SPRING: float = 9000000.0
const DEFAULT_TOLERANCE_M: float = 0.0
## Upstream's default break force is infinite: a slide node does not come off its rail unless the
## file says what it takes.
const DEFAULT_BREAK_FORCE: float = INF


## Reads one row into `truck`, or returns why it could not be read.
static func read(truck: TruckParser, line: String) -> String:
    var parsed: Dictionary = row(TruckLexer.fields(line), truck.node_id_to_index)
    if (parsed["error"] as String) != "":
        return parsed["error"] as String
    parsed.erase("error")
    truck.slide_nodes.append(parsed)
    return ""


## One row. Returns {"error", "node", "rail", "spring", "break_force", "tolerance"}.
static func row(fields: PackedStringArray, id_to_index: Dictionary) -> Dictionary:
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
    var in_rail: bool = true
    for at: int in range(1, fields.size()):
        var field: String = fields[at]
        var option: String = field.substr(0, 1).to_lower()
        if in_rail and not _is_option(field):
            var on: int = int(id_to_index.get(field, -1))
            if on >= 0:
                rail.append(on)
            continue
        in_rail = false
        var value: float = field.substr(1).to_float()
        if option == "s":
            out["spring"] = absf(value)
        elif option == "b":
            out["break_force"] = absf(value)
        elif option == "t":
            out["tolerance"] = absf(value)
    if rail.size() < 2:
        return {"error": "row names %d rail nodes, needs at least 2" % rail.size()}
    out["rail"] = rail
    return out


## Whether a field is an option rather than a rail node. An option is a letter and a number with
## nothing between them; a node reference is a number, or a name that is not one of those letters
## followed by digits.
static func _is_option(field: String) -> bool:
    if field.length() < 2 or field.is_valid_float():
        return false
    return "sbtrgc".contains(field.substr(0, 1).to_lower()) and field.substr(1).is_valid_float()
