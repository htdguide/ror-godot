class_name NodeRows
extends RefCounted
## Parses a `nodes` row, including the part of it that decides what the rig weighs.
##
## A node row is "id, x, y, z, options, loadweight". The first four fields are the ones a
## renderer needs; the last two are the ones a solver needs, and reading only the
## position is why every node on a rig can end up weighing the same.
##
## The hero truck states a weight for all 250 of its nodes — `l 18` under the frame rails,
## `l 2.3` over the panels, `l 14` at the engine — which adds up to 1.2 tonnes before its
## wheels are counted. Read as position only, every one of those nodes weighs the minimass
## floor of 3.2 kg instead, and a vehicle that should be nose-heavy is uniformly light.

## Upstream's NODE_LOADWEIGHT_DEFAULT: the weight a node carrying the `l` option but no
## stated figure takes a share of, from the rig's cargo mass.
const LOAD_WEIGHT_DEFAULT: float = 10.0
## Upstream's NODE_FRICTION_COEF_DEFAULT.
const FRICTION_DEFAULT: float = 1.0

## The `set_node_defaults` state in force. Upstream carries one of these through the file
## and merges it into every node declared after it, which is how a rig gives its tread
## nodes more grip than its bodywork without saying so on each row.
class Defaults:
    extends RefCounted
    ## Negative means "not stated": the node's mass comes from the rig's mass
    ## distribution rather than from the directive.
    var load_weight: float = -1.0
    var friction: float = FRICTION_DEFAULT

    func duplicate_defaults() -> Defaults:
        var copy: Defaults = Defaults.new()
        copy.load_weight = load_weight
        copy.friction = friction
        return copy


## "set_node_defaults loadweight, friction, volume, surface, options". A negative value
## means "keep the default"; only the two fields that change the simulation are read.
static func parse_defaults(fields: PackedStringArray, current: Defaults) -> Defaults:
    var out: Defaults = current.duplicate_defaults()
    if fields.size() >= 1:
        out.load_weight = fields[0].to_float()
    if fields.size() >= 2 and fields[1].to_float() >= 0.0:
        out.friction = fields[1].to_float()
    return out


## Returns {"error", "id", "position", "friction", "mass", "has_mass", "loaded"}.
## `has_mass` is true when the row or the defaults in force state a weight outright, in
## which case `mass` is that weight and the rig's mass distribution leaves the node alone.
static func row(fields: PackedStringArray, defaults: Defaults) -> Dictionary:
    if fields.size() < 4:
        return {"error": "row has %d fields, expected at least 4" % fields.size()}
    var out: Dictionary = {
        "error": "",
        "id": fields[0],
        "position": Vector3(fields[1].to_float(), fields[2].to_float(), fields[3].to_float()),
        "friction": defaults.friction,
        "mass": defaults.load_weight,
        "has_mass": defaults.load_weight >= 0.0,
        "loaded": defaults.load_weight >= 0.0,
    }
    if fields.size() < 5:
        return out
    var options: String = _letters_of(fields[4])
    if not options.contains("l"):
        return out
    out["loaded"] = true
    # An `l` with a figure after it is an outright weight in kilograms. An `l` on its own
    # asks for a share of the rig's cargo mass instead, which is spread over every node
    # that asked, so it cannot be resolved until the whole file has been read.
    var weight: String = _digits_of(fields[4])
    if weight.is_empty() and fields.size() >= 6:
        weight = fields[5]
    if weight.is_valid_float():
        out["mass"] = weight.to_float()
        out["has_mass"] = true
    return out


static func _letters_of(field: String) -> String:
    var out: String = ""
    for i: int in field.length():
        if not field[i].is_valid_int():
            out += field[i]
    return out


static func _digits_of(field: String) -> String:
    var out: String = ""
    for i: int in field.length():
        var character: String = field[i]
        if character.is_valid_int() or character == "." or character == "-":
            out += character
    return out
