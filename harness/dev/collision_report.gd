extends SceneTree
## What a terrain's objects are solid as, against what it draws.
##
##   godot --path . --headless --script res://harness/dev/collision_report.gd -- <map>


func _initialize() -> void:
    var name: String = OS.get_cmdline_user_args()[0]
    var loaded: Dictionary = RorTerrainLibrary.load_named(name)
    if (loaded.get("error", "") as String) != "":
        printerr(loaded["error"])
        quit(1)
        return
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain
    var boxes: Array[Dictionary] = RorObjectCollision.boxes(terrain)
    var per_name: Dictionary = {}
    for box: Dictionary in boxes:
        var key: String = box.get("name", "?") as String
        per_name[key] = int(per_name.get(key, 0)) + 1
    var placed: Dictionary = {}
    for placement: Dictionary in RorObjects.placements(terrain):
        var key: String = placement["name"] as String
        placed[key] = int(placed.get(key, 0)) + 1
    var tris: Array[Dictionary] = RorObjectCollision.triangles(terrain)
    for tri: Dictionary in tris:
        var key: String = tri.get("name", "?") as String
        per_name[key] = int(per_name.get(key, 0)) + 1
    print("%s: %d placements of %d kinds, %d collision boxes, %d collision triangles" % [
        name, RorObjects.placements(terrain).size(), placed.size(), boxes.size(), tris.size()])
    var solid: int = 0
    var hollow: PackedStringArray = PackedStringArray()
    for key: String in placed.keys():
        if per_name.has(key):
            solid += 1
        else:
            hollow.append("%s x%d" % [key, int(placed[key])])
    print("  %d kinds are solid, %d are drawn with nothing to hit" % [solid, hollow.size()])
    for key: String in placed.keys():
        print("    %-28s placed %3d, boxes %d" % [
            key, int(placed[key]), int(per_name.get(key, 0))])
    hollow.sort()
    for i: int in mini(hollow.size(), 25):
        print("    %s" % hollow[i])
    # One placement in detail: where its boxes stand against where its mesh is drawn.
    var wanted: String = OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size() > 1 else ""
    if wanted != "":
        var shown: int = 0
        for box: Dictionary in boxes:
            if (box.get("name", "") as String) != wanted:
                continue
            var at: Transform3D = box["transform"] as Transform3D
            var half: Vector3 = box["half"] as Vector3
            var world: AABB = at * AABB(-half, half * 2.0)
            print("  box y %.2f..%.2f  x %.2f..%.2f  z %.2f..%.2f" % [
                world.position.y, world.end.y, world.position.x, world.end.x,
                world.position.z, world.end.z])
            shown += 1
            if shown >= 8:
                break
    quit(0)
