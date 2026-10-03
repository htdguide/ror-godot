extends GateBase
## A terrain's procedural roads are built, they lie along the points that describe them, and
## their surface faces the sky.
##
## **A `begin_procedural_roads` block is a line of cross-sections**, not a list of objects: each
## line is a position, a rotation, a carriageway width and a border width and height, and
## upstream sweeps the section along the line into one mesh — `ProceduralRoad::addBlock`. 374 of
## Port Starling's 1502 object lines are road points, which is most of its road network, and this
## project read them as placements asking for object definitions named `0`, `8` and `10`.
##
## **Three things are checked, each against the terrain's own points.**
##
## 1. Every block of two points or more produces geometry. Counted from the file.
## 2. Every vertex lies within the half-width its own points state of the line they describe. A
##    sweep that wanders is a road somewhere else, and the bound is the road's own width plus its
##    own border, not a figure chosen here.
## 3. Every near-horizontal face points up. A carriageway wound the other way is invisible from
##    the only place anybody looks at it from, which is exactly what the first build did: 1638
##    horizontal faces, every one of them face-down.
##
## `bridge` and `monorail` points are reported rather than built — they carry pillars, an
## underside and their own wall fits — so a block holding one is allowed to be short of geometry.

## How far outside its own stated half-width a vertex may sit. A shoulder's foot is pulled onto
## the heightmap, which moves it along the ground, so this is slack for terrain rather than for
## the sweep.
const SLACK_M: float = 3.0
## A face this close to horizontal is a surface somebody drives on or looks at from above.
const HORIZONTAL_DOT: float = 0.7
const LISTED: int = 6


static func meta() -> Dictionary:
    return {
        "name": "a_road_of_points_is_swept_into_a_road",
        "proves": "every procedural road block a terrain describes is swept into geometry that lies along its own points with its surface facing up",
        "builds_on": ["every_object_line_is_read_as_what_it_is"],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "every block of two or more buildable points builds, every vertex within its own"
            + " half-width plus %.0f m of the line, and no near-horizontal face pointing down"
            % SLACK_M
        ),
        "why": (
            "374 of Port Starling's 1502 object lines are road points and this project read them"
            + " as placements, so most of its road network was missing. A sweep that wanders is"
            + " a road somewhere else, and one wound the other way is invisible from above —"
            + " which the first build was, on all 1638 of its horizontal faces."
        ),
        "budget_s": 300.0,
        "needs_gpu": false,
        "milestone": "C2",
    }


func run(_harness: Node) -> Dictionary:
    var terrains: int = 0
    var blocks: int = 0
    var triangles: int = 0
    var unbuilt: Dictionary = {}
    var problems: PackedStringArray = PackedStringArray()
    for summary_row: Dictionary in RorTerrainLibrary.summaries():
        if (summary_row["error"] as String) != "":
            continue
        var loaded: Dictionary = RorTerrainLibrary.load_named(summary_row["name"] as String)
        if (loaded.get("error", "") as String) != "":
            continue
        var terrain: RorTerrain = loaded["terrain"] as RorTerrain
        var counted: Dictionary = RorProceduralRoad.summary(terrain)
        if (counted["points"] as int) == 0:
            continue
        terrains += 1
        for kind: String in (counted["unbuilt"] as Dictionary).keys():
            unbuilt[kind] = (
                (unbuilt.get(kind, 0) as int)
                + ((counted["unbuilt"] as Dictionary)[kind] as int)
            )
        var root: Node3D = RorProceduralRoad.build(terrain, StandardMaterial3D.new())
        var built: Array[MeshInstance3D] = []
        for child: Node in root.get_children():
            built.append(child as MeshInstance3D)
        var wanted: Array[Array] = []
        for group: Array[Dictionary] in RorProceduralRoad.groups(terrain):
            if _buildable(terrain, group) >= 2:
                wanted.append(group)
        if built.size() != wanted.size():
            problems.append(
                "%s: %d blocks of two or more buildable points, %d built"
                % [summary_row["name"], wanted.size(), built.size()]
            )
        blocks += built.size()
        for index: int in mini(built.size(), wanted.size()):
            var problem: String = _judge(built[index], terrain, wanted[index])
            if problem != "":
                problems.append("%s: %s" % [summary_row["name"], problem])
            triangles += _triangles(built[index])
        root.queue_free()

    if terrains == 0:
        return ok("skipped: no terrain in this checkout describes a procedural road", 0)
    if problems.size() > 0:
        return fail(
            "%d road blocks are not the road their points describe: %s"
            % [problems.size(), "; ".join(problems.slice(0, LISTED))],
            problems.size()
        )
    return ok(
        "%d terrains, %d road blocks, %d triangles%s"
        % [terrains, blocks, triangles,
           "" if unbuilt.is_empty() else "; not built yet: %s" % str(unbuilt)],
        blocks
    )


## What is wrong with one block's mesh, or "".
func _judge(node: MeshInstance3D, terrain: RorTerrain, group: Array[Dictionary]) -> String:
    var mesh: ArrayMesh = node.mesh as ArrayMesh
    if mesh == null or mesh.get_surface_count() == 0:
        return "a block built an empty mesh"
    var arrays: Array = mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
    var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
    for i: int in range(0, indices.size() - 2, 3):
        var face: Vector3 = (
            vertices[indices[i + 1]] - vertices[indices[i]]
        ).cross(vertices[indices[i + 2]] - vertices[indices[i]]).normalized()
        if face.y < -HORIZONTAL_DOT:
            return "a near-horizontal face points down: the surface is inside out"
    # The bound is the widest section the block's own points state, plus its own border.
    var allowed: float = 0.0
    var line: PackedVector3Array = PackedVector3Array()
    for point: Dictionary in group:
        var here: Dictionary = RorProceduralRoad.resolved(terrain, point)
        line.append(here["position"] as Vector3)
        allowed = maxf(
            allowed, (here["width"] as float) * 0.5 + (here["bwidth"] as float)
        )
    allowed += SLACK_M
    for vertex: Vector3 in vertices:
        var away: float = _from_the_line(vertex, line)
        if away > allowed:
            return (
                "a vertex sits %.1f m from the line its points describe, over the %.1f m their"
                % [away, allowed] + " own widths allow"
            )
    return ""


## How far a point is from a polyline, measured on the ground: the sweep follows the line's
## course and its own terrain-pinned feet move it up and down, not sideways.
func _from_the_line(at: Vector3, line: PackedVector3Array) -> float:
    var flat: Vector2 = Vector2(at.x, at.z)
    var nearest: float = INF
    for index: int in range(1, line.size()):
        var a: Vector2 = Vector2(line[index - 1].x, line[index - 1].z)
        var b: Vector2 = Vector2(line[index].x, line[index].z)
        var span: Vector2 = b - a
        var t: float = 0.0
        if span.length_squared() > 0.0:
            t = clampf((flat - a).dot(span) / span.length_squared(), 0.0, 1.0)
        nearest = minf(nearest, flat.distance_to(a + span * t))
    return nearest


## How many of a block's points are of a kind this builds.
func _buildable(terrain: RorTerrain, group: Array[Dictionary]) -> int:
    var count: int = 0
    for point: Dictionary in group:
        var here: Dictionary = RorProceduralRoad.resolved(terrain, point)
        if RorProceduralRoad.BUILT_KINDS.has(here["kind"]):
            count += 1
    return count


func _triangles(node: MeshInstance3D) -> int:
    var mesh: ArrayMesh = node.mesh as ArrayMesh
    if mesh == null or mesh.get_surface_count() == 0:
        return 0
    return (
        mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array
    ).size() / 3
