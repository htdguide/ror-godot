class_name PlacementRows
extends RefCounted
## Parses the two sections that hang a mesh off a node triad: `flexbodies` and `props`.
##
## Both rows start the same way — three nodes, a three-axis offset, a three-axis rotation
## in degrees, a mesh name — and differ only in what follows. A flexbody is skinned to a
## set of nodes; a prop is rigid and simply rides its triad. Sharing the parse keeps the
## two from drifting apart, which matters because the triad convention is the part that is
## easy to get subtly wrong.

## The steering column's rake, which is upstream's own: `Quaternion(Degree(-59), UNIT_X)` in
## `GfxActor::UpdateProps`, applied after the dashboard prop's orientation and before the steering
## angle about Y.
##
## **It read 121 for as long as a prop's frame was built with the wrong euler order.** 121 is
## 180 - 59, and that 180 was cancelling an error in the frame rather than describing a column.
## The hero truck's dashboard states `-95, 0, 180` — a rotation about two axes, where `Z then Y
## then X` and Godot's default `YXZ` disagree — and its prop frame came out 190 degrees from
## upstream's. Every other dashboard in this library turns about one axis only, where the two
## orders agree, so their frames were already right and the rake was wrong for all of them: the
## 49 Ford, the Gavril Bandit, Omega and Zeta and the Spacewagon all turned their wheels the wrong
## way, and the hero truck did not, which is how the compensation survived.
const STEERING_COLUMN_RAKE_DEG: float = -59.0

## Upstream composes a prop's rotation Z, then Y, then X. Godot's default Euler order is
## YXZ, which agrees only when one of the three angles is zero. The hero truck's seatbelt
## buckles are rotated on all three axes, so the order is not academic there.
const PROP_EULER_ORDER: int = EULER_ORDER_ZYX
## A dashboard prop carries a steering wheel as a second mesh. Upstream has a default
## seating position for it, used when the row does not state one. A row that states zero
## states zero: reading that as "use the default" puts the hero truck's wheel out beside
## the front tyre, which is where this started.
const STEERING_DEFAULT_OFFSET: Vector3 = Vector3(0.67, -0.61, 0.24)


## Common head of both row types: {ref, nx, ny, offset, rot_deg, mesh} or {} with a reason.
static func head(fields: PackedStringArray, id_to_index: Dictionary) -> Dictionary:
    if fields.size() < 10:
        return {"error": "row has %d fields, expected at least 10" % fields.size()}
    var ref: int = int(id_to_index.get(fields[0], -1))
    var nx: int = int(id_to_index.get(fields[1], -1))
    var ny: int = int(id_to_index.get(fields[2], -1))
    if ref < 0 or nx < 0 or ny < 0:
        return {"error": "row references an unknown node"}
    return {
        "error": "",
        "ref": ref,
        "nx": nx,
        "ny": ny,
        "offset": Vector3(fields[3].to_float(), fields[4].to_float(), fields[5].to_float()),
        "rot_deg": Vector3(fields[6].to_float(), fields[7].to_float(), fields[8].to_float()),
        "mesh": fields[9],
    }


## "ref,x,y, offsets, rotations, mesh" plus, for a dashboard, a steering wheel mesh with
## its own offset and rotation about the column.
static func prop(fields: PackedStringArray, id_to_index: Dictionary) -> Dictionary:
    var out: Dictionary = head(fields, id_to_index)
    if (out["error"] as String) != "":
        return out
    out["steering_mesh"] = ""
    out["steering_offset"] = Vector3.ZERO
    out["steering_deg_per_input"] = 0.0
    if not (out["mesh"] as String).to_lower().contains("dashboard") or fields.size() < 11:
        return out
    out["steering_mesh"] = fields[10]
    if fields.size() >= 14:
        out["steering_offset"] = Vector3(
            fields[11].to_float(), fields[12].to_float(), fields[13].to_float()
        )
    else:
        out["steering_offset"] = STEERING_DEFAULT_OFFSET
    if fields.size() >= 15:
        out["steering_deg_per_input"] = fields[14].to_float()
    return out
