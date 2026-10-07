extends SceneTree
## How far a settled wheel's tread sits from its own axle, and how high the body rides.
##
## A tyre that collapses onto its rim reads here as a tread radius well under the one its row
## states, and a rig sitting on its belly reads as a ride height near zero.
##
##   godot --path . --headless --script res://harness/dev/wheel_stance.gd -- <mod dir> <actor file>

const SETTLE_SECONDS: float = 3.0


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    var truck: TruckParser = TruckParser.new()
    var failed: String = truck.parse_file(
        SourceScan.repo_root().path_join(argv[0]).path_join(argv[1])
    )
    if failed != "":
        printerr(failed)
        quit(1)
        return
    var rig: Dictionary = RigBuilder.build(truck, 0.15)
    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.15)
    for _i: int in int(SETTLE_SECONDS * 60.0):
        solver.step(1.0 / 2000.0, 33)
    var at: PackedVector3Array = solver.get_positions()
    for index: int in truck.wheels.size():
        var wheel: Dictionary = truck.wheels[index]
        var axle: Vector3 = (at[wheel["node1"] as int] + at[wheel["node2"] as int]) * 0.5
        var mean: float = 0.0
        var lowest: float = INF
        var first: int = int(wheel["first_tread"])
        for i: int in int(wheel["tread_count"]):
            var node: Vector3 = at[first + i]
            mean += Vector2(node.x - axle.x, node.z - axle.z).length()
            lowest = minf(lowest, node.y)
        mean /= maxf(float(int(wheel["tread_count"])), 1.0)
        print("wheel %d  stated radius %.3f m  settled tread radius %.3f m  lowest tread %.3f m" % [
            index, wheel["tire_radius"], mean, lowest])
    for index: int in truck.wheels.size():
        var wheel: Dictionary = truck.wheels[index]
        var a: int = wheel["node1"] as int
        var b: int = wheel["node2"] as int
        print("wheel %d axle y: rest %.3f -> settled %.3f (dropped %.3f m)" % [
            index, (truck.nodes[a].y + truck.nodes[b].y) * 0.5,
            (at[a].y + at[b].y) * 0.5,
            (truck.nodes[a].y + truck.nodes[b].y - at[a].y - at[b].y) * 0.5])
    var body_low: float = INF
    var body_which: int = -1
    for i: int in truck.generated_from:
        if at[i].y < body_low:
            body_low = at[i].y
            body_which = i
    print("lowest body node %d (%s): rest y %.3f -> settled %.3f" % [
        body_which, truck.node_ids[body_which], truck.nodes[body_which].y, body_low])
    var drops: Array[Dictionary] = []
    for i: int in truck.generated_from:
        drops.append({"node": i, "drop": truck.nodes[i].y - at[i].y})
    drops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return float(a["drop"]) > float(b["drop"]))
    print("-- the body nodes that sagged furthest --")
    for i: int in mini(drops.size(), 10):
        var node: int = int(drops[i]["node"])
        var beams: int = 0
        for b: int in truck.beams.size():
            if truck.beams[b] == node:
                beams += 1
        print("  node %3d  rest %v  dropped %.3f m  %d beams" % [
            node, truck.nodes[node], float(drops[i]["drop"]), beams])
    print("broken beams %d of %d" % [solver.broken_beam_count(), solver.beam_count()])
    var families: Dictionary = {}
    for beam: int in solver.beam_count():
        if not solver.beam_broken(beam):
            continue
        var a: int = truck.beams[beam * 2]
        var b: int = truck.beams[beam * 2 + 1]
        var key: String = "%s-%s  k %.0f d %.0f deform %.0f strength %.0f" % [
            "gen" if a >= truck.generated_from else "body",
            "gen" if b >= truck.generated_from else "body",
            truck.beam_spring[beam], truck.beam_damp[beam],
            truck.beam_deform[beam], truck.beam_strength[beam]]
        families[key] = int(families.get(key, 0)) + 1
    for key: String in families:
        print("  %4d  %s" % [int(families[key]), key])
    print("-- the cinecam mounts --")
    var rest: PackedVector3Array = truck.nodes
    for beam: int in solver.beam_count():
        if absf(truck.beam_spring[beam] - 8000.0) > 1.0:
            continue
        var a: int = truck.beams[beam * 2]
        var b: int = truck.beams[beam * 2 + 1]
        print("  beam %4d %3d(%s)-%3d(%s)  rest %.3f m  now %.3f m  %s" % [
            beam, a, truck.node_ids[a], b, truck.node_ids[b],
            rest[a].distance_to(rest[b]), at[a].distance_to(at[b]),
            "BROKEN" if solver.beam_broken(beam) else "held"])
    quit(0)
