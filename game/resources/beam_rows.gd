class_name BeamRows
extends RefCounted
## Parses the sections that declare a beam without calling it one: `shocks`, `hydros` and
## `commands2`.
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
}
## The field holding the actuation factor, for the sections that have one. A hydro's is a
## signed fraction of its rest length per unit of steering input: the rams on opposite
## sides of a rack carry opposite signs so that one pushes while the other pulls.
const FACTOR_FIELD: Dictionary = {
    "hydros": 2,
}

## How much stronger than the file's break figure a section's beams are.
##
## Upstream's spawner gives a shock four times the breaking threshold in force
## (`SetBeamStrength(beam, def.beam_defaults->breaking_threshold * 4.f)`), and it is not a
## detail: a shock's force is mostly damping, so at the hero truck's 2400 Ns/m and a 4000 N
## threshold it snaps at 1.7 m/s of suspension travel — a kerb. Measured, two of its door
## dampers broke while the rig was settling onto its own springs, before anything had been
## driven at all, and a third broke on the next landing, which is what a session reported as
## recovering the truck breaking a wheel.
const STRENGTH_SCALE: Dictionary = {
    "shocks": 4.0,
    "shocks2": 4.0,
    "shocks3": 4.0,
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
        "deform": defaults.deform(),
        "strength": defaults.breaking_strength(),
        "plastic_coef": defaults.plastic_coef(),
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


## Where a `ties` row states each of its values: "root_node, max_reach_length,
## auto_shorten_rate, min_length, max_length, options, max_stress, group".
const TIE_REACH_FIELD: int = 1
const TIE_RATE_FIELD: int = 2
const TIE_MIN_FIELD: int = 3
const TIE_MAX_FIELD: int = 4
const TIE_OPTIONS_FIELD: int = 5
const TIE_STRESS_FIELD: int = 6
const TIE_GROUP_FIELD: int = 7
## Upstream's own default, for a row that states no limit.
const TIE_DEFAULT_STRESS: float = 100000.0


## A row of the `ties` section: a rope that is not attached to anything yet.
##
## **A tie names one node, not two, and read as a beam row it invented a member.** Upstream's
## `ProcessTie` takes the row's single root node, pairs it with node 0 — node 1 when the root
## *is* node 0 — and adds a rope beam that it immediately disables: a tie does nothing at all
## until a player hooks it onto a ropable, and only then does it contract. Read here as a
## two-node row the second field was the reach length, which is why 39 rows across this
## checkout's corpus reported an unknown node; a row whose reach happened to be written as a
## whole number would instead have passed, and welded the rig to whichever node that was.
##
## No beam is built. The beam upstream builds starts disabled and this project has no tying
## action to enable it with, so a beam here would be a member a real rig does not have.
## Returns {"error", "root", "reach_m", "rate", "min_length", "max_length", "options",
## "max_stress", "group"}.
static func tie(fields: PackedStringArray, id_to_index: Dictionary) -> Dictionary:
    if fields.size() < 2:
        return {"error": "row has %d fields, expected at least 2" % fields.size()}
    var root: int = int(id_to_index.get(fields[0], -1))
    if root < 0:
        return {"error": "row references an unknown node"}
    return {
        "error": "",
        "root": root,
        "reach_m": fields[TIE_REACH_FIELD].to_float(),
        "rate": _field(fields, TIE_RATE_FIELD, 0.0),
        "min_length": _field(fields, TIE_MIN_FIELD, 0.0),
        "max_length": _field(fields, TIE_MAX_FIELD, 0.0),
        "options": fields[TIE_OPTIONS_FIELD] if fields.size() > TIE_OPTIONS_FIELD else "n",
        "max_stress": _field(fields, TIE_STRESS_FIELD, TIE_DEFAULT_STRESS),
        "group": int(_field(fields, TIE_GROUP_FIELD, -1.0)),
    }


static func _field(fields: PackedStringArray, at: int, fallback: float) -> float:
    return fields[at].to_float() if fields.size() > at else fallback


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
        # What it takes to bend this beam and what it takes to break it. A beam that states its
        # own rates still takes the file's deform and break figures: upstream's `beams` section
        # has no per-beam yield, only the defaults in force where the row was written.
        "deform": defaults.deform(),
        "strength": defaults.breaking_strength() * float(
            STRENGTH_SCALE.get(section, 1.0)
        ),
        "plastic_coef": defaults.plastic_coef(),
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
