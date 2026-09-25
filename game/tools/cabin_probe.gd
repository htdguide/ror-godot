extends SceneTree
## Prints where the driver's eye lands relative to the vehicle it is supposed to sit in.
##
##   godot --path game --headless --script res://tools/cabin_probe.gd -- <mod dir> <truck>


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    var built: Dictionary = VehicleBuilder.build(argv[0], argv[1])
    if (built.get("error", "") as String) != "":
        printerr(built["error"])
        quit(1)
        return
    var root: Node3D = built["root"] as Node3D
    get_root().add_child(root)
    var truck: TruckParser = built["truck"] as TruckParser
    var bounds: AABB = VehicleBuilder.world_bounds(root)
    var rig_to_local: Transform3D = built["rig_to_local"] as Transform3D
    var eye: Vector3 = root.global_transform * (rig_to_local * truck.cinecam_position)

    print("has_cinecam      %s" % truck.has_cinecam)
    print("cinecam rig      %v" % truck.cinecam_position)
    print("rig_to_local     %s" % rig_to_local)
    print("root transform   %s" % root.global_transform)
    print("world bounds     pos %v size %v" % [bounds.position, bounds.size])
    print("eye world        %v" % eye)
    print("eye inside body  %s" % bounds.has_point(eye))
    var node_box: AABB = AABB(truck.nodes[0], Vector3.ZERO)
    for node: Vector3 in truck.nodes:
        node_box = node_box.expand(node)
    print("rig node bounds  pos %v size %v" % [node_box.position, node_box.size])
    # The cinecam is beamed to eight named nodes, so it must sit among them. Their
    # centroid is an independent statement of where the driver's eye belongs.
    var anchors: PackedInt32Array = PackedInt32Array([3, 11, 4, 12, 19, 27, 20, 28])
    var centroid: Vector3 = Vector3.ZERO
    for id: int in anchors:
        centroid += truck.nodes[id]
    centroid /= float(anchors.size())
    print("anchor centroid  rig %v -> local %v" % [centroid, rig_to_local * centroid])
    print("-- each part's mesh against the nodes it is bound to, in rig space --")
    for i: int in (built["parts"] as Array[SkinnedFlexbody]).size():
        var part: SkinnedFlexbody = (built["parts"] as Array[SkinnedFlexbody])[i]
        var mesh_box: AABB = AABB(part.rest_vertices[0], Vector3.ZERO)
        for vertex: Vector3 in part.rest_vertices:
            mesh_box = mesh_box.expand(vertex)
        var forset: PackedInt32Array = truck.flexbodies[i]["forset"] as PackedInt32Array
        var node_bounds: AABB = AABB(truck.nodes[forset[0]], Vector3.ZERO)
        for id: int in forset:
            node_bounds = node_bounds.expand(truck.nodes[id])
        print("  %-22s mesh y %6.2f..%6.2f  nodes y %6.2f..%6.2f" % [
            part.mesh_instance.name, mesh_box.position.y, mesh_box.end.y,
            node_bounds.position.y, node_bounds.end.y
        ])
    print("-- part bounds in local space, top face first --")
    var rows: Array[Dictionary] = []
    for part: SkinnedFlexbody in built["parts"] as Array[SkinnedFlexbody]:
        var box: AABB = AABB(part.rest_vertices[0], Vector3.ZERO)
        for vertex: Vector3 in part.rest_vertices:
            box = box.expand(vertex)
        box = AABB(rig_to_local * box.position, box.size)
        rows.append({"name": part.mesh_instance.name, "box": box})
    rows.sort_custom(
        func(a: Dictionary, b: Dictionary) -> bool:
            return (a["box"] as AABB).end.y > (b["box"] as AABB).end.y
    )
    for row: Dictionary in rows:
        var box: AABB = row["box"] as AABB
        print("  %-22s y %6.2f .. %6.2f" % [row["name"], box.position.y, box.end.y])
    quit(0)
