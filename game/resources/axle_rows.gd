class_name AxleRows
extends RefCounted
## Reads `axles`, `interaxles` and `transfercase` rows: which wheels share a differential, which
## kinds it can switch between, and which axles a transfer case drives.
##
## Upstream's `Parser::ParseAxles`, `ParseInterAxles` and `ParseTransferCase`. An axle names its two
## wheels by their axle nodes and lists differential types by letter, the first active:
##
##   axles:        w1(n1 n2), w2(n3 n4), d(sl)
##   interaxles:   axle_1, axle_2, d(l)            (axles numbered from 1, in file order)
##   transfercase: axle_1, axle_2, has_2wd, has_2wd_lo, ratios...   (axle_2 0 for none)
##
## The letters are `o` open, `l` locked, `s` split and `v` viscous; any other is dropped, as
## upstream drops it. An axle with none is open then locked, an interaxle locked.

const TYPES: String = "olsv"


## One row of `section` into `truck`'s lists; an error, or "".
static func read(section: String, line: String, truck: TruckParser) -> String:
    match section:
        "axles":
            truck.has_axles = true
            return axle(line.split(","), truck.node_id_to_index, truck.axles)
        "interaxles":
            return interaxle(line.split(","), truck.interaxles)
    return transfer_case(TruckLexer.fields(line), truck)


## Upstream keeps every row and spawns each in turn, so the last valid one is the one a vehicle
## drives with; the solver judges validity, so every row is kept. Its ratios start with 1, as
## upstream's parser starts them, and the row's own follow.
static func transfer_case(fields: PackedStringArray, truck: TruckParser) -> String:
    if fields.size() < 2:
        return "row names fewer than two axles"
    var ratios: PackedFloat32Array = PackedFloat32Array([1.0])
    for i: int in range(4, fields.size()):
        ratios.append(fields[i].to_float())
    truck.transfer_cases.append({
        "a1": fields[0].to_int() - 1, "a2": fields[1].to_int() - 1,
        "has_2wd": fields[2].to_int() != 0 if fields.size() > 2 else true,
        "has_2wd_lo": fields[3].to_int() != 0 if fields.size() > 3 else false,
        "ratios": ratios,
    })
    return ""


## `fields` are the row split on commas only, as upstream splits it: a wheel's two nodes are
## separated by a space inside one field.
##
## Appends the axle `fields` names to `out` as {nodes: [w1a, w1b, w2a, w2b], types}.
static func axle(fields: PackedStringArray, id_to_index: Dictionary, out: Array[Dictionary]) -> String:
    var nodes: Array[int] = [-1, -1, -1, -1]
    var types: String = ""
    for field: String in fields:
        var text: String = field.strip_edges()
        if text.is_empty():
            continue
        if text.begins_with("w") and text.length() > 2 and text[2] == "(":
            var wheel: int = text.substr(1, 1).to_int() - 1
            if wheel < 0 or wheel > 1:
                return "row names wheel %s" % text.substr(1, 1)
            var inside: PackedStringArray = _inside(text).split(" ", false)
            if inside.size() != 2:
                return "wheel %d names %d nodes, not 2" % [wheel + 1, inside.size()]
            for i: int in 2:
                var node: int = int(id_to_index.get(inside[i], -1))
                if node < 0:
                    return "row references an unknown node %s" % inside[i]
                nodes[wheel * 2 + i] = node
        elif text.begins_with("d("):
            types = _types(_inside(text))
        else:
            # Upstream throws the whole line away on a property it does not recognise.
            return "invalid property %s" % text
    if nodes.has(-1):
        return "row does not name both wheels"
    out.append({"nodes": nodes, "types": types})
    return ""


## Appends the interaxle `fields` names to `out` as {a, b, types}, axles counted from 0.
static func interaxle(fields: PackedStringArray, out: Array[Dictionary]) -> String:
    if fields.size() < 2:
        return "row names fewer than two axles"
    var types: String = ""
    if fields.size() > 2 and fields[2].strip_edges().begins_with("d("):
        types = _types(_inside(fields[2].strip_edges()))
    out.append({"a": fields[0].to_int() - 1, "b": fields[1].to_int() - 1, "types": types})
    return ""


static func _inside(text: String) -> String:
    var open: int = text.find("(")
    var close: int = text.rfind(")")
    if open < 0 or close <= open:
        return ""
    return text.substr(open + 1, close - open - 1).strip_edges()


static func _types(letters: String) -> String:
    var kept: String = ""
    for letter: String in letters:
        if TYPES.contains(letter):
            kept += letter
    return kept


## Switches every axle's differential, or every one between axles, to its next kind, the way
## upstream's toggle keys do, and says what each now is.
static func toggle(solver: RefCounted, between_axles: bool) -> String:
    var kinds: Dictionary = {"s": "split", "o": "open", "v": "viscous", "l": "locked"}
    var names: PackedStringArray = PackedStringArray()
    if between_axles:
        solver.toggle_axle_differentials()
        for i: int in solver.axle_differential_count():
            names.append(kinds.get(solver.axle_differential_type(i), "?"))
    else:
        solver.toggle_wheel_differentials()
        for i: int in solver.wheel_differential_count():
            names.append(kinds.get(solver.wheel_differential_type(i), "?"))
    return "%s differentials: %s" % ["interaxle" if between_axles else "axle",
            ", ".join(names) if not names.is_empty() else "none"]


## Upstream's transfer case keys, `toggleTransferCaseMode` or `toggleTransferCaseGearRatio`, and
## what it then says.
static func shift_transfer_case(solver: RefCounted, range_key: bool) -> String:
    if range_key:
        solver.toggle_transfer_case_ratio()
    else:
        solver.toggle_transfer_case_mode()
    return transfer_case_name(solver)


## Upstream's `getTransferCaseName`, as its console notice puts it.
static func transfer_case_name(solver: RefCounted) -> String:
    if not solver.has_transfer_case():
        return "No transfercase installed on current vehicle!"
    var ratio: float = solver.transfer_case_ratio()
    return "Transfercase switched to: %s %s" % ["4WD" if solver.transfer_case_four_wd() else "2WD",
            "Lo (%s:1)" % String.num(ratio, 5) if ratio > 1.0 else "Hi"]
