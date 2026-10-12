class_name AnimatorRows
extends RefCounted
## Reads `animators` rows: upstream's `ParseAnimator`, then the flags and parameter its spawner
## makes of them (`ProcessAnimator`).
##
##   node1, node2, factor, option|option|...
##
## Upstream splits the row on commas only and the options on `|`. A numbered option (`throttle1`,
## `rpm1`, ...) is an aero engine's; `shortlimit:x` and `longlimit:x` bound the beam's travel.

## Upstream's `ANIM_FLAG_*` bits, by the option that sets each.
const FLAGS: Dictionary = {
    "airspeed": 1 << 0, "vvi": 1 << 1, "aoa": 1 << 3, "flap": 1 << 4, "airbrake": 1 << 5, "roll": 1 << 6,
    "pitch": 1 << 7, "accel": 1 << 10, "brakes": 1 << 11, "clutch": 1 << 12, "tacho": 1 << 13,
    "speedo": 1 << 14, "parking": 1 << 15, "turbo": 1 << 16, "torque": 1 << 21, "difflock": 1 << 23,
    "rudderboat": 1 << 28, "throttleboat": 1 << 29,
}
const SHIFTER: int = 1 << 17
const ALTIMETER: int = 1 << 2
## The aero options and their flag: throttle, rpm, aerotorq, aeropit, aerostatus.
const AERO: Dictionary = {"throttle": 1 << 8, "rpm": 1 << 9, "aerotorq": 1 << 18, "aeropit": 1 << 19, "aerostatus": 1 << 20}
## Options that set the parameter as well as a flag, in the order `ProcessAnimator` tests them:
## the last one present wins.
const PARAMETERS: Array = [
    ["shifterman1", SHIFTER, 1.0], ["shifterman2", SHIFTER, 2.0], ["sequential", SHIFTER, 3.0],
    ["shifterlin", SHIFTER, 4.0], ["altimeter100k", ALTIMETER, 1.0], ["altimeter10k", ALTIMETER, 2.0],
    ["altimeter1k", ALTIMETER, 3.0],
]


## {a, b, factor, flags, param, short_limit, long_limit} or {error}; a limit the row does not state
## is NAN.
static func read(line: String, id_to_index: Dictionary) -> Dictionary:
    var args: PackedStringArray = line.split(",")
    if args.size() < 4:
        return {"error": "row has %d fields, expected at least 4" % args.size()}
    var a: int = int(id_to_index.get(args[0].strip_edges(), -1))
    var b: int = int(id_to_index.get(args[1].strip_edges(), -1))
    if a < 0 or b < 0:
        return {"error": "row references an unknown node"}
    var tokens: PackedStringArray = PackedStringArray()
    var flags: int = 0
    var param: float = 0.0
    var short_limit: float = NAN
    var long_limit: float = NAN
    var aero_flags: int = 0
    var aero_index: int = 0
    var numbered: RegEx = RegEx.create_from_string("^\\s*(throttle|rpm|aerotorq|aeropit|aerostatus)([0-9])")
    for raw: String in args[3].split("|"):
        var token: String = raw.strip_edges()
        var m: RegExMatch = numbered.search(token)
        if m != null:
            aero_flags |= int(AERO[m.get_string(1)])
            aero_index = m.get_string(2).to_int() - 1
        elif token.begins_with("shortlimit") or token.begins_with("longlimit"):
            var fields: PackedStringArray = token.split(":")
            if fields.size() > 1:
                if token.begins_with("shortlimit"):
                    short_limit = fields[1].to_float()
                else:
                    long_limit = fields[1].to_float()
        else:
            tokens.append(token)
    for token: String in tokens:
        flags |= int(FLAGS.get(token, 0))
    for entry: Array in PARAMETERS:
        if tokens.has(entry[0]):
            flags |= int(entry[1])
            param = entry[2]
    # The aero options come last in the spawner, each setting the parameter to its engine.
    if aero_flags != 0:
        flags |= aero_flags
        param = float(aero_index)
    return {"a": a, "b": b, "factor": args[2].strip_edges().to_float(), "flags": flags, "param": param,
            "short_limit": short_limit, "long_limit": long_limit, "invisible": tokens.has("inv"), "error": ""}
