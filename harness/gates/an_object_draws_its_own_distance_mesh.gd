extends GateBase
## An object with a `beginlodmesh` block draws its own distance meshes, at the distances its
## definition states.
##
## **This is the author's own distance geometry and nobody has drawn it for years.** A
## `beginlodmesh` block is a list of `<distance>, <mesh>` lines saying which mesh to draw from how
## far away. Upstream's current parser reads the block and does nothing with it. Starling Island
## ships twelve such meshes across ten objects — its firehouse, police department, hospital, three
## stores, office block, warehouse, bus stop and a road sign — and every one of them is on the
## disk. It is the cheapest distance geometry this project can have, because somebody else already
## made it.
##
## **The oracle is the object definition.** The gate reads each `.odef` with its own small scan,
## takes the distances out of it, and requires the built scene to carry a batch for every level at
## exactly those distances: the header mesh from zero to the first stated distance, each level
## from its own to the next, the last to the horizon. A distance of zero is Godot's "no limit",
## which is what the far end of the last level wants.
##
## It also reports what the levels are worth. A distance mesh that is not simpler than the mesh it
## stands in for is a level that costs more than it saves, which is a fact about the content
## rather than about this project, so it is counted rather than failed.

## Below this there is nothing to judge.
const MIN_LEVELS: int = 1
const LISTED: int = 6
## Float slack on a distance read from a file and written to a property.
const EPSILON: float = 0.01


static func meta() -> Dictionary:
    return {
        "name": "an_object_draws_its_own_distance_mesh",
        "proves": "every object that declares distance meshes draws them, each over exactly the range its own definition states",
        "builds_on": ["ror_terrain_objects_are_placed"],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "a batch per level, with the begin and end distances the definition states",
        "why": (
            "a `beginlodmesh` block is distance geometry the terrain's author already made, and"
            + " upstream's own parser reads it and throws it away. Twelve of them ship with"
            + " Starling Island and none were drawn."
        ),
        "budget_s": 300.0,
        "needs_gpu": false,
        "milestone": "C2",
    }


func run(_harness: Node) -> Dictionary:
    var levels: int = 0
    var objects: int = 0
    var no_cheaper: int = 0
    var saved: int = 0
    var problems: PackedStringArray = PackedStringArray()
    for summary: Dictionary in RorTerrainLibrary.summaries():
        if (summary["error"] as String) != "":
            continue
        var loaded: Dictionary = RorTerrainLibrary.load_named(summary["name"] as String)
        if (loaded.get("error", "") as String) != "":
            continue
        var terrain: RorTerrain = loaded["terrain"] as RorTerrain
        var state: Dictionary = RorObjects.state(terrain)
        var wanted: Dictionary = _wanted_ranges(terrain)
        if wanted.is_empty():
            continue
        var root: Node3D = RorObjects.build(terrain)
        var ranges: Dictionary = _built_ranges(root)
        for mesh_file: String in wanted.keys():
            levels += 1
            var want: Vector2 = wanted[mesh_file] as Vector2
            if not ranges.has(mesh_file):
                problems.append(
                    "%s: %s is declared as a distance mesh and no batch draws it"
                    % [summary["name"], mesh_file]
                )
                continue
            var got: Vector2 = ranges[mesh_file] as Vector2
            if absf(got.x - want.x) > EPSILON or absf(got.y - want.y) > EPSILON:
                problems.append(
                    "%s: %s should draw from %.0f to %.0f m and draws from %.0f to %.0f"
                    % [summary["name"], mesh_file, want.x, want.y, got.x, got.y]
                )
        root.queue_free()
        var worth: Dictionary = _worth(terrain, state)
        objects += worth["objects"] as int
        no_cheaper += worth["no_cheaper"] as int
        saved += worth["saved"] as int

    if levels < MIN_LEVELS:
        return ok("skipped: no object in this checkout declares a distance mesh", 0)
    if problems.size() > 0:
        return fail(
            "%d of %d declared distance meshes are not drawn as their definition states: %s"
            % [problems.size(), levels, "; ".join(problems.slice(0, LISTED))],
            problems.size()
        )
    return ok(
        "%d distance meshes across %d objects, each over the range its definition states;"
        % [levels, objects]
        + " %d triangles saved at the furthest level%s"
        % [saved, "" if no_cheaper == 0 else ", %d no simpler than the mesh they stand in for"
           % no_cheaper],
        levels
    )


