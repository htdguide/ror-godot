extends SceneTree
## Every drawn part of a vehicle with where it ended up, and every node a prop row names.
##
##   godot --path . --headless --script res://harness/dev/part_dump.gd -- <mod dir> <actor file>


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    var built: Dictionary = VehicleBuilder.build(argv[0], argv[1])
    if (built.get("error", "") as String) != "":
        printerr(built["error"])
        quit(1)
        return
    var truck: TruckParser = built["truck"] as TruckParser
    var root: Node3D = built["root"] as Node3D
    # In the tree, so that `global_position` is what the renderer uses rather than identity.
    get_root().add_child(root)
    var rig_to_local: Transform3D = built["rig_to_local"] as Transform3D
    print("rig_to_local %s" % rig_to_local)
    print("prop rows %d, prop nodes %d | flexbody rows %d, parts %d | wheels %d, wheel nodes %d" % [
        truck.props.size(), (built["prop_nodes"] as Array[Node3D]).size(),
        truck.flexbodies.size(), (built["parts"] as Array[SkinnedFlexbody]).size(),
        truck.wheels.size(), (built["wheel_nodes"] as Array[Node3D]).size()])
    print("declared nodes %d, first generated %d, total %d" % [
        truck.nodes.size() - (truck.nodes.size() - truck.generated_from), truck.generated_from,
        truck.nodes.size()])
    for wheel: Dictionary in truck.wheels:
        var axle: Vector3 = (truck.nodes[wheel["node1"] as int]
            + truck.nodes[wheel["node2"] as int]) * 0.5
        var tread: Vector3 = Vector3.ZERO
        for i: int in int(wheel["tread_count"]):
            tread += truck.nodes[int(wheel["first_tread"]) + i]
        tread /= maxf(float(int(wheel["tread_count"])), 1.0)
        print("wheel axle %d/%d at %v -> %v | tread mean %v -> %v | first_tread %d" % [
            wheel["node1"], wheel["node2"], axle, rig_to_local * axle,
            tread, rig_to_local * tread, wheel["first_tread"]])
    for index: int in truck.flexbodies.size():
        var fb: Dictionary = truck.flexbodies[index]
        print("flexbody %2d ref %3d nx %3d ny %3d  forset %3d nodes  %s" % [
            index, fb["ref"], fb["nx"], fb["ny"],
            (fb["forset"] as PackedInt32Array).size(), fb["mesh"]])
    for index: int in truck.props.size():
        var prop: Dictionary = truck.props[index]
        var ref: int = int(prop["ref"])
        var nx: int = int(prop["nx"])
        var ny: int = int(prop["ny"])
        print("prop %2d ref %3d %v | x %3d %v | y %3d %v | %s" % [
            index, ref, truck.nodes[ref], nx, truck.nodes[nx], ny, truck.nodes[ny],
            prop["mesh"]])
    var rig: Dictionary = RigBuilder.build(truck, 0.15)
    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.15)
    for _i: int in 120:
        solver.step(1.0 / 2000.0, 33)
    var positions: PackedVector3Array = solver.get_positions()
    var actor: Transform3D = ActorFrame.of(positions, truck.camera_nodes)
    print("camera_nodes %s" % truck.camera_nodes)
    print("actor %s" % actor)
    VehicleBuilder.apply_pose(built, truck, positions, PackedFloat32Array())
    print("-- posed parts (vehicle-local) --")
    for part: SkinnedFlexbody in built["parts"] as Array[SkinnedFlexbody]:
        print("%-28s %d bones  posed centre %v" % [
            part.mesh_instance.name, part.triads.size(),
            part.mesh_instance.get_aabb().get_center()])
    print("-- wheels (vehicle-local) --")
    for node: Node3D in built["wheel_nodes"] as Array[Node3D]:
        print("wheel at %v" % node.transform.origin)
    print("-- drawn (local to the vehicle root) --")
    for node: Node in _all(root):
        var mesh: MeshInstance3D = node as MeshInstance3D
        if mesh == null:
            continue
        var box: AABB = mesh.global_transform * mesh.get_aabb()
        print("%-34s at %v  rest centre %v" % [
            mesh.name, mesh.global_position, box.get_center()])
    quit(0)


func _all(node: Node) -> Array[Node]:
    var out: Array[Node] = [node]
    for child: Node in node.get_children():
        out.append_array(_all(child))
    return out
