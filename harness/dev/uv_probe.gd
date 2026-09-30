extends SceneTree
## Reports where a mesh's UVs land in its texture, and how bright that region is.
##
##   godot --path game --headless --script res://harness/dev/uv_probe.gd -- <mesh> <texture.dds>
##
## Written because comparing two renders by eye cannot settle which UV convention is
## correct, and a wrong guess here makes every later material judgement wrong.


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    var mesh_reader: RefCounted = ClassDB.instantiate("OgreMeshReader") as RefCounted
    var dds_reader: RefCounted = ClassDB.instantiate("DdsReader") as RefCounted
    var texture: Dictionary = dds_reader.read_file(argv[1])
    var image: Image = Image.create_from_data(
        int(texture["width"]), int(texture["height"]), false,
        int(texture["format"]) as Image.Format, texture["data"] as PackedByteArray
    )
    var result: Dictionary = mesh_reader.read_file(argv[0])
    for submesh: Dictionary in result["submeshes"] as Array:
        var uvs: PackedVector2Array = submesh["uvs"] as PackedVector2Array
        if uvs.is_empty():
            continue
        var min_uv: Vector2 = uvs[0]
        var max_uv: Vector2 = uvs[0]
        for uv: Vector2 in uvs:
            min_uv = min_uv.min(uv)
            max_uv = max_uv.max(uv)
        print(
            "%s: uv %.3f,%.3f .. %.3f,%.3f  mean_luma direct=%.3f flipped=%.3f"
            % [
                argv[0].get_file(), min_uv.x, min_uv.y, max_uv.x, max_uv.y,
                _mean_luma(image, uvs, false), _mean_luma(image, uvs, true)
            ]
        )
    quit(0)


func _mean_luma(image: Image, uvs: PackedVector2Array, flip: bool) -> float:
    var total: float = 0.0
    var count: int = 0
    var size: Vector2i = image.get_size()
    for i: int in range(0, uvs.size(), 7):
        var uv: Vector2 = uvs[i]
        var v: float = 1.0 - uv.y if flip else uv.y
        var x: int = clampi(int(uv.x * float(size.x)), 0, size.x - 1)
        var y: int = clampi(int(v * float(size.y)), 0, size.y - 1)
        total += image.get_pixel(x, y).get_luminance()
        count += 1
    return 0.0 if count == 0 else total / float(count)
