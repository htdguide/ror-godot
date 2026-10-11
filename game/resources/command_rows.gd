class_name CommandRows
extends RefCounted
## Reads what makes a `commands` or `commands2` row a ram rather than only a beam: its rates, the
## lengths it may travel between, the keys that drive it and how.
##
## The beam itself is `BeamRows`' business, and was all this project read: the hero's doors are
## four `commands2` rams that open on keys 1 to 4, and they were plain beams, so the doors never
## opened. Field order and option rules are upstream's `Parser::ParseCommandsUnified`:
##
##   commands:  n1, n2, rate,                  max_contraction, max_extension, key_contract,
##              key_extend, options, description, inertia x4, affect_engine, needs_engine, sound
##   commands2: n1, n2, shorten, lengthen,     (the same from max_contraction on)
##
## A row's lengths are fractions of the beam's own length; its rates are metres a second, scaled
## by the engine's crank factor when it draws on the engine (`affect_engine` > 0, the default).

const SECTIONS: PackedStringArray = ["commands", "commands2"]
## Upstream's `Inertia` before any `set_inertia_defaults`: no delay, no curves.
const NO_INERTIA: Dictionary = {"start_delay": 0.0, "stop_delay": 0.0, "start_function": "", "stop_function": ""}


## Appends the row's command to `out` when `section` is a command section. `beam` is the index
## the row's beam is about to take.
## A `hydros` row as the steering takes it: {beam, factor, inertia, inertia_defaults}. Upstream's
## `ParseHydros`: `n1, n2, factor, options, start_delay, stop_delay, start_function, stop_function`.
static func hydro(fields: PackedStringArray, beam: int, factor: float, defaults: Dictionary) -> Dictionary:
    var inertia: Dictionary = NO_INERTIA.duplicate()
    var keys: Array[String] = ["start_delay", "stop_delay", "start_function", "stop_function"]
    for i: int in 4:
        if fields.size() > 4 + i:
            inertia[keys[i]] = fields[4 + i].to_float() if i < 2 else fields[4 + i]
    return {"beam": beam, "factor": factor, "inertia": inertia, "inertia_defaults": defaults}


## `defaults` is the `set_inertia_defaults` in force, as `inertia_defaults` reads it.
static func collect(section: String, fields: PackedStringArray, beam: int, out: Array[Dictionary],
        defaults: Dictionary = NO_INERTIA) -> void:
    if not SECTIONS.has(section):
        return
    var two: bool = section == "commands2"
    var minimum: int = 8 if two else 7
    if fields.size() < minimum:
        return
    var at: int = 2
    var shorten: float = fields[at].to_float()
    at += 1
    var lengthen: float = shorten
    if two:
        lengthen = fields[at].to_float()
        at += 1
    var row: Dictionary = {
        "beam": beam,
        "shorten_rate": shorten,
        "lengthen_rate": lengthen,
        "max_contraction": fields[at].to_float(),
        "max_extension": fields[at + 1].to_float(),
        "contract_key": fields[at + 2].to_int(),
        "extend_key": fields[at + 3].to_int(),
        "invisible": false, "rope": false, "not_faster": false,
        "auto_center": false, "one_press": false, "one_press_center": false,
        "description": "",
        "affect_engine": 1.0,
        "needs_engine": true,
        "inertia": NO_INERTIA.duplicate(),
        "inertia_defaults": defaults,
    }
    at += 4
    if fields.size() > at:
        _options(fields[at], row)
        at += 1
    if fields.size() > at:
        row["description"] = fields[at]
        at += 1
    # Upstream's `ParseOptionalInertia`: start and stop delay factors, then start and stop curves.
    var inertia: Dictionary = row["inertia"] as Dictionary
    var keys: Array[String] = ["start_delay", "stop_delay", "start_function", "stop_function"]
    for i: int in 4:
        if fields.size() > at + i:
            inertia[keys[i]] = fields[at + i].to_float() if i < 2 else fields[at + i]
    at += 4
    if fields.size() > at:
        row["affect_engine"] = fields[at].to_float()
        at += 1
    if fields.size() > at:
        row["needs_engine"] = _truth(fields[at])
    out.append(row)


## The option letters, with upstream's rule that only one of `c`, `p`, `o` wins: the first named.
static func _options(letters: String, row: Dictionary) -> void:
    var winner: String = ""
    for letter: String in letters:
        if winner == "" and letter in ["o", "p", "c"]:
            winner = letter
        match letter:
            "i": row["invisible"] = true
            "r": row["rope"] = true
            "f": row["not_faster"] = true
            "c": row["auto_center"] = true
            "p": row["one_press"] = true
            "o": row["one_press_center"] = true
    if bool(row["auto_center"]) and winner != "c" and winner != "":
        row["auto_center"] = false
    if bool(row["one_press_center"]) and winner != "o" and winner != "":
        row["one_press_center"] = false
    elif bool(row["one_press"]) and winner != "p" and winner != "":
        row["one_press"] = false


## Upstream's `GetArgBool`, which is Ogre's `parseBool`: true when the field starts with "true",
## "yes", "1" or "on", case aside, and false otherwise.
static func _truth(field: String) -> bool:
    var value: String = field.strip_edges().to_lower()
    for prefix: String in ["true", "yes", "1", "on"]:
        if value.begins_with(prefix):
            return true
    return false


## Upstream's `ParseDirectiveSetInertiaDefaults`: `start, stop, start_function, stop_function`, the
## curves kept from the defaults before when not given; a negative delay restores no inertia.
static func inertia_defaults(arguments: PackedStringArray, before: Dictionary) -> Dictionary:
    if arguments.is_empty():
        return before
    var start: float = arguments[0].to_float()
    var stop: float = arguments[1].to_float() if arguments.size() > 1 else 0.0
    if start < 0.0 or stop < 0.0:
        return NO_INERTIA
    var out: Dictionary = before.duplicate()
    out["start_delay"] = start
    out["stop_delay"] = stop
    if arguments.size() > 2:
        out["start_function"] = arguments[2]
    if arguments.size() > 3:
        out["stop_function"] = arguments[3]
    return out


## Upstream's `ActorSpawner::_ProcessKeyInertia`: the row's own inertia when both its delays are
## set, else the defaults when either of theirs is positive, else nothing. "/" and "-" are a row's
## placeholders for no curve. Returns [start_delay, stop_delay, start_function, stop_function], or
## an empty array for leaving the key as it is.
static func key_inertia(row: Dictionary) -> Array:
    var own: Dictionary = row["inertia"] as Dictionary
    var defaults: Dictionary = row["inertia_defaults"] as Dictionary
    if float(own["start_delay"]) != 0.0 and float(own["stop_delay"]) != 0.0:
        return [own["start_delay"], own["stop_delay"], _curve(own["start_function"]), _curve(own["stop_function"])]
    if float(defaults["start_delay"]) > 0.0 or float(defaults["stop_delay"]) > 0.0:
        return [defaults["start_delay"], defaults["stop_delay"], defaults["start_function"], defaults["stop_function"]]
    return []


static func _curve(name: Variant) -> String:
    var text: String = str(name)
    return "" if text == "/" or text == "-" else text
