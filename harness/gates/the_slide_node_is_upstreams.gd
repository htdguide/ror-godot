extends GateBase
## A slide node is upstream's `SlideNode` on upstream's rail: a chain of the rig's own beams
## (`ActorSpawner::CreateRail`), closed into a loop when its first node is its last, the node
## keeping the segment it is on and moving at most to a neighbour each step
## (`RailSegment::CheckCurSlideSegment`), pulled to the nearest point past its tolerance, the
## reaction shared by the beam's ends, and breaking free past its break force, still pushing on the
## step it breaks. Compared step by step with SlideNode.cpp compiled from the pinned submodule
## (`tools/build_parity.sh`); the rail is built there by `CreateRail` transcribed.
##
## Ours searched the whole rail every step for the nearest segment, needed no beams under it,
## did not close a loop, and let go a step early. And a slide node naming a `railgroups` rail by
## `g` was refused: 1238 rows across the corpus, every excavator and dozer track.
##
## Rails here are open chains, loops a node runs round more than once, chains missing a beam (no
## rail, no force), beams written either way round, and paths that jump segments in one step.

const ORACLE: String = "build/parity/upstream_oracle"
const DT: float = 0.0005
const CASES: int = 160
const STEPS: int = 24
const RAILGROUPS: String = """rails
globals
1000, 0, tracks/semi
nodes
0, 0.0, 0.0, 0.0
1, 1.0, 0.0, 0.0
2, 2.0, 0.0, 0.0
3, 1.0, 0.5, 0.0
beams
0, 1
1, 2
railgroups
7, 0, 1, 2
slidenodes
3, g7, s5000
3, g8
end"""


