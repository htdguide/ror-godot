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


## Appends the row's command to `out` when `section` is a command section. `beam` is the index
## the row's beam is about to take.
static func collect(section: String, fields: PackedStringArray, beam: int, out: Array[Dictionary]) -> void:
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
    }
    at += 4
    if fields.size() > at:
        _options(fields[at], row)
        at += 1
    if fields.size() > at:
        row["description"] = fields[at]
        at += 1
    # Four inertia fields, which shape how a key's input ramps; not modelled, so a key acts at once.
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
