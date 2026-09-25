extends SceneTree
## Reports whether a vehicle's flexbody placements mirror the mesh.
##
## A basis with a negative determinant reverses triangle winding, so every surface faces
## the wrong way: culled from the front, drawn from behind.


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_file(argv[0].path_join(argv[1]))
    if error != "":
        printerr(error)
        quit(1)
        return
    var mirrored: int = 0
    for entry: Dictionary in truck.flexbodies:
        var placement: Transform3D = FlexbodyBinder.placement(truck.nodes, entry)
        var determinant: float = placement.basis.determinant()
        if determinant < 0.0:
            mirrored += 1
        print("%-24s det %+.4f scale %s" % [
            entry["mesh"], determinant, placement.basis.get_scale()
        ])
    print("mirrored placements: %d of %d" % [mirrored, truck.flexbodies.size()])
    quit(0)
