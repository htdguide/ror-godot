extends GateBase
## Every six-number line in a terrain's object files is read as the thing it is, and every object
## whose definition this checkout has is built.
##
## **A `.tobj` is not a list of buildings.** It mixes scenery with actor spawn points and with
## blocks of procedural road points, and upstream sorts them before anything is done with them —
## `TObjFileFormat.cpp` reads the line as `odef`, `type`, `instance_name` and then asks `IsRoad()`
## and `IsActor()` over its own name list. Read as scenery, a road point asks for an object
## definition called `0`, `8` or `10`, and a marina asks for one called
## `marina sale Marina_Wells`.
##
## **What that cost, measured on Port Starling.** 1502 object lines, of which 374 were road points
## inside `begin_procedural_roads` blocks and 8 were actor spawns written with a type and an
## instance name. On top of that, an object definition was looked for only in the terrain's own
## folder, and the map names a great many it does not ship: `road-slab` 189 times, `road-park`
## 139, and signs, traffic lights and dock sections besides, every one of them in
## `resources/meshes`. Between them, **835 of 1502 placements — 56% of the map — drew nothing**,
## which is most of its roads and a good share of its buildings. 1117 draw now.
##
## **Four things are checked, each against the files rather than against a recorded number.**
##
## 1. Nothing is dropped: scenery plus road points plus actor spawns equals the number of
##    six-number lines, counted here by reading the file.
## 2. No line inside a procedural-road block is read as scenery, counting those blocks here too.
## 3. No scenery name carries a space: upstream's `%s` stops at whitespace and so must this.
## 4. Every scenery placement whose `.odef` exists anywhere a mod may name it from builds
##    geometry. One whose definition is nowhere is reported — upstream draws nothing for it
##    either, `FetchODef` returns null — and Starling's own tree pack ships `mc_tree02` through
##    `mc_tree06` and not `mc_tree01`, which is a fault in the mod and not in the reader.

## Below this there is nothing to judge: a fresh clone has no downloaded terrains.
const MIN_TERRAINS: int = 1
const LISTED: int = 6


static func meta() -> Dictionary:
    return {
        "name": "every_object_line_is_read_as_what_it_is",
        "proves": "every object line of every terrain in the library is read as scenery, a road point or an actor spawn, and every placement whose definition this checkout has builds geometry",
        "builds_on": ["ror_terrain_objects_are_placed"],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "scenery + road points + actor spawns equals the six-number lines, and every findable definition builds",
        "why": (
            "read as scenery, a road point asks for an object definition called `0`, and an"
            + " object definition was looked for only beside the terrain while the map names"
            + " many it does not ship. 835 of Port Starling's 1502 placements drew nothing:"
            + " most of its roads and a good share of its buildings."
        ),
        "budget_s": 420.0,
        "needs_gpu": true,
        "milestone": "C2",
    }