## The range every declared distance mesh should be drawn over, read from the definitions
## themselves. `{mesh file -> Vector2(begin, end)}`.
func _wanted_ranges(terrain: RorTerrain) -> Dictionary:
    var out: Dictionary = {}
    var seen: Dictionary = {}
    for placement: Dictionary in RorObjects.placements(terrain):
        var name: String = placement["name"] as String
        if seen.has(name):
            continue
        seen[name] = true
        var path: String = RorContentPath.find("%s.odef" % name, terrain.directory)
        var stated: Array[Dictionary] = _stated_lods(path)
        for index: int in stated.size():
            out[stated[index]["mesh"]] = Vector2(
                stated[index]["distance"] as float,
                0.0 if index + 1 >= stated.size()
                else stated[index + 1]["distance"] as float
            )
    return out


## The `<distance>, <mesh>` lines of a `beginlodmesh` block, read here rather than through
## `Odef`, because `Odef` is half of what is under test.
func _stated_lods(path: String) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var inside: bool = false
    for raw_line: String in RorText.read(path).split("\n"):
        var line: String = raw_line.strip_edges()
        if line.to_lower() == "beginlodmesh":
            inside = true
            continue
        if line.to_lower() == "endlodmesh":
            inside = false
            continue
        if not inside:
            continue
        var fields: PackedStringArray = line.split(",")
        if fields.size() >= 2 and fields[0].strip_edges().is_valid_float():
            out.append({
                "distance": fields[0].strip_edges().to_float(),
                "mesh": fields[1].strip_edges(),
            })
    out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return (a["distance"] as float) < (b["distance"] as float)
    )
    return out


## What range each mesh is actually drawn over in the built scene.
func _built_ranges(root: Node3D) -> Dictionary:
    var out: Dictionary = {}
    for child: Node in root.get_children():
        var batch: MultiMeshInstance3D = child as MultiMeshInstance3D
        if batch == null or not batch.has_meta("mesh_file"):
            continue
        out[batch.get_meta("mesh_file")] = Vector2(
            batch.visibility_range_begin, batch.visibility_range_end
        )
    return out


## What the levels are worth: how many triangles the furthest level saves over the mesh it
## stands in for, and how many are no simpler than it.
func _worth(terrain: RorTerrain, state: Dictionary) -> Dictionary:
    var objects: int = 0
    var no_cheaper: int = 0
    var saved: int = 0
    var seen: Dictionary = {}
    for placement: Dictionary in RorObjects.placements(terrain):
        var name: String = placement["name"] as String
        if seen.has(name):
            continue
        seen[name] = true
        var odef: Dictionary = RorObjects.definition(terrain, name, state)
        var lods: Array[Dictionary] = odef.get("lods", [] as Array[Dictionary])
        if lods.is_empty():
            continue
        objects += 1
        var full: int = 0
        for mesh_file: String in odef["meshes"] as PackedStringArray:
            full += _triangles(RorObjects.mesh_of(terrain, mesh_file, state))
        var furthest: int = _triangles(
            RorObjects.mesh_of(terrain, lods[lods.size() - 1]["mesh"] as String, state)
        )
        if furthest >= full:
            no_cheaper += 1
        else:
            saved += full - furthest
    return {"objects": objects, "no_cheaper": no_cheaper, "saved": saved}


func _triangles(mesh: ArrayMesh) -> int:
    if mesh == null:
        return 0
    var total: int = 0
    for surface: int in mesh.get_surface_count():
        total += (
            mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX] as PackedInt32Array
        ).size() / 3
    return total
