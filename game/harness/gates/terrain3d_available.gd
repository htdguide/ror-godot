extends GateBase
## Terrain3D is installed, loads on this engine, and still has the interfaces this project
## builds on.
##
## It is a C++ GDExtension pinned at a release built for Godot 4.4 to 4.6, and this project
## runs 4.7. GDExtension is forward compatible, which is the same argument that lets our own
## bridge build against godot-cpp 4.5 and load on 4.7 — but "should be compatible" is a
## claim, and this is the measurement. An addon that fails to load registers no classes at
## all, which is silent until something tries to use one.
##
## The interfaces checked are the ones the integration actually depends on, per PLAN §0.6:
## the height and normal queries that Rigs of Rods' collision is driven through, the image
## import that turns a DEM into terrain from the command line, and a collision mode that can
## be turned off so Godot physics never touches the ground the solver owns.

const ADDON_PATH: String = "res://addons/terrain_3d/terrain.gdextension"
const NEEDED_CLASSES: Array[String] = [
    "Terrain3D", "Terrain3DData", "Terrain3DMaterial", "Terrain3DAssets", "Terrain3DInstancer",
]
## Class name -> the methods this project calls on it.
const NEEDED_METHODS: Dictionary = {
    "Terrain3DData": ["get_height", "get_normal", "import_images", "get_mesh_vertex"],
    "Terrain3D": ["set_collision_mode", "get_data", "set_material", "change_region_size"],
}
## Collision has to be capable of being off. The name is checked rather than the number,
## because the number is what a future release is free to change.
const DISABLED_MODE_NAME: String = "Disabled"
const DISABLED_MODE_VALUE: int = 0


static func meta() -> Dictionary:
    return {
        "name": "terrain3d_available",
        "proves": "the pinned Terrain3D build loads on this engine and still exposes the height query, image import and disableable collision the integration is built on",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "%d classes and %d methods present; collision mode %d is named '%s'"
            % [
                NEEDED_CLASSES.size(),
                (NEEDED_METHODS["Terrain3DData"] as Array).size()
                + (NEEDED_METHODS["Terrain3D"] as Array).size(),
                DISABLED_MODE_VALUE,
                DISABLED_MODE_NAME,
            ]
        ),
        "why": (
            "the addon is pinned at a release built for an older engine than this project"
            + " runs, and an extension that fails to load registers nothing rather than"
            + " raising anything. Checking the specific methods, rather than merely that"
            + " the addon is present, is what makes an upstream rename fail here instead of"
            + " somewhere further downstream."
        ),
        "budget_s": 15.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    if not ResourceLoader.exists(ADDON_PATH) and not FileAccess.file_exists(ADDON_PATH):
        return ok("skipped: Terrain3D is not installed. Run tools/build_terrain3d.sh", 0)

    var missing: PackedStringArray = PackedStringArray()
    for name: String in NEEDED_CLASSES:
        if not ClassDB.class_exists(name):
            missing.append("class %s" % name)
    if missing.size() == NEEDED_CLASSES.size():
        return fail(
            "the addon is installed but registered no classes: the extension did not load."
            + " Rebuild it with tools/build_terrain3d.sh"
        )
    for name: String in NEEDED_METHODS.keys():
        if not ClassDB.class_exists(name):
            continue
        for method: String in NEEDED_METHODS[name] as Array:
            if not ClassDB.class_has_method(name, method):
                missing.append("%s.%s" % [name, method])
    if missing.size() > 0:
        return fail(
            "the pinned Terrain3D build is missing %s" % ", ".join(missing), missing.size()
        )

    var modes: PackedStringArray = _collision_modes()
    if modes.is_empty():
        return fail("Terrain3D exposes no collision_mode property to turn collision off with")
    if DISABLED_MODE_VALUE >= modes.size() or modes[DISABLED_MODE_VALUE] != DISABLED_MODE_NAME:
        return fail(
            "collision mode %d is '%s', not '%s': Godot physics cannot be kept off the"
            % [
                DISABLED_MODE_VALUE,
                modes[DISABLED_MODE_VALUE] if DISABLED_MODE_VALUE < modes.size() else "absent",
                DISABLED_MODE_NAME,
            ]
            + " terrain by that number any more (modes: %s)" % ", ".join(modes)
        )
    return ok(
        "Terrain3D loaded on Godot %s: %d classes, every needed method, collision modes %s"
        % [
            Engine.get_version_info()["string"],
            NEEDED_CLASSES.size(),
            ", ".join(modes),
        ],
        0
    )


## The names Terrain3D gives its collision modes, in order, read from the property's own
## enum hint rather than assumed.
func _collision_modes() -> PackedStringArray:
    for property: Dictionary in ClassDB.class_get_property_list("Terrain3D", true):
        if (property["name"] as String) == "collision_mode":
            return (property["hint_string"] as String).split(",")
    return PackedStringArray()
