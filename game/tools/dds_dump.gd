extends SceneTree
## Saves a DDS texture as PNG so it can be looked at.
##
##   godot --path game --headless --script res://tools/dds_dump.gd -- <in.dds> <out.png>


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    if argv.size() < 2:
        printerr("dds_dump: expected <in.dds> <out.png>")
        quit(2)
        return
    var reader: RefCounted = ClassDB.instantiate("DdsReader") as RefCounted
    var result: Dictionary = reader.read_file(argv[0])
    if (result.get("error", "") as String) != "":
        printerr("dds_dump: " + (result["error"] as String))
        quit(1)
        return
    var image: Image = Image.create_from_data(
        int(result["width"]), int(result["height"]), false,
        int(result["format"]) as Image.Format, result["data"] as PackedByteArray
    )
    image.resize(512, 512, Image.INTERPOLATE_BILINEAR)
    image.save_png(argv[1])
    print("dds_dump: %dx%d format=%d -> %s" % [int(result["width"]), int(result["height"]), int(result["format"]), argv[1]])
    quit(0)
