extends GateBase
## The top surface of every procedural road is drawn facing upwards.
##
## **A road wound the wrong way round is a road nobody can see.** Godot draws a triangle as
## front-facing when its corners run clockwise in screen space (ADR 0005), and the sweep wound
## its quads the other way — so every deck on every map pointed at the ground. The shoulders
## stood either side of a corridor of grass and a vehicle drove on a surface that was not there.
## Reported from a window as "car standing with no road texture on the road", with a photograph
## of the truck between two kerbs on bare terrain; measured at that spot, 32 near-horizontal road
## triangles faced down and none faced up.
##
## Nothing checked this. `an_object_is_wound_the_way_its_file_is` and `object_photoset` hold the
## *objects* a terrain places to the convention, and a swept road is the one piece of a terrain
## that is not an object: it is built here from a line of points, so it has no file to be checked
## against and no mesh to photograph.
##
## **An underside is allowed to face down, and bridges have one.** A raised road carries a deck,
## two walls and a floor, and the floor is correctly turned away from the sky. So a downward face
## is a fault only where nothing covers it: the test asks whether any road surface sits above it
## in the same column, and lets it pass when one does.

## How level a triangle has to be before it counts as a surface rather than a wall.
const LEVEL: float = 0.7
## How wide a column is when asking what is above a triangle.
const COLUMN_M: float = 1.0
## How far above a triangle another surface has to sit to be a roof over it rather than itself.
const COVER_M: float = 0.1
## Below this a terrain sweeps no road worth judging.
const MIN_SURFACES: int = 20
const LISTED: int = 5


static func meta() -> Dictionary:
    return {
        "name": "a_swept_road_faces_the_sky",
        "proves": (
            "every level surface of every procedural road on every terrain faces upwards, unless"
            + " another road surface covers it"
        ),
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "no uncovered level road triangle facing down",
        "why": (
            "the sweep wound its quads counter-clockwise and Godot faces a triangle forward when"
            + " it runs clockwise, so every road deck on every map was drawn pointing at the"
            + " ground: kerbs either side of a corridor of grass, and a vehicle driving on"
            + " nothing. A swept road is the one part of a terrain with no file to check it"
            + " against and no mesh to photograph."
        ),
        "budget_s": 180.0,
        "needs_gpu": false,
        "milestone": "C2",
    }


func run(_harness: Node) -> Dictionary:
    var surfaces: int = 0
    var terrains: int = 0
    var problems: PackedStringArray = PackedStringArray()
    for summary: Dictionary in RorTerrainLibrary.summaries():
        if (summary["error"] as String) != "":
            continue
        var loaded: Dictionary = RorTerrainLibrary.load_named(summary["name"] as String)
        if (loaded.get("error", "") as String) != "":
            continue
        var terrain: RorTerrain = loaded["terrain"] as RorTerrain
        var level: Array[Dictionary] = _level_triangles(terrain)
        if level.is_empty():
            continue
        terrains += 1
        surfaces += level.size()
        # The highest road surface over each column, so an underside can be told from a deck.
        var roof: Dictionary = {}
        for face: Dictionary in level:
            var at: Vector3 = face["at"] as Vector3
            var key: String = "%d,%d" % [
                floori(at.x / COLUMN_M), floori(at.z / COLUMN_M)
            ]
            roof[key] = maxf(roof.get(key, -INF) as float, at.y)
        for face: Dictionary in level:
            if (face["up"] as bool):
                continue
            var at: Vector3 = face["at"] as Vector3
            var key: String = "%d,%d" % [
                floori(at.x / COLUMN_M), floori(at.z / COLUMN_M)
            ]
            if (roof[key] as float) > at.y + COVER_M:
                continue
            problems.append("%s: a level road surface at %v faces down with nothing over it"
                % [summary["name"], at])

    if surfaces < MIN_SURFACES:
        return ok("skipped: %d level road surfaces in this checkout" % surfaces, surfaces)
    if problems.size() > 0:
        return fail(
            "%d of %d level road surfaces face down: %s"
            % [problems.size(), surfaces, "; ".join(problems.slice(0, LISTED))],
            problems.size()
        )
    return ok(
        "%d level road surfaces across %d terrains, every uncovered one facing the sky"
        % [surfaces, terrains],
        surfaces
    )


## Every near-level triangle of a terrain's swept roads, as `{"at", "up"}` in world space.
func _level_triangles(terrain: RorTerrain) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    # Freed below: the builder makes a node per block and nothing here puts them in a tree.
    var built: Node3D = RorProceduralRoad.build(terrain)
    for node: Node in built.get_children():
        var road: MeshInstance3D = node as MeshInstance3D
        if road == null or road.mesh == null:
            continue
        for surface: int in road.mesh.get_surface_count():
            var arrays: Array = road.mesh.surface_get_arrays(surface)
            var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
            var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
            for at: int in range(0, indices.size() - 2, 3):
                var a: Vector3 = road.transform * points[indices[at]]
                var b: Vector3 = road.transform * points[indices[at + 1]]
                var c: Vector3 = road.transform * points[indices[at + 2]]
                # Clockwise is forward, so the way a drawn face looks is the negated cross.
                var face: Vector3 = -(b - a).cross(c - a)
                if face.length_squared() <= 0.0:
                    continue
                var normal: Vector3 = face.normalized()
                if absf(normal.y) < LEVEL:
                    continue
                out.append({"at": (a + b + c) / 3.0, "up": normal.y > 0.0})
    built.free()
    return out
