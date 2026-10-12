extends GateBase
## A `wings` row is upstream's wing: `ParseWing` reads it, `Airfoil` loads its X-Plane polar, and
## `FlexAirfoil::updateForces` puts lift, drag, induced drag and the pitching moment on its eight
## corners from the wind over it, its angle of attack, its control surface's deflection and the air
## density at its height; a panel stretched past twice its area breaks and pushes no more. Compared
## step by step with those functions compiled from the pinned submodule (`tools/build_parity.sh`),
## on the game's own airfoils and those the corpus ships.
##
## Ours read no wings: 107 corpus files declare them, and no aircraft flew.
##
## Wind comes from every side, including behind the wing, so the polar is read across its whole
## range; the panel turns, climbs and is sometimes stretched to breaking.

const ORACLE: String = "build/parity/upstream_oracle"
const CASES: int = 160
const STEPS: int = 30
const AIRFOILS: PackedStringArray = [
    "vendor/rigs-of-rods/resources/airfoils/NACA0009.afl", "vendor/rigs-of-rods/resources/airfoils/Clark-Y.afl",
    "vendor/rigs-of-rods/resources/airfoils/NACA64.1.412.afl", "vendor/rigs-of-rods/resources/airfoils/NACA64.3.618.afl",
    "assets/corpus/200_soukhoi-su-37/flanker_tip.afl", "-",
]
const TYPES: String = "nabferSTcdghUVij"
## A run of two wings (the second's node 1 the first's node 0) and a tail apart from it, for the
## spawner's induced drag: the run's span and summed area on its two ends, the tail its own.
const RUN: String = """plane
globals
1000, 0, tracks/semi
nodes
0, 2, 0, 0
1, 4, 0, 0
2, 2, 0.1, 0
3, 4, 0.1, 0
4, 2, 0, 1
5, 4, 0, 1
6, 2, 0.1, 1
7, 4, 0.1, 1
8, 0, 0, 0
9, 0, 0.1, 0
10, 0, 0, 1
11, 0, 0.1, 1
12, 0, 0, 5
13, 1, 0, 5
14, 0, 0.1, 5
15, 1, 0.1, 5
16, 0, 0, 5.5
17, 1, 0, 5.5
18, 0, 0.1, 5.5
19, 1, 0.1, 5.5
beams
0, 1
wings
0, 1, 2, 3, 4, 5, 6, 7, 0, 0, 1, 0, 0, 1, 1, 1, n, -1, -1, -1, NACA0009.afl
8, 0, 9, 2, 10, 4, 11, 6, 0, 0, 1, 0, 0, 1, 1, 1, n, -1, -1, -1, NACA0009.afl
12, 13, 14, 15, 16, 17, 18, 19, 0, 0, 1, 0, 0, 1, 1, 1, e, 0.7, 20, 20, NACA0009.afl
end"""
const WING_ROW: String = """plane
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
0, 1, 2, 3, 4, 5, 6, 7, 0, 0, 1, 0, 0, 1, 1, 1, a, 0.75, -20, 20, NACA0009.afl, 1.2
0, 1, 2, 3, 4, 5, 6, 7, 0, 0, 1, 0, 0, 1, 1, 1
end"""


