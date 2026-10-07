extends SceneTree
## What each declared material of a vehicle resolves to: its class and its first texture.


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    var truck: TruckParser = TruckParser.new()
    var failed: String = truck.parse_file(argv[0].path_join(argv[1]))
    if failed != "":
        printerr(failed)
        quit(1)
        return
    for name: String in truck.managed_materials.keys():
        var declared: Dictionary = truck.managed_materials[name] as Dictionary
        var classified: Dictionary = MaterialClass.classify(name, declared)
        print("%-30s effect %-22s class %-10s textures %s" % [
            name, declared["effect"], classified["class"], declared["textures"]])
    quit(0)
