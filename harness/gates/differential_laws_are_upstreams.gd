extends GateBase
## The four differential laws, split, open, viscous and locked, are upstream's arithmetic: case by
## case against `Differential::CalcSeparateDiff`, `CalcOpenDiff`, `CalcViscousDiff` and
## `CalcLockedDiff` compiled from the pinned submodule (`tools/build_parity.sh`).
##
## `a_differential_shares_torque_by_its_kind` holds what the laws do to a driven truck; this holds
## the laws themselves, including the open differential's even split below 1 m/s and its 0.1-0.9
## clamp, and the locked one's wind carried from one substep to the next.

const ORACLE: String = "build/parity/upstream_oracle"
const TOLERANCE_RELATIVE: float = 1e-6
const DT: float = 0.0005
const TYPES: String = "sovl"


static func meta() -> Dictionary:
    return {
        "name": "differential_laws_are_upstreams",
        "proves": "split, open, viscous and locked differentials give upstream's two torques and wind for the same speeds, torque and wind",
        "builds_on": ["a_differential_shares_torque_by_its_kind"],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "every case within %s of upstream's torques and wind" % String.num_scientific(TOLERANCE_RELATIVE),
        "why": "the laws were ported by reading, with no case run against upstream's own code.",
        "budget_s": 20.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var root: String = SourceScan.repo_root()
    if not FileAccess.file_exists(root.path_join(ORACLE)):
        return ok("skipped: the upstream oracle is not built. Run tools/build_parity.sh", 0)
    var solver: RefCounted = ClassDB.instantiate("RorSolver") as RefCounted
    var cases: Array[Array] = _cases()
    var lines: PackedStringArray = PackedStringArray()
    for one: Array in cases:
        var fields: PackedStringArray = PackedStringArray(["diff", one[0]])
        for i: int in range(1, 6):
            fields.append(String.num_scientific(float(one[i])))
        lines.append(" ".join(fields))
    var path: String = root.path_join("build/parity/diff_cases.txt")
    var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    file.store_string("\n".join(lines) + "\n")
    file.close()
    var output: Array = []
    var status: int = OS.execute("/bin/sh", ["-c", "'%s' < '%s'" % [root.path_join(ORACLE), path]], output, true)
    if status != 0:
        return fail("the upstream oracle exited %d: %s" % [status, "\n".join(output)])
    var results: PackedStringArray = ("\n".join(output)).strip_edges().split("\n")
    if results.size() != cases.size():
        return fail("the oracle returned %d results for %d cases" % [results.size(), cases.size()])
    var worst: float = 0.0
    var worst_at: int = 0
    var per_type: Dictionary = {}
    for i: int in cases.size():
        var one: Array = cases[i]
        var theirs: PackedStringArray = results[i].split(" ", false)
        var ours: PackedFloat32Array = solver.differential_probe(one[0], one[1], one[2], one[3], one[4], one[5])
        for j: int in 3:
            var difference: float = absf(theirs[j].to_float() - ours[j]) / maxf(absf(theirs[j].to_float()), 1.0)
            if difference > worst:
                worst = difference
                worst_at = i
        per_type[one[0]] = int(per_type.get(one[0], 0)) + 1
    if worst > TOLERANCE_RELATIVE:
        var one: Array = cases[worst_at]
        return fail("case %d (%s, speeds %.3f / %.3f, torque %.1f, wind %.5f): upstream %s, ours %s" % [
                worst_at, one[0], one[1], one[2], one[3], one[5], results[worst_at],
                solver.differential_probe(one[0], one[1], one[2], one[3], one[4], one[5])], worst)
    return ok("%d cases (%s) against upstream's four laws, worst %s" % [cases.size(), per_type,
            String.num_scientific(worst)], worst)


## [type, speed_a, speed_b, in_torque, dt, wind] cases: speeds either side of the open
## differential's 1 m/s and of each other, both signs, and wind from none to past a turn.
func _cases() -> Array[Array]:
    var cases: Array[Array] = []
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = 20261012
    for n: int in 800:
        var scale: float = [0.5, 2.0, 30.0][n % 3]
        cases.append([TYPES[n % 4], rng.randf_range(-scale, scale), rng.randf_range(-scale, scale),
                rng.randf_range(-5000.0, 5000.0), DT, rng.randf_range(-0.05, 0.05) if n % 5 else 0.0])
    # The open differential's edges: one wheel stopped, both at exactly 1 m/s, one either side.
    for pair: Vector2 in [Vector2(0.0, 5.0), Vector2(1.0, 1.0), Vector2(1.0, 3.0), Vector2(0.999, 3.0), Vector2(1.001, 3.0),
            Vector2(-2.0, 18.0), Vector2(30.0, 0.5)]:
        cases.append(["o", pair.x, pair.y, 1000.0, DT, 0.0])
    return cases