static func meta() -> Dictionary:
    return {
        "name": "the_wing_is_upstreams",
        "proves": "wing rows are read and their airfoils loaded and flown as upstream's ParseWing, Airfoil and FlexAirfoil do, force for force",
        "builds_on": [],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "every node force, angle of attack and break of %d cases x %d steps bit-identical to upstream's; a wing naming no airfoil skipped" % [CASES, STEPS],
        "why": "107 corpus files declare wings and none was read: no aircraft flew.",
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var truck: TruckParser = TruckParser.new()
    truck.parse_text(WING_ROW)
    if truck.links.wings.size() != 2 or truck.links.wings[0]["type"] != "a" or truck.links.wings[0]["airfoil"] != "NACA0009.afl" \
            or truck.links.wings[0]["efficacy"] != 1.2:
        return fail("the wings rows read as %s" % [truck.links.wings])
    var solver: RorSolver = RigBuilder.build(truck, 0.0)["solver"] as RorSolver
    if solver.wing_count() != 1:
        return fail("%d wings were built; upstream skips the one naming no airfoil" % solver.wing_count())
    var run: TruckParser = TruckParser.new()
    run.parse_text(RUN)
    var plane: RorSolver = RigBuilder.build(run, 0.0)["solver"] as RorSolver
    # Upstream's rule: the run's span is node 1 of its first wing to node 0 of its last, 4 m; its
    # area the two panels' 2 + 2 m2, its first wing the right end and its last the left; the tail,
    # closing the vehicle, both ends at once, so its last call, the left one, stands: 1 m, 0.5 m2.
    var want: Array[Vector3] = [Vector3(4.0, 4.0, 0.0), Vector3(4.0, 4.0, 1.0), Vector3(1.0, 0.5, 1.0)]
    for i: int in 3:
        if plane.wing_state(i)["induced"] != want[i]:
            return fail("wing %d's induced drag is %s (span, area, left); upstream's spawner gives %s" % [i, plane.wing_state(i)["induced"], want[i]])
    var report: String = "rows read, the airfoil-less wing skipped, induced drag spans and areas as upstream's spawner sets them"

    var root: String = SourceScan.repo_root()
    if not FileAccess.file_exists(root.path_join(ORACLE)):
        return ok(report + "; parity skipped: the upstream oracle is not built. Run tools/build_parity.sh", 0)
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = 20261013
    var cases: Array[Dictionary] = []
    var lines: PackedStringArray = PackedStringArray()
    for n: int in CASES:
        var c: Dictionary = _case(rng, root)
        if c.is_empty():
            continue
        cases.append(c)
        lines.append(_line(c))
    var path: String = root.path_join("build/parity/wing_cases.txt")
    var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    file.store_string("\n".join(lines) + "\n")
    file.close()
    var output: Array = []
    var status: int = OS.execute("/bin/sh", ["-c", "'%s' < '%s'" % [root.path_join(ORACLE), path]], output, true)
    if status != 0:
        return fail("the upstream oracle exited %d: %s" % [status, "\n".join(output)])
    var results: PackedStringArray = ("\n".join(output)).strip_edges().split("\n")
    if results.size() != cases.size() * STEPS:
        return fail("the oracle printed %d steps, not %d" % [results.size(), cases.size() * STEPS])
    var broke: int = 0
    var pushed: int = 0
    for i: int in cases.size():
        var c: Dictionary = cases[i]
        var afl: String = "" if c["afl"] == "-" else FileAccess.get_file_as_string(root.path_join(c["afl"]))
        var ours: PackedStringArray = RorSolver.wing_probe(afl, c["params"], c["start"], c["steps"])
        for step: int in STEPS:
            var theirs: String = results[i * STEPS + step]
            if ours[step] != theirs:
                return fail("case %d (%s, %s), step %d:\n upstream %s\n ours     %s" % [i, c["afl"], c["params"][0], step, theirs, ours[step]])
            pushed += 1 if not theirs.begins_with("0 0 0 0 0 0") else 0
        broke += 1 if results[i * STEPS + STEPS - 1].ends_with(" 1") else 0
    return ok(report + "; %d cases x %d steps bit-identical to upstream's, %d steps pushing, %d wings broken" % [
        cases.size(), STEPS, pushed, broke], 0)


func _case(rng: RandomNumberGenerator, root: String) -> Dictionary:
    var afl: String = AIRFOILS[rng.randi_range(0, AIRFOILS.size() - 1)]
    if afl != "-" and not FileAccess.file_exists(root.path_join(afl)):
        return {}
    var span: float = rng.randf_range(1.0, 4.0)
    var chord: float = rng.randf_range(0.4, 2.0)
    var thick: float = rng.randf_range(0.05, 0.2)
    var basis: Basis = Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-PI, PI), rng.randf_range(-0.5, 0.5)))
    var origin: Vector3 = Vector3(rng.randf_range(-5.0, 5.0), rng.randf_range(0.0, 4000.0), rng.randf_range(-5.0, 5.0))
    var local: Array[Vector3] = [Vector3(0, 0, 0), Vector3(span, 0, 0), Vector3(0, thick, 0), Vector3(span, thick, 0),
            Vector3(0, 0, chord), Vector3(span, 0, chord), Vector3(0, thick, chord), Vector3(span, thick, chord)]
    var start: PackedVector3Array = PackedVector3Array()
    for p: Vector3 in local:
        start.append(_f(origin + basis * p))
    var type: String = TYPES[rng.randi_range(0, TYPES.length() - 1)]
    var params: Array = [type, _f1(rng.randf_range(0.5, 1.0)) if rng.randf() < 0.7 else -1.0,
            _f1(rng.randf_range(5.0, 30.0)) if rng.randf() < 0.7 else -1.0, _f1(rng.randf_range(5.0, 30.0)) if rng.randf() < 0.7 else -1.0,
            _f1(rng.randf_range(0.5, 1.5)), true, rng.randf() < 0.5, _f1(rng.randf_range(4.0, 20.0)), _f1(rng.randf_range(4.0, 40.0)),
            rng.randf() < 0.5]
    var steps: Array = []
    var stretch: float = 1.0
    var wind_dir: Vector3 = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.5, 0.5), rng.randf_range(-1.0, 1.0)).normalized()
    for step: int in STEPS:
        if rng.randf() < 0.012:
            stretch = rng.randf_range(1.5, 3.0)
        wind_dir = (wind_dir + Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4))).normalized()
        var at: PackedVector3Array = PackedVector3Array()
        for k: int in 8:
            var p: Vector3 = local[k] * Vector3(stretch, 1.0, 1.0) + Vector3(rng.randf_range(-0.01, 0.01), rng.randf_range(-0.01, 0.01), rng.randf_range(-0.01, 0.01))
            at.append(_f(origin + basis * p))
        var speed: float = rng.randf_range(0.0, 90.0)
        var v0: Vector3 = _f(wind_dir * speed + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)))
        var v1: Vector3 = _f(wind_dir * speed + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)))
        steps.append([_f1(rng.randf_range(-1.0, 1.0)), at, v0, v1])
    return {"afl": afl, "params": params, "start": start, "steps": steps}