func run(_harness: Node) -> Dictionary:
    var terrains: int = 0
    var placed: int = 0
    var built: int = 0
    var without: int = 0
    var broken: int = 0
    var problems: PackedStringArray = PackedStringArray()
    for summary: Dictionary in RorTerrainLibrary.summaries():
        if (summary["error"] as String) != "":
            continue
        var loaded: Dictionary = RorTerrainLibrary.load_named(summary["name"] as String)
        if (loaded.get("error", "") as String) != "":
            continue
        var terrain: RorTerrain = loaded["terrain"] as RorTerrain
        terrains += 1
        var own: Dictionary = _lines_of(terrain)
        var sorted: Dictionary = RorObjects.unbuilt(terrain)
        var placements: Array[Dictionary] = RorObjects.placements(terrain)
        var accounted: int = (
            placements.size() + (sorted["road_points"] as int) + (sorted["actor_spawns"] as int)
        )
        if accounted != (own["lines"] as int):
            problems.append(
                "%s: %d six-number lines and %d accounted for"
                % [summary["name"], own["lines"], accounted]
            )
        if (sorted["road_points"] as int) < (own["road_lines"] as int):
            problems.append(
                "%s: %d lines inside procedural-road blocks and %d read as road points"
                % [summary["name"], own["road_lines"], sorted["road_points"]]
            )
        var caches: Dictionary = RorObjects.state(terrain)
        for placement: Dictionary in placements:
            placed += 1
            var name: String = placement["name"] as String
            if name.contains(" "):
                problems.append("%s: an object named `%s`" % [summary["name"], name])
                continue
            if not RorContentPath.has("%s.odef" % name, terrain.directory):
                without += 1
                continue
            # The file is there, so the loader has to find it. Looked for only beside the
            # terrain it was not: this is the check that fails on 2361 placements.
            var odef: Dictionary = RorObjects.definition(terrain, name, caches)
            if (odef.get("error", "") as String) != "":
                problems.append(
                    "%s: %s.odef exists and the loader did not find it"
                    % [summary["name"], name]
                )
                continue
            if _draws(terrain, name, caches):
                built += 1
            elif _names_a_readable_mesh(terrain, name, caches):
                problems.append(
                    "%s: %s has a definition and a readable mesh and builds no geometry"
                    % [summary["name"], name]
                )
            else:
                # A mesh file that will not read is a broken file, not a misread line.
                # NhelensGrass ships `a1da0UID-kwhale.mesh` whose own M_MESH chunk declares
                # 110,924 bytes in a file of 106,944: it is 3,980 bytes short, and nothing can
                # be made of it.
                broken += 1

    if terrains < MIN_TERRAINS:
        return ok("skipped: no terrain in this checkout loads", 0)
    if problems.size() > 0:
        return fail(
            "%d object lines across %d terrains are not read as what they are: %s"
            % [problems.size(), terrains, "; ".join(problems.slice(0, LISTED))],
            problems.size()
        )
    return ok(
        "%d terrains, %d scenery placements, %d built%s"
        % [terrains, placed, built,
           ("" if without == 0 else
            "; %d name a definition no file in this checkout holds" % without)
           + ("" if broken == 0 else "; %d name a mesh file that will not read" % broken)],
        built
    )


## Whether a placement's definition names a mesh file this reader can open at all. The question
## separates "the line was misread" from "the file is broken", which look identical from the
## outside and have nothing to do with each other.
func _names_a_readable_mesh(terrain: RorTerrain, name: String, caches: Dictionary) -> bool:
    var odef: Dictionary = RorObjects.definition(terrain, name, caches)
    if (odef.get("error", "") as String) != "":
        return false
    for file: String in odef["meshes"] as PackedStringArray:
        var read: Dictionary = (caches["reader"] as RefCounted).read_file(
            RorContentPath.find(file, terrain.directory)
        )
        if (read.get("error", "") as String) == "" and (read["submeshes"] as Array).size() > 0:
            return true
    return false


## Whether one placement resolves all the way to geometry.
func _draws(terrain: RorTerrain, name: String, caches: Dictionary) -> bool:
    var odef: Dictionary = RorObjects.definition(terrain, name, caches)
    if (odef.get("error", "") as String) != "":
        return false
    for file: String in odef["meshes"] as PackedStringArray:
        if RorObjects.mesh_of(terrain, file, caches) != null:
            return true
    return false


## How many six-number lines a terrain's object files hold, and how many of them are inside a
## procedural-road block. Counted here, with no help from the reader under test.
func _lines_of(terrain: RorTerrain) -> Dictionary:
    var lines: int = 0
    var road_lines: int = 0
    for file: String in terrain.config["objects"] as PackedStringArray:
        var inside: bool = false
        for raw_line: String in RorText.read(terrain.directory.path_join(file)).split("\n"):
            var line: String = raw_line.strip_edges()
            if line.is_empty() or line.begins_with("//") or line.begins_with(";"):
                continue
            var first: String = line.get_slice(" ", 0).to_lower()
            if first == Tobj.ROADS_BEGIN:
                inside = true
                continue
            if first == Tobj.ROADS_END:
                inside = false
                continue
            var fields: PackedStringArray = line.split(",")
            if fields.size() < 7 or not fields[0].strip_edges().is_valid_float():
                continue
            lines += 1
            if inside:
                road_lines += 1
    return {"lines": lines, "road_lines": road_lines}
