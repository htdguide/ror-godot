class_name VehicleSession
extends RefCounted
## Loading a vehicle into a running session, for `--vehicle` and for an ad-hoc shot.
##
## Split out of `Harness` when that file went over the source cap. It is a seam rather than a
## shelf: nothing here is part of the run loop, and the one thing it needs from the harness — the
## world to put the vehicle in — is passed rather than reached for.



static func load_into(harness: Node, spec: String) -> String:
    var parts: PackedStringArray = spec.split(":")
    if parts.size() != 2:
        return "expected --vehicle <mod dir>:<truck file>, got '%s'" % spec
    var mod_dir: String = parts[0]
    if not mod_dir.is_absolute_path():
        mod_dir = SourceScan.repo_root().path_join(mod_dir)
    # The blockout scale props exist to give an empty frame something to measure. With a
    # vehicle loaded they are just obstacles for it to sit inside.
    for prop: Node in harness.world.get_children():
        if str(prop.name).begins_with("Box") or str(prop.name) == "Sphere":
            prop.queue_free()

    var built: Dictionary = VehicleBuilder.build(mod_dir, parts[1])
    if (built.get("error", "") as String) != "":
        return built["error"] as String
    var root: Node3D = built["root"] as Node3D
    harness.world.add_child(root)
    var bounds: AABB = VehicleBuilder.world_bounds(root)
    # Stand it on the ground, where a person expects to find it. A driving session skips
    # this: the solver spawns the rig above the ground itself and every pose after that
    # carries the rig's own position, so shifting it here would offset it twice.
    if not harness.args.has_flag("play"):
        root.position += Vector3(
            -bounds.get_center().x, -bounds.position.y, -bounds.get_center().z
        )
    harness.vehicle = built
    print("HARNESS_VEHICLE " + JSON.stringify({
        "parts": int(built["built"]), "wheels": int(built["wheels"]),
        "size": "%.2f x %.2f x %.2f" % [bounds.size.x, bounds.size.y, bounds.size.z],
    }))
    return ""
