extends SceneTree
## Dumps what Terrain3D's ground material actually is: its properties, and the shader code it
## generates. The starting point for M2's ground material, which replaces that shader.
##
##   godot --path . --headless --script res://harness/dev/terrain_material_probe.gd


var _terrain: Node3D = null
var _frames: int = 0


func _initialize() -> void:
    if not ClassDB.class_exists("Terrain3D"):
        print("Terrain3D is not installed. Run tools/build_terrain3d.sh")
        quit()
        return
    _terrain = ClassDB.instantiate("Terrain3D") as Node3D
    root.add_child(_terrain)


## A Terrain3D finishes building its subsystems only once it has been inside a World3D for a
## frame, so its material does not exist yet in `_initialize`.
func _process(_delta: float) -> bool:
    _frames += 1
    if _frames < 3:
        return false
    _report(_terrain)
    return true


func _report(terrain: Node3D) -> void:
    var material: Object = terrain.get("material")
    if material == null:
        print("the terrain has no material")
        return
    print("=== Terrain3DMaterial properties ===")
    for entry: Dictionary in material.get_property_list():
        var name: String = entry["name"] as String
        if name.begins_with("_") or (int(entry["usage"]) & PROPERTY_USAGE_EDITOR) == 0:
            continue
        var value: Variant = material.get(name)
        var shown: String = str(value)
        if shown.length() > 90:
            shown = "%s… (%d chars)" % [shown.substr(0, 90), shown.length()]
        print("  %-28s %s" % [name, shown])

    # Terrain3D generates its shader as a string in C++ and never hands it back as one: there is
    # no `get_shader_code`, only `get_shader_rid`. The code is reachable through the rendering
    # server, which is the only way to see what an override has to replace.
    var code: String = ""
    if material.has_method("get_shader_rid"):
        var rid: RID = material.call("get_shader_rid") as RID
        if rid.is_valid():
            code = RenderingServer.shader_get_code(rid)
    if code.is_empty():
        print("=== no shader code reachable ===")
        for method: Dictionary in material.get_method_list():
            if (method["name"] as String).to_lower().contains("shader"):
                print("  method: %s" % method["name"])
        return
    var out: String = "artifacts/terrain3d_generated.gdshader"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
    var handle: FileAccess = FileAccess.open("res://%s" % out, FileAccess.WRITE)
    if handle != null:
        handle.store_string(code)
        handle.close()
    print("=== shader code: %d lines -> %s ===" % [code.split("\n").size(), out])
