extends SceneTree
## Reports whether Terrain3D loaded and which of the interfaces this project needs it has.
##
##   godot --path game --headless --script res://tools/terrain3d_probe.gd


const NEEDED_CLASSES: Array[String] = [
    "Terrain3D", "Terrain3DData", "Terrain3DMaterial", "Terrain3DAssets", "Terrain3DInstancer",
]
## The height-query interface the collision bridge is built on, and the import entry point
## tools/import_dem.gd needs.
const NEEDED_METHODS: Dictionary = {
    "Terrain3DData": ["get_height", "get_normal", "import_images", "get_mesh_vertex"],
    "Terrain3D": ["set_collision_mode", "get_data", "set_material", "change_region_size"],
}


func _initialize() -> void:
    var missing: PackedStringArray = PackedStringArray()
    for name: String in NEEDED_CLASSES:
        if ClassDB.class_exists(name):
            print("class %s: present" % name)
        else:
            missing.append(name)
            print("class %s: MISSING" % name)
    for name: String in NEEDED_METHODS.keys():
        if not ClassDB.class_exists(name):
            continue
        for method: String in NEEDED_METHODS[name] as Array:
            if ClassDB.class_has_method(name, method):
                print("  %s.%s: present" % [name, method])
            else:
                missing.append("%s.%s" % [name, method])
                print("  %s.%s: MISSING" % [name, method])

    if ClassDB.class_exists("Terrain3D"):
        var terrain: Object = ClassDB.instantiate("Terrain3D")
        print("instantiated Terrain3D: %s" % terrain)
        # Collision mode Disabled is the whole integration premise: Rigs of Rods' own
        # collision stays authoritative and Godot physics never touches the terrain.
        for value: int in [0, 1, 2]:
            terrain.set("collision_mode", value)
            print("  collision_mode %d -> %s" % [value, terrain.get("collision_mode")])
        var data: Object = terrain.get("data")
        print("  data: %s" % data)
        if data != null:
            print("  get_height at origin: %s" % data.call("get_height", Vector3.ZERO))
    print("Godot %s" % Engine.get_version_info()["string"])
    print("missing: %s" % ("none" if missing.is_empty() else ", ".join(missing)))
    quit(0 if missing.is_empty() else 1)
