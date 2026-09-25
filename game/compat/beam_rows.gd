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


static func handles(section: String) -> bool:
    return SPRING_FIELD.has(section)


## Returns {"error": String, "a": int, "b": int, "spring": float, "damp": float,
## "factor": float}. `factor` is zero for every section that does not actuate.
static func joint(
    section: String,
    fields: PackedStringArray,
    id_to_index: Dictionary,
    default_spring: float,
    default_damp: float
) -> Dictionary:
    if fields.size() < 2:
        return {"error": "row has %d fields, expected at least 2" % fields.size()}
    var a: int = int(id_to_index.get(fields[0], -1))
    var b: int = int(id_to_index.get(fields[1], -1))
    if a < 0 or b < 0:
        return {"error": "row references an unknown node"}
    var spring: float = default_spring
    var damp: float = default_damp
    var at: int = int(SPRING_FIELD[section])
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
    return {"error": "", "a": a, "b": b, "spring": spring, "damp": damp, "factor": factor}
