extends SceneTree
## Measures how far each part's nodes move relative to the vehicle, after settling.
##
##   godot --path game --headless --script res://tools/hinge_probe.gd -- <mod dir> <truck>
##
## A part that stays put relative to the body is attached; one that swings away is not.
## Rigid motion of the whole vehicle is removed first, so what is left is the part moving
## against the rig rather than the rig moving against the world.

const SUBSTEP_HZ: float = 10000.0
const SETTLE_SECONDS: float = 2.0
const DROP_HEIGHT_M: float = 0.3


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_file(argv[0].path_join(argv[1]))
    if error != "":
        printerr(error)
        quit(1)
        return
    var solver: RefCounted = ClassDB.instantiate("RorSolver") as RefCounted
    var mass: float = maxf(truck.minimass_kg, 1.0)
    var lowest: float = INF
    for node: Vector3 in truck.nodes:
        lowest = minf(lowest, node.y)
    var lift: Vector3 = Vector3(0.0, DROP_HEIGHT_M - lowest, 0.0)
    for node: Vector3 in truck.nodes:
        solver.add_node(node + lift, mass)
    for i: int in range(0, truck.beams.size(), 2):
        var beam: int = i / 2
        solver.add_beam(
            truck.beams[i], truck.beams[i + 1], 0.0,
            truck.beam_spring[beam], truck.beam_damp[beam]
        )
    solver.set_gravity(Vector3(0.0, -9.81, 0.0))
    solver.set_ground(0.0, true)
    solver.step(1.0 / SUBSTEP_HZ, int(SETTLE_SECONDS * SUBSTEP_HZ))

    var settled: PackedVector3Array = PackedVector3Array()
    for n: int in solver.node_count():
        settled.append(solver.get_node_position(n))
    # Take the rig's own frame out of it, so a part's motion is measured against the
    # vehicle rather than against the world it has just landed in.
    var before: Transform3D = ActorFrame.of(truck.nodes, truck.camera_nodes)
    var after: Transform3D = ActorFrame.of(settled, truck.camera_nodes)
    var rest_to_actor: Transform3D = before.affine_inverse()
    var settled_to_actor: Transform3D = after.affine_inverse()

    for entry: Dictionary in truck.flexbodies:
        var forset: PackedInt32Array = entry["forset"] as PackedInt32Array
        var worst: float = 0.0
        var total: float = 0.0
        for id: int in forset:
            var moved: float = (
                (settled_to_actor * settled[id]) - (rest_to_actor * truck.nodes[id])
            ).length()
            worst = maxf(worst, moved)
            total += moved
        print("%-24s nodes %3d  mean %6.1f mm  worst %6.1f mm" % [
            entry["mesh"], forset.size(),
            1000.0 * total / maxf(float(forset.size()), 1.0), 1000.0 * worst
        ])
    # How each of those nodes is held. A node with no beam to anything outside its own
    # part is not attached to the vehicle at all, whatever the file appears to say.
    var door: PackedInt32Array = PackedInt32Array()
    for entry: Dictionary in truck.flexbodies:
        if (entry["mesh"] as String).begins_with("S10door."):
            door = entry["forset"] as PackedInt32Array
    var inside: Dictionary = {}
    for id: int in door:
        inside[id] = true
    var internal: int = 0
    var external: int = 0
    var loose: PackedInt32Array = PackedInt32Array()
    var touched: Dictionary = {}
    for i: int in range(0, truck.beams.size(), 2):
        var a: int = truck.beams[i]
        var b: int = truck.beams[i + 1]
        var a_in: bool = inside.has(a)
        var b_in: bool = inside.has(b)
        if not a_in and not b_in:
            continue
        if a_in and b_in:
            internal += 1
        else:
            external += 1
            touched[a if a_in else b] = true
    for id: int in door:
        if not touched.has(id):
            loose.append(id)
    print("door nodes %d: %d beams inside the door, %d to the rest of the rig" % [
        door.size(), internal, external
    ])
    print("door nodes with no beam to the rest of the rig: %d" % loose.size())
    var door_spring: float = INF
    var door_total: float = 0.0
    var door_count: int = 0
    var rig_spring: float = INF
    var rig_total: float = 0.0
    var rig_count: int = 0
    for i: int in range(0, truck.beams.size(), 2):
        var beam: int = i / 2
        var spring: float = truck.beam_spring[beam]
        var a_in: bool = inside.has(truck.beams[i])
        var b_in: bool = inside.has(truck.beams[i + 1])
        if a_in or b_in:
            door_spring = minf(door_spring, spring)
            door_total += spring
            door_count += 1
        else:
            rig_spring = minf(rig_spring, spring)
            rig_total += spring
            rig_count += 1
    print("door beams  %d  min spring %.0f  mean %.0f" % [
        door_count, door_spring, door_total / maxf(float(door_count), 1.0)
    ])
    print("other beams %d  min spring %.0f  mean %.0f" % [
        rig_count, rig_spring, rig_total / maxf(float(rig_count), 1.0)
    ])
    # Strain says which of two stories is true. Beams stretched far past their rest length
    # mean the solver is failing to hold the door. Beams at rest length mean the door is
    # being carried somewhere by beams that are perfectly satisfied, and the fault is in
    # what they are attached to.
    var worst_strain: float = 0.0
    var worst_beam: String = ""
    var strained: int = 0
    for i: int in range(0, truck.beams.size(), 2):
        var a: int = truck.beams[i]
        var b: int = truck.beams[i + 1]
        if not (inside.has(a) or inside.has(b)):
            continue
        var rest: float = truck.nodes[a].distance_to(truck.nodes[b])
        if rest <= 0.0001:
            continue
        var now: float = settled[a].distance_to(settled[b])
        var strain: float = absf(now - rest) / rest
        if strain > 0.05:
            strained += 1
        if strain > worst_strain:
            worst_strain = strain
            worst_beam = "%d-%d rest %.3f now %.3f" % [a, b, rest, now]
    var movers: PackedInt32Array = PackedInt32Array()
    for n: int in truck.nodes.size():
        var moved: float = (
            (settled_to_actor * settled[n]) - (rest_to_actor * truck.nodes[n])
        ).length()
        if moved > 0.1:
            movers.append(n)
    var ids: PackedStringArray = PackedStringArray()
    for n: int in movers:
        ids.append(truck.node_ids[n] if n < truck.node_ids.size() else str(n))
    print("nodes moving over 100 mm: %d of %d" % [movers.size(), truck.nodes.size()])
    print("their ids: %s" % ", ".join(ids))
    print("door beams over 5%% strain: %d of %d; worst %.1f%% (%s)" % [
        strained, door_count, worst_strain * 100.0, worst_beam
    ])
    quit(0)
