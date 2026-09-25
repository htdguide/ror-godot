extends SceneTree
## Prints where each of a vehicle's parts ends up, relative to the vehicle's own bounds.
##
##   godot --path game --headless --script res://tools/part_positions.gd -- <mod dir> <truck>


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    var built: Dictionary = VehicleBuilder.build(argv[0], argv[1])
    if (built.get("error", "") as String) != "":
        printerr(built["error"])
        quit(1)
        return
    var truck: TruckParser = built["truck"] as TruckParser
    var parts: Array[SkinnedFlexbody] = built["parts"] as Array[SkinnedFlexbody]

    var whole: AABB = AABB()
    var started: bool = false
    var rows: Array = []
    for part: SkinnedFlexbody in parts:
        var box: AABB = AABB(part.rest_vertices[0], Vector3.ZERO)
        for vertex: Vector3 in part.rest_vertices:
            box = box.expand(vertex)
        whole = box if not started else whole.merge(box)
        started = true
        rows.append([part.mesh_instance.name, box])
    print("vehicle rig bounds: position %s size %s" % [whole.position, whole.size])
    for row: Array in rows:
        var box: AABB = row[1] as AABB
        var centre: Vector3 = box.position + box.size * 0.5
        # Where the part sits along the rig's own length, 0 at one end and 1 at the other.
        var along: float = (centre.x - whole.position.x) / maxf(whole.size.x, 0.001)
        print("%-22s centre %-28s size %-26s along_x %.2f" % [row[0], centre, box.size, along])
    quit(0)
