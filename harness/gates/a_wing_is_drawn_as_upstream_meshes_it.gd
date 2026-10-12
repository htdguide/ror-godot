extends GateBase
## A wing is drawn as upstream's `FlexAirfoil` meshes it: 54 vertices at fractions of its panel's
## edges, 44 triangles (the two end faces, the cambered band, the control surface up and down),
## the trailing edge of its control surface swung by its deflection about the chord point
## (`updateVerticesPhysics`), a stabilator turned whole, and a broken wing collapsed to a speck;
## seen from outside, the band's faces are the front ones Godot draws.
##
## Ours drew no wings: every aircraft flew as a fuselage.
##
## The oracle is upstream's code read rule by rule: a 2 m by 1 m panel 0.1 m thick, chord point
## 0.75, deflected 0 and 20 degrees.

const PLANE: String = """plane
globals
1000, 0, tracks/semi
nodes
0, 0, 0, 0
1, 2, 0, 0
2, 0, 0.1, 0
3, 2, 0.1, 0
4, 0, 0, 1
5, 2, 0, 1
6, 0, 0.1, 1
7, 2, 0.1, 1
beams
0, 1
wings
0, 1, 2, 3, 4, 5, 6, 7, 0, 0, 1, 0, 0, 1, 1, 1, a, 0.75, 20, 20, NACA0009.afl
0, 1, 2, 3, 4, 5, 6, 7, 0, 0, 1, 0, 0, 1, 1, 1, S, 0.75, 20, 20, NACA0009.afl
end"""


static func meta() -> Dictionary:
    return {
        "name": "a_wing_is_drawn_as_upstream_meshes_it",
        "proves": "wings are drawn as upstream's FlexAirfoil meshes them: its vertices, triangles, control-surface swing, stabilator turn and broken collapse, front-facing outward",
        "builds_on": [],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "54 vertices and 44 triangles; the trailing edge at upstream's position within 1e-5 m at 0 and 20 degrees; a broken wing within 0.03 m of its corner; top faces front-facing upward",
        "why": "wings were not drawn: every aircraft flew as a fuselage.",
        "budget_s": 10.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var truck: TruckParser = TruckParser.new()
    truck.parse_text(PLANE)
    var root: Node3D = Node3D.new()
    var wings: Array[Dictionary] = WingMesh.build(root, truck, StandardMaterial3D.new())
    if wings.size() != 2:
        root.free()
        return fail("%d wings were drawn, not 2" % wings.size())
    var nodes: PackedVector3Array = truck.nodes
    WingMesh._pose(wings[0], nodes, Transform3D.IDENTITY, 0.0, false)
    var arrays: Array = (wings[0]["instance"] as MeshInstance3D).mesh.surface_get_arrays(0)
    var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
    if v.size() != 54 or idx.size() != 132:
        root.free()
        return fail("the wing has %d vertices and %d triangles, not upstream's 54 and 44" % [v.size(), idx.size() / 3])
    # The trailing edge, vertex 26: upstream's airfoilpos 78-80 times the left edges, at rest
    # (0.5 + 0.25 x sin 0, 0.75 + 0.25 x cos 0) of the thickness and the chord.
    var thick: float = 0.1
    var want: Vector3 = Vector3(0.0, 0.5 * thick, 1.0)
    if v[26].distance_to(want) > 1e-5:
        root.free()
        return fail("at rest the trailing edge is at %s, not upstream's %s" % [v[26], want])
    WingMesh._pose(wings[0], nodes, Transform3D.IDENTITY, 20.0, false)
    v = (wings[0]["instance"] as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
    var lratio: float = thick / 1.0
    want = Vector3(0.0, (0.5 + 0.25 * sin(20.0 / 57.0) / lratio) * thick, 0.75 + 0.25 * cos(20.0 / 57.0))
    if v[26].distance_to(want) > 1e-5:
        root.free()
        return fail("deflected 20 degrees the trailing edge is at %s, not upstream's %s" % [v[26], want])
    # Front faces: the band's top triangles, by Godot's clockwise winding, face up.
    var up: int = 0
    var down: int = 0
    for t: int in range(60, 120, 3):
        var a: Vector3 = v[idx[t]]
        var b: Vector3 = v[idx[t + 1]]
        var c: Vector3 = v[idx[t + 2]]
        var centre: Vector3 = (a + b + c) / 3.0
        var front: Vector3 = (c - a).cross(b - a)
        if centre.y > 0.5 * thick + 1e-4:
            if front.y > 0.0:
                up += 1
            else:
                down += 1
    if up == 0 or down != 0:
        root.free()
        return fail("of the band's upper triangles %d face up and %d down; all should face up" % [up, down])
    # The stabilator turns whole: its leading edge (vertex 0) moves with the deflection.
    WingMesh._pose(wings[1], nodes, Transform3D.IDENTITY, 0.0, false)
    var rest: Vector3 = (wings[1]["instance"] as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0]
    WingMesh._pose(wings[1], nodes, Transform3D.IDENTITY, 20.0, false)
    var turned: Vector3 = (wings[1]["instance"] as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX][0]
    if rest.distance_to(turned) < 0.01:
        root.free()
        return fail("the stabilator's leading edge did not move when deflected 20 degrees")
    WingMesh._pose(wings[0], nodes, Transform3D.IDENTITY, 0.0, true)
    v = (wings[0]["instance"] as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
    for p: Vector3 in v:
        if p.length() > 0.03:
            root.free()
            return fail("a broken wing still reaches %s from its corner" % p)
    root.free()
    return ok("54 vertices, 44 triangles; trailing edge as upstream's at 0 and 20 degrees; stabilator turns; broken collapses; %d upper faces front-facing up" % up, 0)