static func meta() -> Dictionary:
    return {
        "name": "the_slide_node_is_upstreams",
        "proves": "slide nodes ride upstream's beam rails with upstream's segment tracking, loops, tolerance and break step, matching SlideNode.cpp force for force; a slide node takes a railgroups rail by g",
        "builds_on": [],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "every step of %d cases: the broken flag equal and every node force bit-identical to upstream's; g7 takes rail group 7, an undeclared g8 is refused" % CASES,
        "why": "slide nodes searched the whole rail every step, ignored loops and beams, let go a step early, and 1238 corpus rows naming a rail group were refused.",
        "budget_s": 20.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var truck: TruckParser = TruckParser.new()
    truck.parse_text(RAILGROUPS)
    if truck.slide_nodes.size() != 1 or truck.slide_nodes[0]["rail"] != PackedInt32Array([0, 1, 2]) \
            or truck.slide_nodes[0]["spring"] != 5000.0:
        return fail("the g7 slide node did not take rail group 7's nodes 0, 1, 2: %s" % [truck.slide_nodes])
    if not " | ".join(truck.errors).contains("rail group 8"):
        return fail("a slide node naming an undeclared rail group 8 was not refused: %s" % [truck.errors])

    var root: String = SourceScan.repo_root()
    if not FileAccess.file_exists(root.path_join(ORACLE)):
        return ok("rail groups read; parity skipped: the upstream oracle is not built. Run tools/build_parity.sh", 0)
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = 20261013
    var cases: Array[Dictionary] = []
    for n: int in CASES:
        cases.append(_case(rng, n))
    var lines: PackedStringArray = PackedStringArray()
    for c: Dictionary in cases:
        lines.append(_line(c))
    var path: String = root.path_join("build/parity/slide_cases.txt")
    var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    file.store_string("\n".join(lines) + "\n")
    file.close()
    var output: Array = []
    var status: int = OS.execute("/bin/sh", ["-c", "'%s' < '%s'" % [root.path_join(ORACLE), path]], output, true)
    if status != 0:
        return fail("the upstream oracle exited %d: %s" % [status, "\n".join(output)])
    var results: PackedStringArray = ("\n".join(output)).strip_edges().split("\n")
    if results.size() != CASES * STEPS:
        return fail("the oracle printed %d steps, not %d" % [results.size(), CASES * STEPS])
    var broke: int = 0
    var loops: int = 0
    var pushed: int = 0
    for i: int in cases.size():
        var c: Dictionary = cases[i]
        var ours: PackedFloat32Array = RorSolver.slide_probe(c["positions"], c["pairs"], c["rail"], c["node"],
                c["spring"], c["break"], c["tolerance"], c["path"], DT)
        var width: int = 1 + 3 * (c["positions"] as PackedVector3Array).size()
        loops += 1 if c["loop"] else 0
        for step: int in STEPS:
            var theirs: PackedStringArray = results[i * STEPS + step].split(" ", false)
            for k: int in width:
                var want: float = _f1(theirs[k].to_float())
                var have: float = ours[step * width + k]
                if want != have:
                    return fail("case %d (%s), step %d, value %d: upstream %s, ours %s" % [
                        i, c["kind"], step, k, theirs[k], String.num_scientific(have)], absf(want - have))
                if k > 0 and want != 0.0:
                    pushed += 1
            broke += 1 if theirs[0] == "1" and step == STEPS - 1 else 0
    return ok("rail groups read; %d cases (%d loops, %d broken by the end), %d steps, %d non-zero forces, all identical to upstream's SlideNode" % [
        CASES, loops, broke, CASES * STEPS, pushed], 0)


## One case: a rail of the given kind, extra beams, and a path for the slide node.
func _case(rng: RandomNumberGenerator, n: int) -> Dictionary:
    var kind: String = ["open", "loop", "gap", "open"][n % 4]
    var count: int = rng.randi_range(3, 7)
    var positions: PackedVector3Array = PackedVector3Array()
    var radius: float = rng.randf_range(0.5, 2.0)
    for k: int in count:
        if kind == "loop":
            var angle: float = TAU * float(k) / float(count)
            positions.append(_f(Vector3(cos(angle) * radius, rng.randf_range(-0.1, 0.1), sin(angle) * radius)))
        else:
            positions.append(_f(Vector3(float(k) * rng.randf_range(0.3, 1.0), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))))
    var rail: PackedInt32Array = PackedInt32Array()
    for k: int in count:
        rail.append(k)
    if kind == "loop":
        rail.append(0)
    # The rail's beams, some written the other way round, among others that are not the rail's.
    var pairs: PackedInt32Array = PackedInt32Array()
    for k: int in rail.size() - 1:
        if kind == "gap" and k == rail.size() / 2:
            continue
        if rng.randf() < 0.5:
            pairs.append_array([rail[k], rail[k + 1]])
        else:
            pairs.append_array([rail[k + 1], rail[k]])
    for k: int in rng.randi_range(0, 3):
        pairs.append_array([rng.randi_range(0, count - 1), count])
    # The slide node, last, walks the rail with an offset, sometimes jumping several segments.
    var node: int = count
    var along: float = rng.randf_range(0.0, float(rail.size() - 1))
    var path: PackedVector3Array = PackedVector3Array()
    var offset_scale: float = rng.randf_range(0.0, 0.2)
    for step: int in STEPS + 1:
        along += rng.randf_range(-0.2, 0.6) if rng.randf() < 0.85 else rng.randf_range(1.5, 3.0)
        var span: float = float(rail.size() - 1)
        var t: float = fposmod(along, span) if kind == "loop" else clampf(along, -0.5, span + 0.5)
        var seg: int = clampi(int(floor(t)), 0, rail.size() - 2)
        var point: Vector3 = positions[rail[seg]].lerp(positions[rail[seg + 1]], t - float(seg))
        point += Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * offset_scale
        path.append(_f(point))
    # Its start is the first point of the path, which the reset sees; the steps follow.
    positions.append(path[0])
    path = path.slice(1)
    var spring: float = _f1(rng.randf_range(1.0e5, 1.0e7))
    var breaking: float = INF if n % 3 != 0 else _f1(rng.randf_range(1.0e4, 1.0e6))
    var tolerance: float = 0.0 if n % 5 == 0 else _f1(rng.randf_range(0.0, 0.05))
    return {"kind": kind, "loop": kind == "loop", "positions": positions, "pairs": pairs, "rail": rail, "node": node,
            "spring": spring, "break": breaking, "tolerance": tolerance, "path": path}


func _line(c: Dictionary) -> String:
    var positions: PackedVector3Array = c["positions"]
    var pairs: PackedInt32Array = c["pairs"]
    var rail: PackedInt32Array = c["rail"]
    var path: PackedVector3Array = c["path"]
    var parts: PackedStringArray = PackedStringArray([
        "slide", str(positions.size()), str(pairs.size() / 2), str(rail.size()), str(path.size()), str(c["node"]),
        _n(c["spring"]), "inf" if c["break"] == INF else _n(c["break"]), _n(c["tolerance"]), _n(DT),
    ])
    for p: Vector3 in positions:
        parts.append_array([_n(p.x), _n(p.y), _n(p.z)])
    for k: int in pairs:
        parts.append(str(k))
    for k: int in rail:
        parts.append(str(k))
    for p: Vector3 in path:
        parts.append_array([_n(p.x), _n(p.y), _n(p.z)])
    return " ".join(parts)


## Every input a float32 already, so both sides start from the same bits.
func _f(v: Vector3) -> Vector3:
    return Vector3(_f1(v.x), _f1(v.y), _f1(v.z))


func _f1(x: float) -> float:
    return PackedFloat32Array([x])[0]


func _n(value: float) -> String:
    return String.num_scientific(value)
