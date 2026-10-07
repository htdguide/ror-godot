extends SceneTree
## Whether a vehicle's flexbodies are actually skinned, and where their posed bounds land.


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    var built: Dictionary = VehicleBuilder.build(argv[0], argv[1])
    if (built.get("error", "") as String) != "":
        printerr(built["error"])
        quit(1)
        return
    var truck: TruckParser = built["truck"] as TruckParser
    print("actor %s" % (built["actor"] as Transform3D))
    for part: SkinnedFlexbody in built["parts"] as Array[SkinnedFlexbody]:
        var rest: AABB = AABB()
        if part.rest_vertices.size() > 0:
            rest = AABB(part.rest_vertices[0], Vector3.ZERO)
            for v: Vector3 in part.rest_vertices:
                rest = rest.expand(v)
        print("%-26s bones %3d  skeleton %s  skin %s  rest centre %v  drawn centre %v" % [
            part.mesh_instance.name, part.triads.size(),
            "valid" if part.skeleton_rid.is_valid() else "INVALID",
            "set" if part.mesh_instance.skeleton != NodePath() else "none",
            rest.get_center(), part.mesh_instance.get_aabb().get_center()])
    quit(0)
