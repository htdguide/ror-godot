extends SceneTree
## The UV range each submesh of a mesh covers, in the texture-coordinate set the reader keeps.
##
## A submesh whose UVs span most of 0..1 is reading an atlas meant for a different texture.


func _initialize() -> void:
    var reader: RefCounted = ClassDB.instantiate("OgreMeshReader") as RefCounted
    var result: Dictionary = reader.read_file(OS.get_cmdline_user_args()[0])
    if (result.get("error", "") as String) != "":
        printerr(result["error"])
        quit(1)
        return
    var shared: PackedVector2Array = result.get("uvs", PackedVector2Array()) as PackedVector2Array
    for submesh: Dictionary in result["submeshes"] as Array:
        var uvs: PackedVector2Array = submesh.get("uvs", shared) as PackedVector2Array
        var indices: PackedInt32Array = submesh["indices"] as PackedInt32Array
        var low: Vector2 = Vector2(INF, INF)
        var high: Vector2 = Vector2(-INF, -INF)
        for index: int in indices:
            if index < uvs.size():
                low = low.min(uvs[index])
                high = high.max(uvs[index])
        print("%-28s %5d indices  u %.3f..%.3f  v %.3f..%.3f" % [
            submesh["material"], indices.size(), low.x, high.x, low.y, high.y])
    quit(0)
