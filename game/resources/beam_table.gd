class_name BeamTable
extends RefCounted
## The beams a file declares, and what each one is made of.
##
## Extracted from `TruckParser` when that file reached its size cap, and it is a responsibility
## rather than a slice: a beam is not one number. It is a pair of nodes, a spring and a damper
## from whatever `set_beam_defaults` was in force where the row was written, the stress it yields
## at, the stress it breaks at, and — for shocks, ropes and support beams — what happens outside
## its travel. Keeping those together is what makes it possible to say "this beam" and mean all of
## it.

## Node pairs, two entries per beam.
var beams: PackedInt32Array = PackedInt32Array()
## Per-beam spring and damping, as set by the `set_beam_defaults` directives in force where each
## beam was declared. Using one global default instead makes a real rig explode: the files are
## written against the values they declare.
var spring: PackedFloat32Array = PackedFloat32Array()
var damp: PackedFloat32Array = PackedFloat32Array()
## What each beam yields at and what it breaks at, from the same defaults. A beam past its deform
## stress bends permanently; past its strength it snaps. Unparsed, a rig is a perfect spring: it
## can be driven into a wall at any speed and come away the shape it started.
var deform: PackedFloat32Array = PackedFloat32Array()
var strength: PackedFloat32Array = PackedFloat32Array()
var plastic: PackedFloat32Array = PackedFloat32Array()
## Whether each beam may take a permanent set. An actuator does not: see `BeamRows.NEVER_YIELDS`.
var deformable: PackedByteArray = PackedByteArray()
## Whether each beam is one of upstream's `BEAM_VIRTUAL`: it carries force like any other, is
## never drawn, and is left out of the rig's mass distribution. A wheel's rigidity beams are the
## case that exists.
var virtual_beam: PackedByteArray = PackedByteArray()
## One entry per beam that has a travel limit rather than being a plain spring: shocks, ropes and
## support beams. {beam, bound, short_bound, long_bound, bound_spring, bound_damp,
## precompression}. Without these a shock is a soft spring with no bump stop, so a suspension
## travels through its own limits and a door damper never resists.
var bounded: Array[Dictionary] = []
## Each beam's detacher group (`detacher_group` in force where its row stands; 0 for none): when a
## beam of a positive group breaks, every beam of that group or its negative breaks with it, and
## the wheels `wheel_detachers` names for the group come off. {wheel, group} per `wheeldetachers` row.
var detacher: PackedInt32Array = PackedInt32Array()
var wheel_detachers: Array[Dictionary] = []
## The group in force for the row being read; a beam the file only implies (a wheel's, a
## cinecam's) states 0 itself, as upstream gives those `DEFAULT_DETACHER_GROUP`.
var detacher_group: int = 0


## Appends a beam row, and remembers what it does outside its travel when it is not a plain
## spring.
func record(row: Dictionary) -> void:
    var index: int = beams.size() / 2
    if (row["bound"] as int) != BeamRows.BOUND_NORMAL:
        bounded.append({
            "beam": index,
            "bound": row["bound"],
            "short_bound": row["short_bound"],
            "long_bound": row["long_bound"],
            "bound_spring": row["bound_spring"],
            "bound_damp": row["bound_damp"],
            "precompression": row["precompression"],
            # A `shocks2`/`shocks3` beam's own rates and its soft bump: see `BeamRows.joint`.
            "rates": row.get("rates", PackedFloat32Array()),
            "soft_bump": bool(row.get("soft_bump", false)),
        })
    beams.append(row["a"] as int)
    beams.append(row["b"] as int)
    spring.append(row["spring"] as float)
    damp.append(row["damp"] as float)
    deform.append(float(row.get("deform", BeamDefaults.DEFAULT_DEFORM)))
    strength.append(float(row.get("strength", BeamDefaults.DEFAULT_BREAK)))
    plastic.append(float(row.get("plastic_coef", BeamDefaults.DEFAULT_PLASTIC_COEF)))
    deformable.append(1 if bool(row.get("deformable", true)) else 0)
    virtual_beam.append(1 if bool(row.get("virtual", false)) else 0)
    detacher.append(int(row.get("detacher_group", detacher_group)))


func count() -> int:
    return beams.size() / 2
