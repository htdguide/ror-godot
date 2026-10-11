class_name AxleRows
extends RefCounted
## Reads `axles` and `interaxles` rows: which wheels share a differential, and which kinds it can
## switch between.
##
## Upstream's `Parser::ParseAxles` and `ParseInterAxles`. An axle names its two wheels by their
## axle nodes and lists differential types by letter, the first active:
##
##   axles:      w1(n1 n2), w2(n3 n4), d(sl)
##   interaxles: axle_1, axle_2, d(l)            (axles numbered from 1, in file order)
##
## The letters are `o` open, `l` locked, `s` split and `v` viscous; any other is dropped, as
## upstream drops it. An axle with none is open then locked, an interaxle locked.

const TYPES: String = "olsv"


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
