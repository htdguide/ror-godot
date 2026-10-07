class_name CinecamMount
extends RefCounted
## The node and the eight beams a `cinecam` row declares.
##
## **A cinecam is a node, and the node is the point here rather than the camera.** Upstream's
## `ProcessCinecam` appends one node at the stated position and hangs it on eight beams to the
## nodes the row names. Two things follow, and both were live faults:
##
## The node is numbered *before* every wheel node, so a reader that skips cinecams has every
## generated node number too low by the count of cinecams the file declares. The Mazda declares
## three and its hubcaps name node 332, which is the first rim node of its left front wheel only
## once those three are counted; read without them each hubcap, brake disc and tyre named a node
## that did not exist and was dropped.
##
## And the eight beams are what make it a node at all. A point mass with no member holding it is
## not part of the rig: it takes its share of the dry mass and then falls out of the vehicle.
##
## Lives apart from `TruckParser` because it is a section that builds structure rather than
## records a row, which is what `WheelRig` is too, and the parser is at its size cap.


## Adds the node and its beams to `truck`. `row` is `CameraRows.read_cinecam`'s.
static func build(truck: TruckParser, row: Dictionary) -> void:
    var at: int = truck.nodes.size()
    truck.register_generated("@cinecam%d" % truck.cinecams.size())
    truck.nodes.append(row["position"] as Vector3)
    # Upstream applies neither the node defaults' weight nor the row's own `node_mass` here, on
    # purpose and with a comment saying so: the node goes through the rig's own mass
    # distribution like any other body node.
    truck.node_mass.append(-1.0)
    truck.node_friction.append(NodeRows.FRICTION_DEFAULT)
    for mount: String in row["nodes"] as PackedStringArray:
        var to: int = int(truck.node_id_to_index.get(mount, -1))
        if to < 0:
            truck.errors.append("cinecam mount references an unknown node: %s" % mount)
            continue
        truck.beam_table.record(_beam(at, to, row, truck.beam_defaults))


## The mount beam itself: the row's own rates, and the defaults' yield and breaking stresses.
static func _beam(
    at: int, to: int, row: Dictionary, defaults: BeamDefaults
) -> Dictionary:
    return {
        "a": at,
        "b": to,
        "spring": row["spring"] as float,
        "damp": row["damp"] as float,
        "deform": defaults.deform(),
        "strength": defaults.breaking_strength(),
        "plastic_coef": defaults.plastic_coef(),
        "bound": BeamRows.BOUND_NORMAL,
        "short_bound": 0.0,
        "long_bound": 0.0,
        "bound_spring": row["spring"] as float,
        "bound_damp": row["damp"] as float,
        "precompression": 1.0,
    }