func _line(c: Dictionary) -> String:
    var p: Array = c["params"]
    var path: String = c["afl"] if c["afl"] == "-" else SourceScan.repo_root().path_join(c["afl"])
    var parts: PackedStringArray = PackedStringArray(["wing", path, p[0], _n(p[1]), _n(p[2]), _n(p[3]), _n(p[4]),
            "1" if p[5] else "0", "1" if p[6] else "0", _n(p[7]), _n(p[8]), "1" if p[9] else "0", str(STEPS)])
    for v: Vector3 in c["start"] as PackedVector3Array:
        parts.append_array([_n(v.x), _n(v.y), _n(v.z)])
    for step: Array in c["steps"]:
        parts.append(_n(step[0]))
        for v: Vector3 in step[1] as PackedVector3Array:
            parts.append_array([_n(v.x), _n(v.y), _n(v.z)])
        for v: Vector3 in [step[2], step[3]]:
            parts.append_array([_n(v.x), _n(v.y), _n(v.z)])
    return " ".join(parts)


func _f(v: Vector3) -> Vector3:
    return Vector3(_f1(v.x), _f1(v.y), _f1(v.z))


func _f1(x: float) -> float:
    return PackedFloat32Array([x])[0]


func _n(value: float) -> String:
    return String.num_scientific(value)
