class_name BeamRows
extends RefCounted
## Parses the sections that declare a beam without calling it one: `shocks`, `hydros`,
## `commands2` and `ties`.
##
## Each names two nodes and adds a real structural link. Skipping them does not merely
## lose a feature — it leaves the rig missing members. On the hero truck the doors are
## held on entirely by four `commands2` rams and four `shocks` dampers, so with these
## sections unread a door has no beam to the body at all and swings a metre off its
## hinges the moment the vehicle settles.
##
## What is modelled here is the beam. A shock's travel bounds and a command's key-driven
## contraction are behaviours on top of that, and neither changes the fact that the two
## nodes are joined.
##
## A hydro's steering factor is different, and it is returned: it is the whole of what the
## section does. A hydro beam steers by changing its own rest length, so read as a plain
## beam it holds the steering rack rigid and the rig cannot turn at all.

## Section name -> the field index its spring and damping start at, or -1 when the row
## carries none and the beam defaults in force apply instead.
const SPRING_FIELD: Dictionary = {
    "shocks": 2,
    "shocks2": 2,
    "hydros": -1,
    "commands": -1,
    "commands2": -1,
    "ties": -1,
}
## The field holding the actuation factor, for the sections that have one. A hydro's is a
## signed fraction of its rest length per unit of steering input: the rams on opposite
## sides of a rack carry opposite signs so that one pushes while the other pulls.
const FACTOR_FIELD: Dictionary = {
    "hydros": 2,
}

## What a section's beams do outside their travel, matching the solver's BeamBound. A shock
## ramps towards the structural rates past either bound; a rope carries tension only; a
## support beam carries compression only.
const BOUND_NORMAL: int = 0
const BOUND_SHOCK: int = 1
const BOUND_ROPE: int = 2
const BOUND_SUPPORT: int = 3
const BOUND_TYPE: Dictionary = {
    "shocks": BOUND_SHOCK,
    "shocks2": BOUND_SHOCK,
    "ropes": BOUND_ROPE,
    "supportbeams": BOUND_SUPPORT,
}
## Where a shock row states its travel: "node1, node2, springin, dampin, shortbound,
## longbound, precomp, options". The bounds are fractions of the beam's own rest length,
## unless the row carries the `m` option, in which case they are metres.
const SHOCK_SHORT_BOUND_FIELD: int = 4
const SHOCK_PRECOMPRESSION_FIELD: int = 6
const SHOCK_OPTIONS_FIELD: int = 7


## Upstream's SUPPORT_BEAM_LIMIT_DEFAULT, for a support beam that states no break limit.
const SUPPORT_BREAK_LIMIT_DEFAULT: float = 4.0
## Where a plain `beams` row states its options and, for a support beam, its break limit.
const BEAM_OPTIONS_FIELD: int = 2
const BEAM_BREAK_LIMIT_FIELD: int = 3


## A row of the `beams` section: "node1, node2, options, extension_break_limit".
##
## The options are not decoration. `r` makes the beam a rope, which carries tension and cannot
## push; `s` makes it a support beam, which carries compression and cannot pull. Read as plain
## beams they become rigid struts in both directions, and a suspension located by limiter
## straps stops being a suspension: on the hero truck, two `ir` beams across the rear axle
## resisted 225 kN each and the axle travelled 6 mm.
static func plain(
    fields: PackedStringArray, id_to_index: Dictionary, defaults: BeamDefaults
) -> Dictionary:
    if fields.size() < 2:
        return {"error": "row has %d fields, expected at least 2" % fields.size()}
    var a: int = int(id_to_index.get(fields[0], -1))
    var b: int = int(id_to_index.get(fields[1], -1))
    if a < 0 or b < 0:
        return {"error": "row references an unknown node"}
    var options: String = (
        fields[BEAM_OPTIONS_FIELD] if fields.size() > BEAM_OPTIONS_FIELD else ""
    )
    var bound: int = BOUND_NORMAL
    var long_bound: float = 0.0
    if options.contains("r"):
        bound = BOUND_ROPE
    elif options.contains("s"):
        bound = BOUND_SUPPORT
        # A support beam breaks once stretched this many times its own length. Only the
        # bound is carried here; breaking is not modelled yet.
        long_bound = SUPPORT_BREAK_LIMIT_DEFAULT
        if fields.size() > BEAM_BREAK_LIMIT_FIELD:
            long_bound = maxf(fields[BEAM_BREAK_LIMIT_FIELD].to_float(), 0.0)
    return {
        "error": "",
        "a": a,
        "b": b,
        "spring": defaults.spring(),
        "damp": defaults.damp(),
        "factor": 0.0,
        "bound": bound,
        "short_bound": 0.0,
        "long_bound": long_bound,
        "bound_spring": defaults.spring_unscaled(),
        "bound_damp": defaults.damp_unscaled(),
        "precompression": 1.0,
    }


