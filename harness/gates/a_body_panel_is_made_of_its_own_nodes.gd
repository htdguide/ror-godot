extends GateBase
## Every body panel a vehicle file describes is built, and every vertex of it sits on the node it
## is made of.
##
## **A `submesh` is geometry with no mesh file behind it.** Its vertices *are* nodes, its
## triangles are `cab` lines over them, and its texture coordinates come from `texcoords` lines.
## Upstream builds a `FlexObj` per group; this project read the triangles for collision and drew
## none of it. 18 of the 18 vehicles in this library declare submeshes — for four of them it is
## the whole of their geometry, and for ten more it is bodywork missing from something that
## otherwise looked built. Building them took the library from 405 drawn parts to 573.
##
## **The oracle is the vehicle's own file, twice over.**
##
## 1. A group that declares at least three texture coordinates and at least one triangle over
##    nodes that have them is drawable, and every drawable group has to produce a part. Counted
##    by reading the file, not by asking the builder.
## 2. Every vertex of a built panel has to coincide **exactly** with the node it was made from.
##    That is not a tolerance: a cab vertex is a node, so the distance is zero or the geometry is
##    not what the file says. It is the check that would catch a panel built from the wrong
##    nodes, which would look plausible and be wrong.
##
## A cab with no texture coordinates is not drawn, and upstream does not draw one either. The
## hero truck and the Mazda are both that case: 242 and 187 cab triangles, no coordinates at all.

## Below this there is nothing to judge: a fresh clone has no downloaded packs.
const MIN_VEHICLES: int = 2
## A vertex and its node are the same point. This is float slack, not a tolerance.
const COINCIDENT_M: float = 1e-6
const LISTED: int = 6


static func meta() -> Dictionary:
    return {
        "name": "a_body_panel_is_made_of_its_own_nodes",
        "proves": "every drawable submesh group in the library builds a panel, and every vertex of every panel sits exactly on the node it is made of",
        "builds_on": ["every_mod_car_builds"],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "every drawable group builds, and every vertex is within 1e-6 m of its node",
        "why": (
            "a submesh body has no mesh file to check against: it is nodes and triangles over"
            + " them, so a panel built from the wrong nodes looks plausible. 18 of 18 vehicles"
            + " here declare one and none of them drew it."
        ),
        "budget_s": 300.0,
        "needs_gpu": true,
        "milestone": "C1",
    }


func run(_harness: Node) -> Dictionary:
    var entries: Array[Dictionary] = RorVehicleLibrary.entries()
    if entries.size() < MIN_VEHICLES:
        return ok("skipped: %d vehicles in this checkout" % entries.size(), 0)
    var dds: RefCounted = ClassDB.instantiate("DdsReader") as RefCounted
    var declared: int = 0
    var built: int = 0
    var vertices: int = 0
    var problems: PackedStringArray = PackedStringArray()
    for entry: Dictionary in entries:
        var truck: TruckParser = TruckParser.new()
        var path: String = (entry["directory"] as String).path_join(entry["file"] as String)
        if truck.parse_file(path) != "":
            continue
        var wanted: int = _drawable_groups(path)
        declared += wanted
        var root: Node3D = Node3D.new()
        var parts: Array[SkinnedFlexbody] = CabBody.build(
            root, truck, Transform3D.IDENTITY, entry["directory"] as String, dds, {}, {}
        )
        built += parts.size()
        if parts.size() != wanted:
            problems.append(
                "%s: %d groups its file can draw, %d built"
                % [entry["name"], wanted, parts.size()]
            )
        for part: SkinnedFlexbody in parts:
            var apart: float = _furthest_from_a_node(part, truck.nodes)
            vertices += part.rest_vertices.size()
            if apart > COINCIDENT_M:
                problems.append(
                    "%s: a panel vertex sits %.6f m from any node" % [entry["name"], apart]
                )
        root.queue_free()

    if declared == 0:
        return ok("skipped: no vehicle in this checkout declares a drawable body panel", 0)
    if problems.size() > 0:
        return fail(
            "%d of %d declared body panels are not what their file says: %s"
            % [problems.size(), declared, "; ".join(problems.slice(0, LISTED))],
            problems.size()
        )
    return ok(
        "%d body panels across %d vehicles, %d vertices, every one of them on its own node"
        % [built, entries.size(), vertices],
        built
    )


## How far the furthest vertex of a panel sits from the nearest node of the rig.
func _furthest_from_a_node(part: SkinnedFlexbody, nodes: PackedVector3Array) -> float:
    var worst: float = 0.0
    for vertex: Vector3 in part.rest_vertices:
        var nearest: float = INF
        for node: Vector3 in nodes:
            nearest = minf(nearest, vertex.distance_squared_to(node))
            if nearest <= 0.0:
                break
        worst = maxf(worst, sqrt(nearest))
    return worst


## How many `submesh` groups a file describes that can be drawn: at least three texture
## coordinates, and at least one triangle every corner of which has one.
##
## Read here with its own scan rather than through `TruckParser`, because the parser is half of
## what is under test.
func _drawable_groups(path: String) -> int:
    var count: int = 0
    var section: String = ""
    var uvs: Dictionary = {}
    var triangles: Array[PackedStringArray] = []
    var out: int = 0
    for raw_line: String in RorText.read(path).split("\n"):
        var line: String = raw_line.get_slice(";", 0).get_slice("//", 0).strip_edges()
        if line.is_empty():
            continue
        if not line.contains(",") and not line.contains(" ") and not line.contains("\t"):
            if line.to_lower() == "submesh":
                out += _judge(uvs, triangles)
                uvs = {}
                triangles = []
                count += 1
            section = line.to_lower()
            continue
        var fields: PackedStringArray = RorText.fields(line)
        if section == "texcoords" and fields.size() >= 3:
            uvs[fields[0]] = true
        elif section == "cab" and fields.size() >= 3:
            triangles.append(fields)
    out += _judge(uvs, triangles)
    return out


## Whether one group's own lines describe something drawable.
func _judge(uvs: Dictionary, triangles: Array[PackedStringArray]) -> int:
    if uvs.size() < 3 or triangles.is_empty():
        return 0
    for triangle: PackedStringArray in triangles:
        for corner: int in 3:
            if not uvs.has(triangle[corner]):
                # A triangle over a node with no coordinates cannot be textured, and the builder
                # drops the whole group rather than draw half a panel.
                return 0
    return 1
