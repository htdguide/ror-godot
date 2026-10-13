extends GateBase
## A `forset` line names the nodes upstream's `ProcessForsetLine` reads from it: comma-separated
## items, each a node or a range around a dash, every number read as C's `strtoul` reads it. So
## "0 - 36" is 37 nodes, "1 2" is node 1, and a trailing comma or garbage adds node 0.
##
## Ours split on spaces as well as commas: the Spitfire's "forset 0 - 36" bound its fuselage and
## canopy to nodes 0 and 36 alone, 5,543 vertices on a flat triad.
##
## The oracle is upstream's code read rule by rule, then the Spitfire itself.

const CASES: Array = [
    ["0 - 36", [0, 36, 37]],
    ["0-3,5", [0, 5, 5]],
    [" : 2-4 , 7", [2, 7, 4]],
    ["1 2", [1, 1, 1]],
    ["152, 153,", [152, 0, 3]],
    ["x", [0, 0, 1]],
]
const MOD_DIR: String = "assets/corpus/181_supermarine-spitfire"


static func meta() -> Dictionary:
    return {
        "name": "a_forset_is_read_as_upstream_reads_it",
        "proves": "forset lines resolve to the nodes upstream's ProcessForsetLine reads, its quirks included, and a vertex on a flat triad binds at zero as upstream's Matrix3::Inverse leaves it",
        "builds_on": [],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "a flat triad binds at zero; %d lines resolve to upstream's first node, last node and count; every Spitfire flexbody vertex on an invertible triad (upstream zeroes a flat one)" % CASES.size(),
        "why": "'forset 0 - 36' was read as two nodes: the Spitfire's fuselage and canopy bound to a flat triad.",
        "budget_s": 20.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var ids: Dictionary = {}
    for id: int in 200:
        ids[str(id)] = id
    for c: Array in CASES:
        var got: PackedInt32Array = NodeIdRanges.resolve(c[0], ids)
        var want: Array = c[1]
        if got.size() != want[2] or got[0] != want[0] or got[got.size() - 1] != want[1]:
            return fail("forset '%s' read as %s; upstream reads %d nodes from %d to %d" % [c[0], got, want[2], want[0], want[1]])
    # Three nodes in a line: upstream's `Matrix3::Inverse` fails and gives zero, so the vertex
    # binds at its reference node instead of wherever a singular inverse would throw it.
    var line: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3(2, 0, 0)])
    var lined: Dictionary = FlexbodyBinder.bind(line, PackedInt32Array([0, 1, 2]), PackedVector3Array([Vector3(0.1, 0.5, 0.2)]))
    if (lined["coords"] as PackedVector3Array)[0] != Vector3.ZERO:
        return fail("a vertex on three nodes in a line bound at %s, not upstream's zero" % (lined["coords"] as PackedVector3Array)[0])
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("%d lines as upstream; the Spitfire is not present" % CASES.size(), 0)
    var built: Dictionary = VehicleBuilder.build(mod_dir, "spitfire_Vb.airplane")
    var truck: TruckParser = built["truck"]
    var parts: Array[SkinnedFlexbody] = built["parts"]
    var flat: int = 0
    for i: int in parts.size():
        var forset: PackedInt32Array = truck.flexbodies[i]["forset"]
        for v: Vector3 in parts[i].rest_vertices:
            var t: Vector3i = FlexbodyBinder._triad_for(truck.nodes, forset, v)
            var dx: Vector3 = truck.nodes[t.y] - truck.nodes[t.x]
            var dy: Vector3 = truck.nodes[t.z] - truck.nodes[t.x]
            if absf(Basis(dx, dy, dx.cross(dy).normalized()).determinant()) <= 1e-6:
                flat += 1
    (built["root"] as Node).free()
    if flat > 0:
        return fail("%d Spitfire flexbody vertices bind to a flat triad" % flat, flat)
    return ok("%d lines as upstream; the Spitfire's %d flexbodies bind to invertible triads" % [CASES.size(), truck.flexbodies.size()], 0)
