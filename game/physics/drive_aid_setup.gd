class_name DriveAidSetup
extends RefCounted
## Hands the solver what its wheel step reads besides torque: the vehicle's forward, and the
## traction control and anti-lock brake its file states (`DriveAids`).
##
## The forward is upstream's `getDirection`: from the main camera's `dir` node to its `pos` node.
## A file with no cameras, or whose camera `dir` is node 0, gets upstream's fallback from
## `ActorSpawner`: `pos` stays node 0, `dir` becomes the node furthest from it, and the direction is
## turned about up by that node's angle in the ground plane so it still points forward-ish.


static func hand_to(solver: RefCounted, truck: TruckParser) -> void:
    var pos: int = int(truck.camera_nodes.get("centre", 0))
    var dir: int = int(truck.camera_nodes.get("dir", 0))
    var yaw: float = 0.0
    if dir == 0 and truck.nodes.size() > 1:
        var reference: Vector3 = truck.nodes[pos]
        var furthest: float = 0.0
        for i: int in truck.nodes.size():
            var distance: float = truck.nodes[i].distance_squared_to(reference)
            if distance > furthest:
                furthest = distance
                dir = i
        var d: Vector3 = truck.nodes[dir] - reference
        yaw = atan2(d.dot(Vector3(0.0, 0.0, 1.0)), d.dot(Vector3(1.0, 0.0, 0.0)))
    solver.set_direction_nodes(pos, dir, yaw)
    # The roll node upstream's `GetCameraRoll` reads, node 0 without a camera; and `speedoMax`.
    solver.set_camera_roll_node(int(truck.camera_nodes.get("roll", 0)))
    solver.set_speedo_max(float(truck.drivetrain.get("speedo_max", 140.0)))
    for kind: String in ["tc", "abs"]:
        var aid: Dictionary = truck.drivetrain.get(kind, {}) as Dictionary
        if not aid.is_empty():
            solver.set_drive_aid(kind, aid["on"] as bool, aid["toggle"] as bool, aid["ratio"] as float,
                    aid["pulse_time"] as float, float(aid.get("min_speed", 0.0)))
    var cruise: Dictionary = truck.drivetrain.get("cruise", {}) as Dictionary
    if not cruise.is_empty():
        solver.set_cruise_control(cruise["lower_limit"], cruise["can_brake"])
