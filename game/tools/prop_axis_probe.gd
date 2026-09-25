extends SceneTree
## Reports which way a prop's mesh faces, and where its rake puts it.


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    var reader: RefCounted = ClassDB.instantiate("OgreMeshReader") as RefCounted
    var result: Dictionary = reader.read_file(argv[0].path_join(argv[1]))
    var box: AABB = AABB()
    var started: bool = false
    for submesh: Dictionary in result["submeshes"] as Array:
        for vertex: Vector3 in submesh["positions"] as PackedVector3Array:
            box = AABB(vertex, Vector3.ZERO) if not started else box.expand(vertex)
            started = true
    print("mesh bounds  pos %v size %v" % [box.position, box.size])
    var thin: int = 0
    for axis: int in 3:
        if box.size[axis] < box.size[thin]:
            thin = axis
    print("thinnest axis %s -> the column runs along it" % ["X", "Y", "Z"][thin])

    var truck: TruckParser = TruckParser.new()
    truck.parse_file(argv[0].path_join(argv[2]))
    for entry: Dictionary in truck.props:
        if (entry["steering_mesh"] as String).is_empty():
            continue
        var dash: Transform3D = FlexbodyBinder.placement(truck.nodes, entry)
        var face: Vector3 = Vector3.ZERO
        face[thin] = 1.0
        print("dashboard basis %s" % dash.basis)
        for rake: float in [-59.0, -31.0, 0.0, 59.0, 121.0, 149.0]:
            var turned: Basis = dash.basis * Basis.from_euler(
                Vector3(deg_to_rad(rake), 0.0, 0.0), PlacementRows.PROP_EULER_ORDER
            )
            var normal: Vector3 = (turned * face).normalized()
            # Rig space: -X is forward on this vehicle, +Y is up. A driver sits behind the
            # wheel, so the face should point backwards (+X) and upwards (+Y).
            print("  rake %+7.1f deg -> face %+.2v   back %+.2f  up %+.2f" % [
                rake, normal, normal.x, normal.y
            ])
    quit(0)
