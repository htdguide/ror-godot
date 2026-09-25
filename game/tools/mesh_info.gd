extends SceneTree
## Prints what the OGRE mesh reader sees in a file.
##
##   godot --path game --headless --script res://tools/mesh_info.gd -- <mesh> [<mesh>...]
##
## Headless is fine here: reading geometry renders nothing.


func _initialize() -> void:
    var reader: RefCounted = ClassDB.instantiate("OgreMeshReader") as RefCounted
    if reader == null:
        printerr("OgreMeshReader is not registered: build the GDExtension first")
        quit(2)
        return
    for path: String in OS.get_cmdline_user_args():
        var result: Dictionary = reader.read_file(path)
        if (result.get("error", "") as String) != "":
            print("%s: ERROR %s" % [path.get_file(), result["error"]])
            continue
        var submeshes: Array = result["submeshes"] as Array
        print(
            "%s  version=%s shared_vertices=%d submeshes=%d"
            % [path.get_file(), result["version"], int(result["shared_vertex_count"]), submeshes.size()]
        )
        for i: int in submeshes.size():
            var submesh: Dictionary = submeshes[i]
            var positions: PackedVector3Array = submesh["positions"] as PackedVector3Array
            var box: AABB = AABB()
            for v: int in positions.size():
                box = AABB(positions[0], Vector3.ZERO) if v == 0 else box.expand(positions[v])
            print(
                "  [%d] material='%s' shared=%s vertices=%d indices=%d size=%.3f x %.3f x %.3f"
                % [
                    i, submesh["material"], submesh["uses_shared_vertices"],
                    positions.size(), (submesh["indices"] as PackedInt32Array).size(),
                    box.size.x, box.size.y, box.size.z
                ]
            )
    quit(0)
