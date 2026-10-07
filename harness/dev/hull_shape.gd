extends SceneTree
## The triangles of one object's collision hull, in its own frame, and whether it is closed.
##
## A closed hull has every edge shared by exactly two triangles. An open one has edges used once,
## and a node crosses those gaps without ever meeting a face.


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    var loaded: Dictionary = RorTerrainLibrary.load_named(argv[0])
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain
    var kept: Array = []
    for tri: Dictionary in RorObjectCollision.triangles(terrain):
        if (tri["name"] as String) != argv[1]:
            continue
        kept.append(tri)
        if kept.size() >= 24:
            break
    var edges: Dictionary = {}
    for tri: Dictionary in kept:
        for pair: Array in [["a", "b"], ["b", "c"], ["c", "a"]]:
            var one: Vector3 = tri[pair[0]] as Vector3
            var two: Vector3 = tri[pair[1]] as Vector3
            var key: String = "%v|%v" % [one.min(two).snappedf(0.001), one.max(two).snappedf(0.001)]
            edges[key] = int(edges.get(key, 0)) + 1
    var once: int = 0
    for key: String in edges.keys():
        if int(edges[key]) == 1:
            once += 1
    print("%s: %d triangles shown, %d distinct edges, %d used by only one triangle" % [
        argv[1], kept.size(), edges.size(), once])
    print("closed" if once == 0 else "OPEN: a node crosses those %d edges without meeting a face" % once)
    for i: int in mini(kept.size(), 8):
        var tri: Dictionary = kept[i]
        var a: Vector3 = tri["a"] as Vector3
        var n: Vector3 = ((tri["b"] as Vector3) - a).cross((tri["c"] as Vector3) - a).normalized()
        print("  tri %d normal %v  area-ish %.3f" % [i, n, a.distance_to(tri["b"] as Vector3)])
    quit(0)
