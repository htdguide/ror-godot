extends SceneTree
## Checks whether a mesh's stored normals point outward.
##
## Winding controls which face is culled; normals control lighting and reflection. They
## are separate streams and can disagree. For a roughly closed shell, a vertex normal
## should point away from the mesh's centre — if most of them point inward, every surface
## is lit from the wrong side.


func _initialize() -> void:
    var reader: RefCounted = ClassDB.instantiate("OgreMeshReader") as RefCounted
    for path: String in OS.get_cmdline_user_args():
        var result: Dictionary = reader.read_file(path)
        if (result.get("error", "") as String) != "":
            print("%s: %s" % [path.get_file(), result["error"]])
            continue
        for submesh: Dictionary in result["submeshes"] as Array:
            var positions: PackedVector3Array = submesh["positions"] as PackedVector3Array
            var normals: PackedVector3Array = submesh["normals"] as PackedVector3Array
            if positions.is_empty() or normals.size() != positions.size():
                continue
            var centre: Vector3 = Vector3.ZERO
            for position: Vector3 in positions:
                centre += position
            centre /= float(positions.size())

            var outward: int = 0
            var inward: int = 0
            var winding_agrees: int = 0
            var winding_disagrees: int = 0
            for i: int in positions.size():
                var to_surface: Vector3 = positions[i] - centre
                if to_surface.length_squared() < 0.000001:
                    continue
                if normals[i].dot(to_surface.normalized()) >= 0.0:
                    outward += 1
                else:
                    inward += 1
            # And whether the triangle's own winding agrees with the stored normal.
            var indices: PackedInt32Array = submesh["indices"] as PackedInt32Array
            for i: int in range(0, indices.size() - 2, 3):
                var a: Vector3 = positions[indices[i]]
                var b: Vector3 = positions[indices[i + 1]]
                var c: Vector3 = positions[indices[i + 2]]
                var face: Vector3 = (b - a).cross(c - a)
                if face.length_squared() < 0.000000001:
                    continue
                var stored: Vector3 = normals[indices[i]]
                if face.normalized().dot(stored) >= 0.0:
                    winding_agrees += 1
                else:
                    winding_disagrees += 1
            print(
                "%-22s normals outward %d inward %d | winding agrees %d disagrees %d"
                % [path.get_file(), outward, inward, winding_agrees, winding_disagrees]
            )
    quit(0)
