extends SceneTree
## Reports where a vehicle's geometry sits relative to where its nodes sit.
##
##   godot --path game --headless --script res://harness/dev/stance_probe.gd -- <mod dir> <truck>
##
## Ground contact acts on nodes; a person looks at the tyres. When the two disagree the
## vehicle is drawn sunk into the ground by exactly that disagreement.


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

    var lowest_node: float = truck.nodes[0].y
    for node: Vector3 in truck.nodes:
        lowest_node = minf(lowest_node, node.y)
    var bounds: AABB = VehicleBuilder.world_bounds(root)
    print("lowest node        %.3f m" % lowest_node)
    print("lowest geometry    %.3f m" % bounds.position.y)
    print("gap                %.3f m" % (lowest_node - bounds.position.y))
    for wheel: Dictionary in truck.wheels:
        print("wheel tyre radius  %.3f m  rim %.3f m  nodes %d,%d" % [
            wheel["tyre_radius"], wheel["rim_radius"], wheel["node_a"], wheel["node_b"]
        ])
    quit(0)
