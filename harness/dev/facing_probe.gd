extends SceneTree
## Reports whether each submesh's triangle winding agrees with its stored vertex normals.
##
##   godot --path game --headless --script res://harness/dev/facing_probe.gd -- <mesh> [<mesh>...]
##
## A triangle's geometric normal follows from the order of its three indices. The mesh also
## ships an authored normal per vertex. When the two disagree, one of them is inverted, and
## the visible result is the classic pair of faults: the surface is culled when looked at
## from outside, and it is lit as though the light came from behind it.
##
## This is a measurement, not a guess about OGRE's conventions, and it is per submesh
## because a single reversal applied to a whole file is only correct if every submesh in
## the file agrees.


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
        print(path.get_file())
        for i: int in (result["submeshes"] as Array).size():
            _report(i, (result["submeshes"] as Array)[i] as Dictionary)
    quit(0)


func _report(index: int, submesh: Dictionary) -> void:
    var positions: PackedVector3Array = submesh["positions"] as PackedVector3Array
    var normals: PackedVector3Array = submesh["normals"] as PackedVector3Array
    var indices: PackedInt32Array = submesh["indices"] as PackedInt32Array
    if normals.size() != positions.size():
        print("  [%d] %-16s no stored normals" % [index, submesh["material"]])
        return
    var centre: Vector3 = Vector3.ZERO
    for v: Vector3 in positions:
        centre += v
    centre /= maxf(float(positions.size()), 1.0)
    var agree: int = 0
    var disagree: int = 0
    var degenerate: int = 0
    var wound_outward: int = 0
    var authored_outward: int = 0
    for t: int in range(0, indices.size() - 2, 3):
        var a: Vector3 = positions[indices[t]]
        var b: Vector3 = positions[indices[t + 1]]
        var c: Vector3 = positions[indices[t + 2]]
        var geometric: Vector3 = (b - a).cross(c - a)
        if geometric.length_squared() < 1e-16:
            degenerate += 1
            continue
        var authored: Vector3 = normals[indices[t]] + normals[indices[t + 1]] + normals[indices[t + 2]]
        if geometric.normalized().dot(authored.normalized()) > 0.0:
            agree += 1
        else:
            disagree += 1
        # Independent of what the file claims: a shell's faces point away from its middle.
        var outward: Vector3 = (a + b + c) / 3.0 - centre
        if geometric.dot(outward) > 0.0:
            wound_outward += 1
        if authored.dot(outward) > 0.0:
            authored_outward += 1
    var total: int = agree + disagree
    print(
        "  [%d] %-16s tris=%d agree=%.0f%% wound_outward=%.0f%% authored_outward=%.0f%% degenerate=%d"
        % [
            index, submesh["material"], total,
            100.0 * agree / maxi(total, 1),
            100.0 * wound_outward / maxi(total, 1),
            100.0 * authored_outward / maxi(total, 1),
            degenerate
        ]
    )