static func handles(section: String) -> bool:
    return SPRING_FIELD.has(section) or BOUND_TYPE.has(section)


## Returns {"error", "a", "b", "spring", "damp", "factor", "bound", "short_bound",
## "long_bound", "bound_spring", "bound_damp", "precompression"}.
##
## `factor` is zero for every section that does not actuate, and `bound` is BOUND_NORMAL for
## every section whose beams have no travel limit. `length_m` is the beam's rest length, which
## a shock row needs only when it states its bounds in metres.
static func joint(
    section: String,
    fields: PackedStringArray,
    id_to_index: Dictionary,
    defaults: BeamDefaults,
    length_m: float = 0.0
) -> Dictionary:
    if fields.size() < 2:
        return {"error": "row has %d fields, expected at least 2" % fields.size()}
    var a: int = int(id_to_index.get(fields[0], -1))
    var b: int = int(id_to_index.get(fields[1], -1))
    if a < 0 or b < 0:
        return {"error": "row references an unknown node"}
    var spring: float = defaults.spring()
    var damp: float = defaults.damp()
    var at: int = int(SPRING_FIELD.get(section, -1))
    if at >= 0 and fields.size() > at + 1:
        # A shock's stated rates are used as stated, soft ones included. The hero truck's
        # door dampers ask for a spring of 1 N/m and mean it: the doors hang on the
        # `commands2` rams beside them, and forcing the dampers up to the beam defaults
        # instead welds the suspension solid — measured travel falls from 154 mm to 2 mm.
        spring = maxf(fields[at].to_float(), 0.0)
        damp = maxf(fields[at + 1].to_float(), 0.0)
    var factor: float = 0.0
    var factor_at: int = int(FACTOR_FIELD.get(section, -1))
    if factor_at >= 0 and fields.size() > factor_at:
        factor = fields[factor_at].to_float()
    var row: Dictionary = {
        "error": "",
        "a": a,
        "b": b,
        "spring": spring,
        "damp": damp,
        "factor": factor,
        "bound": int(BOUND_TYPE.get(section, BOUND_NORMAL)),
        "short_bound": 0.0,
        "long_bound": 0.0,
        # A shock past its travel hands over to the structural rates as stated, unscaled.
        "bound_spring": defaults.spring_unscaled(),
        "bound_damp": defaults.damp_unscaled(),
        "precompression": 1.0,
    }
    if (row["bound"] as int) == BOUND_SHOCK:
        _read_shock_travel(fields, row, length_m)
    return row


## A shock's travel and pre-compression.
static func _read_shock_travel(
    fields: PackedStringArray, row: Dictionary, length_m: float
) -> void:
    if fields.size() <= SHOCK_SHORT_BOUND_FIELD + 1:
        return
    var short_bound: float = fields[SHOCK_SHORT_BOUND_FIELD].to_float()
    var long_bound: float = fields[SHOCK_SHORT_BOUND_FIELD + 1].to_float()
    var options: String = (
        fields[SHOCK_OPTIONS_FIELD] if fields.size() > SHOCK_OPTIONS_FIELD else ""
    )
    # The `m` option states the bounds in metres rather than as fractions of the beam.
    if options.contains("m") and length_m > 0.0:
        short_bound /= length_m
        long_bound /= length_m
    row["short_bound"] = maxf(short_bound, 0.0)
    row["long_bound"] = maxf(long_bound, 0.0)
    if fields.size() > SHOCK_PRECOMPRESSION_FIELD:
        row["precompression"] = maxf(fields[SHOCK_PRECOMPRESSION_FIELD].to_float(), 0.0)
