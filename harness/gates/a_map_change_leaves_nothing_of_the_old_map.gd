extends GateBase
## Changing the map removes everything the old map built, the sea included.
##
## A session changed from La Paz to Starling and kept La Paz's sea: the removal list in the
## session named the objects, the roads and the trees, and the water had been added after the
## list was written. The list is one constant now (`PlayMap.MAP_NODES`), and this holds it
## against the builders' own node names rather than against itself: a world is given one child
## named as each builder names its root — read from the builders' source, not from the constant
## — plus the things a map does not own, and after `PlayMap.clear` only those are left.

const BUILDERS: Dictionary = {
    "game/terrain/ror_objects.gd": "RorObjects",
    "game/terrain/ror_procedural_road.gd": "RorProceduralRoads",
    "game/terrain/ror_trees.gd": "RorTrees",
    "game/terrain/ror_water.gd": "RorWater",
    "game/terrain/terrain_world.gd": "Terrain",
}
const NOT_A_MAPS: PackedStringArray = ["WorldEnvironment", "Sun", "Fill", "Ground", "Vehicle"]


static func meta() -> Dictionary:
    return {
        "name": "a_map_change_leaves_nothing_of_the_old_map",
        "proves": "every node a terrain's builders parent their work under is removed by a map change, and nothing that is not a map's is",
        "builds_on": ["the_build_profile_decides_where_content_lives"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "%d builder root names, each found in its builder's source, each removed; %d other nodes kept" % [BUILDERS.size(), NOT_A_MAPS.size()],
        "why": (
            "a session kept the old map's sea through a map change because the removal list"
            + " was written before the sea was; a list checked against the builders' own names"
            + " cannot be stale that way."
        ),
        "budget_s": 10.0,
        "needs_gpu": false,
        "milestone": "M2",
    }


func run(_harness: Node) -> Dictionary:
    var problems: PackedStringArray = PackedStringArray()
    for file: String in BUILDERS:
        var text: String = FileAccess.get_file_as_string(SourceScan.repo_root().path_join(file))
        var wanted: String = BUILDERS[file] as String
        if not text.contains('"%s"' % wanted):
            problems.append("%s does not name its root \"%s\"" % [file, wanted])
    var world: Node3D = Node3D.new()
    var mapped: PackedStringArray = PackedStringArray()
    for file: String in BUILDERS:
        var child: Node3D = Node3D.new()
        child.name = BUILDERS[file] as String
        world.add_child(child)
        mapped.append(child.name)
    for name: String in NOT_A_MAPS:
        var kept: Node3D = Node3D.new()
        kept.name = name
        world.add_child(kept)
    var gone: int = PlayMap.clear(world)
    var left: PackedStringArray = PackedStringArray()
    for child: Node in world.get_children():
        left.append(child.name)
    for name: String in mapped:
        if left.has(name):
            problems.append("%s survived the change" % name)
    if left.size() != NOT_A_MAPS.size():
        problems.append("%d nodes left where %d were not the map's: %s" % [left.size(), NOT_A_MAPS.size(), ", ".join(left)])
    for name: String in NOT_A_MAPS:
        if not left.has(name):
            problems.append("%s is not the map's and was removed" % name)
    world.free()
    if not problems.is_empty():
        return fail("; ".join(problems), problems.size())
    return ok("%d nodes of the old map removed (%d builder roots), %d kept" % [gone, BUILDERS.size(), left.size()], gone)
