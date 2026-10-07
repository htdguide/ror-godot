extends SceneTree
## Whether each driven wheel's reaction torque has an arm to push against.
##
## Upstream drives a wheel by forcing its tread round and pushing back along the suspension arm,
## between the `reference_arm_node` the row names and the axle node nearest it. It abandons the
## reaction when the arm is too nearly along the axle to carry one — `offset * 2 < rlen`, which
## upstream's own source marks as a TODO. A driven wheel with no reaction has nothing holding it
## against its own torque.


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    var truck: TruckParser = TruckParser.new()
    if truck.parse_file(SourceScan.repo_root().path_join(argv[0]).path_join(argv[1])) != "":
        quit(1)
        return
    for index: int in truck.wheels.size():
        var wheel: Dictionary = truck.wheels[index]
        var a: int = wheel["node1"] as int
        var b: int = wheel["node2"] as int
        var arm: int = wheel["arm_node"] as int
        if arm < 0 or arm >= truck.nodes.size():
            print("wheel %d: arm node unresolved, no reaction at all" % index)
            continue
        # The axle node nearest the arm, which is what upstream attaches to.
        var near: int = a if truck.nodes[a].distance_to(truck.nodes[arm]) <= \
            truck.nodes[b].distance_to(truck.nodes[arm]) else b
        var axis: Vector3 = (truck.nodes[b] - truck.nodes[a]).normalized()
        var rradius: Vector3 = truck.nodes[arm] - truck.nodes[near]
        var radius: Vector3 = rradius - axis * rradius.dot(axis)
        var offset: float = (rradius - radius).length()
        var rlen: float = radius.length()
        print("wheel %d drive %d: arm %d, lever %.3f m, error arm %.3f m -> %s" % [
            index, wheel["propulsed"] as int, arm, rlen, offset,
            "reaction applied" if (rlen > 0.01 and offset * 2.0 < rlen) else "REACTION SKIPPED"])
    quit(0)
