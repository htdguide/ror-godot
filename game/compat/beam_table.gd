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
## One entry per beam that has a travel limit rather than being a plain spring: shocks, ropes and
## support beams. {beam, bound, short_bound, long_bound, bound_spring, bound_damp,
## precompression}. Without these a shock is a soft spring with no bump stop, so a suspension
## travels through its own limits and a door damper never resists.
var bounded: Array[Dictionary] = []


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
        })
    beams.append(row["a"] as int)
    beams.append(row["b"] as int)
    spring.append(row["spring"] as float)
    damp.append(row["damp"] as float)
    deform.append(float(row.get("deform", BeamDefaults.DEFAULT_DEFORM)))
    strength.append(float(row.get("strength", BeamDefaults.DEFAULT_BREAK)))
    plastic.append(float(row.get("plastic_coef", BeamDefaults.DEFAULT_PLASTIC_COEF)))


func count() -> int:
    return beams.size() / 2
