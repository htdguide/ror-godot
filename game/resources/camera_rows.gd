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

## How many nodes a cinecam hangs from, and where in the row they start. Upstream's `nodes[8]`.
const MOUNTS: int = 8
const FIRST_MOUNT_FIELD: int = 3
const SPRING_FIELD: int = 11
const MASS_FIELD: int = 13
## Upstream's `RigDef::Cinecam` defaults, for a row that states none of its own.
const DEFAULT_SPRING: float = 8000.0
const DEFAULT_DAMP: float = 800.0
## **A cinecam node weighs this, and it does not take a share of the rig's dry mass.**
## `Actor::RecalculateNodeMasses` distributes the dry mass over the beams and then overwrites
## every cinecam node's mass with the row's own figure, before the minimass floor is applied. Left
## to the distribution it lands wherever the rig's mass happens to put it — and on a vehicle whose
## `globals` states a dry mass of zero, as the Mazda's does, that is the 0.20 kg minimass. Eight
## mounts at 800 Ns/m on 0.2 kg is a damping ratio of 16 against an explicit integrator's bound of
## 2 at 2 kHz: the node shakes itself apart, tears off all eight of its beams and leaves the rig.
## Measured, it ended 14 m from a mount whose rest length is 1.9 m.
const DEFAULT_MASS: float = 20.0

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


## "x, y, z, node1..node8, spring, damp".
##
## **A cinecam is a node, and that is not a detail about the camera.** Upstream's
## `ProcessCinecam` appends one node at the stated position and eight beams from it to the
## nodes the row names, and those nodes are numbered *before* every wheel node — so a file
## with three cinecams has its first tyre node three higher than a reader that skipped them
## thinks. Measured on the Mazda: its hubcaps name node 332, which is the first rim node of
## its left front wheel only once its three cinecams have been counted.
##
## Returns {"error", "position", "nodes", "spring", "damp", "mass"}; `nodes` are the node ids as
## written, left unresolved because this is read before the wheel sections and resolving is the
## parser's to do once every node exists.
func read_cinecam(fields: PackedStringArray) -> Dictionary:
    if fields.size() < 3:
        return {"error": "row has %d fields, expected at least 3" % fields.size()}
    var position: Vector3 = Vector3(
        fields[0].to_float(), fields[1].to_float(), fields[2].to_float()
    )
    positions.append(position)
    var named: PackedStringArray = PackedStringArray()
    for at: int in range(FIRST_MOUNT_FIELD, mini(FIRST_MOUNT_FIELD + MOUNTS, fields.size())):
        named.append(fields[at])
    return {
        "error": "",
        "position": position,
        "nodes": named,
        "spring": (
            fields[SPRING_FIELD].to_float() if fields.size() > SPRING_FIELD
            else DEFAULT_SPRING
        ),
        "damp": (
            fields[SPRING_FIELD + 1].to_float() if fields.size() > SPRING_FIELD + 1
            else DEFAULT_DAMP
        ),
        # Upstream ignores a stated mass of zero or less, because a trailing pseudo-comment
        # parses as one.
        "mass": (
            fields[MASS_FIELD].to_float()
            if fields.size() > MASS_FIELD and fields[MASS_FIELD].to_float() > 0.0
            else DEFAULT_MASS
        ),
    }


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
