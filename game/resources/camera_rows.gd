class_name CameraRows
extends RefCounted
## Where a vehicle file says its cameras go: the `cameras` and `cinecam` sections.
##
## Two things here cost time to establish and are easy to get wrong again.
##
## A `cameras` row names three nodes — a centre, a node in front, and a node to one side — and
## it may appear *before* the nodes section it refers to, as it does in upstream's own DAF
## semi. Resolving those names eagerly rejects a valid file, so they are kept as names until
## the whole file has been read.
##
## A rig commonly declares several cinecams and only some sit inside the cab. The hero truck's
## first is a raised centre view 0.22 m above its own roof; its second is the driver's eye.
## Which one a caller wants depends on what it is for, so every one is kept in file order and
## the choice is left to the caller.

## The node names from the first `cameras` row, unresolved.
var pending: PackedStringArray = PackedStringArray()
## Every cinecam position the file declares, in file order.
var positions: PackedVector3Array = PackedVector3Array()


## Rows are "centre_node, direction_node, roll_node". Only the first row is kept: it is the
## actor's main camera, and one frame per actor is what the bridge needs.
func read_cameras(fields: PackedStringArray) -> void:
    if not pending.is_empty() or fields.size() < 3:
        return
    pending = PackedStringArray([fields[0], fields[1], fields[2]])


## "x, y, z, node1..node8, spring, damp" — only the position is needed here.
func read_cinecam(fields: PackedStringArray) -> void:
    if fields.size() < 3:
        return
    positions.append(
        Vector3(fields[0].to_float(), fields[1].to_float(), fields[2].to_float())
    )


## Resolves the reference nodes once every node is known. Returns
## {"nodes": {centre, dir, roll}, "error": String}; `nodes` is empty when the file named none.
func resolve(id_to_index: Dictionary) -> Dictionary:
    if pending.size() < 3:
        return {"nodes": {}, "error": ""}
    var centre: int = int(id_to_index.get(pending[0], -1))
    var direction: int = int(id_to_index.get(pending[1], -1))
    var roll: int = int(id_to_index.get(pending[2], -1))
    if centre < 0 or direction < 0 or roll < 0:
        return {
            "nodes": {},
            "error": "cameras references unknown node: %s" % ", ".join(pending),
        }
    return {"nodes": {"centre": centre, "dir": direction, "roll": roll}, "error": ""}
