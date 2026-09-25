extends SceneTree
## Command-line front end for ImgDiff.
##
##   godot --path game --headless --script res://tools/imgdiff.gd -- A.png B.png [tolerance]
##
## Headless renders nothing, but it loads and processes images perfectly well, so the
## differ needs no second toolchain and no Python dependency.


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    if argv.size() < 2:
        printerr("imgdiff: expected two image paths")
        quit(2)
        return
    var tolerance: float = ImgDiff.DEFAULT_TOLERANCE if argv.size() < 3 else argv[2].to_float()
    var result: Dictionary = ImgDiff.compare(argv[0], argv[1], tolerance)
    print("IMGDIFF " + JSON.stringify(result))
    quit(0 if result.get("pass", false) else 1)
