extends SceneTree
## The terrain's height at a world point, for checking an object stands where its collision does.


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    var loaded: Dictionary = RorTerrainLibrary.load_named(argv[0])
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain
    for i: int in range(1, argv.size(), 2):
        var x: float = argv[i].to_float()
        var z: float = argv[i + 1].to_float()
        print("ground at %.1f, %.1f = %.2f m" % [x, z, terrain.height_at(x, z)])
    quit(0)
