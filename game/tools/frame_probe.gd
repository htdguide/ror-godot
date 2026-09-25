extends SceneTree
## Prints a vehicle's actor frame, so claims about it can be checked rather than assumed.
##
##   godot --path game --headless --script res://tools/frame_probe.gd -- <truck file>


func _initialize() -> void:
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_file(OS.get_cmdline_user_args()[0])
    if error != "":
        printerr(error)
        quit(1)
        return
    var frame: Transform3D = ActorFrame.of(truck.nodes, truck.camera_nodes)
    print("camera_nodes=%s" % truck.camera_nodes)
    print("origin=%s" % frame.origin)
    print("basis x=%s y=%s z=%s det=%.4f" % [
        frame.basis.x, frame.basis.y, frame.basis.z, frame.basis.determinant()
    ])
    quit(0)
