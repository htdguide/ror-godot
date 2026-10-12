extends GateBase
## A rig that declares `fusedrag` is dragged as one body by upstream's `Actor::CalcFuseDrag`: the
## front node's wind, the tropospheric air density at its altitude, and a flat plate of the
## fuselage's width, shared over every node. Compared case by case with the function compiled
## from the pinned submodule (`tools/build_parity.sh`).
##
## Ours used the exact power where upstream uses its bit-trick `approx_pow`, and float literals
## where upstream's are doubles, so above sea level the density, and with it the drag, differed.
## The airfoil term upstream adds is multiplied by the fuselage's side area, which its spawner makes
## zero by setting the back node to the front one; the shim's airfoil answers anything finite.

const ORACLE: String = "build/parity/upstream_oracle"
const TOLERANCE_RELATIVE: float = 2e-8


static func meta() -> Dictionary:
    return {
        "name": "fuselage_drag_is_upstreams",
        "proves": "a fusedrag rig's per-node drag is upstream's CalcFuseDrag for its front node's wind, altitude and fuselage width",
        "builds_on": [],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "every case within %s of upstream's force" % String.num_scientific(TOLERANCE_RELATIVE),
        "why": "the fuselage drag used an exact power and float literals where upstream uses approx_pow and doubles, so it differed above sea level.",
        "budget_s": 10.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var root: String = SourceScan.repo_root()
    if not FileAccess.file_exists(root.path_join(ORACLE)):
        return ok("skipped: the upstream oracle is not built. Run tools/build_parity.sh", 0)
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = 20261012
    var cases: Array[Array] = []
    for n: int in 120:
        var velocity: Vector3 = Vector3(rng.randf_range(-40.0, 40.0), rng.randf_range(-5.0, 5.0), rng.randf_range(-40.0, 40.0))
        cases.append([[10, 100, 500][n % 3], [0.0, 0.05, 0.1, 1.0, 2.5][n % 5], velocity, [-50.0, 0.0, 120.0, 800.0, 3000.0][n % 5 if n % 7 else 0] + rng.randf_range(0.0, 30.0)])
    var lines: PackedStringArray = PackedStringArray()
    for c: Array in cases:
        var v: Vector3 = c[2]
        lines.append("fuse %d %s %s %s %s %s" % [c[0], _n(c[1]), _n(v.x), _n(v.y), _n(v.z), _n(c[3])])
    var path: String = root.path_join("build/parity/fuse_cases.txt")
    var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    file.store_string("\n".join(lines) + "\n")
    file.close()
    var output: Array = []
    var status: int = OS.execute("/bin/sh", ["-c", "'%s' < '%s'" % [root.path_join(ORACLE), path]], output, true)
    if status != 0:
        return fail("the upstream oracle exited %d: %s" % [status, "\n".join(output)])
    var results: PackedStringArray = ("\n".join(output)).strip_edges().split("\n")
    var worst: float = 0.0
    for i: int in cases.size():
        var c: Array = cases[i]
        var solver: RefCounted = ClassDB.instantiate("RorSolver") as RefCounted
        solver.add_node(Vector3(0.0, c[3], 0.0), 1.0)
        solver.set_node_velocity(0, c[2])
        for k: int in range(1, c[0]):
            solver.add_node(Vector3(float(k) * 0.01, 0.0, 0.0), 1.0)
        solver.set_fuselage_drag(0, c[1], true)
        var forces: PackedVector3Array = solver.air_drag_probe()
        var theirs: PackedStringArray = results[i].split(" ", false)
        for node: int in [0, int(c[0]) - 1]:
            for axis: int in 3:
                var want: float = theirs[axis].to_float()
                var difference: float = absf(want - forces[node][axis]) / maxf(absf(want), 1e-6)
                if difference > TOLERANCE_RELATIVE:
                    return fail("case %d (%d nodes, width %.2f, wind %s, altitude %.1f m), node %d axis %d: upstream %s, ours %s" % [
                        i, c[0], c[1], c[2], c[3], node, axis, theirs[axis], _n(forces[node][axis])], difference)
                worst = maxf(worst, difference)
    return ok("%d cases against upstream's CalcFuseDrag, altitudes -50 to 3030 m, worst %s" % [cases.size(), String.num_scientific(worst)], worst)


func _n(value: float) -> String:
    return String.num_scientific(value)
