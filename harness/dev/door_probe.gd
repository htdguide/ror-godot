extends SceneTree
## Compares a flexbody's placed rest geometry with the nodes it is bound to.
##
## A part that renders in the wrong place is either placed wrong or authored wrong, and
## the nodes it is skinned to say which: they are where the rig believes the part is.


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    var built: Dictionary = VehicleBuilder.build(argv[0], argv[1])
    if (built.get("error", "") as String) != "":
        printerr(built["error"])
        quit(1)
        return
    var truck: TruckParser = built["truck"] as TruckParser
    var parts: Array[SkinnedFlexbody] = built["parts"] as Array[SkinnedFlexbody]
    for i: int in parts.size():
        var part: SkinnedFlexbody = parts[i]
        var wanted: String = argv[2] if argv.size() > 2 else ""
        if wanted != "" and not str(part.mesh_instance.name).to_lower().contains(wanted):
            continue
        var mesh_box: AABB = AABB(part.rest_vertices[0], Vector3.ZERO)
        for vertex: Vector3 in part.rest_vertices:
            mesh_box = mesh_box.expand(vertex)
        var forset: PackedInt32Array = truck.flexbodies[i]["forset"] as PackedInt32Array
        var node_box: AABB = AABB(truck.nodes[forset[0]], Vector3.ZERO)
        for id: int in forset:
            node_box = node_box.expand(truck.nodes[id])
        print("%s  forset %d nodes" % [part.mesh_instance.name, forset.size()])
        print("   mesh  %+.2v .. %+.2v" % [mesh_box.position, mesh_box.end])
        print("   nodes %+.2v .. %+.2v" % [node_box.position, node_box.end])
        print("   mesh centre %+.2v   nodes centre %+.2v   apart %.3f m" % [
            mesh_box.get_center(), node_box.get_center(),
            mesh_box.get_center().distance_to(node_box.get_center())
        ])
    quit(0)
