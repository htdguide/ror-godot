extends GateBase
## A `cab` triangle with a buoyant option (b, r, s, D, F, S) is upstream's buoycab: `Buoyance`
## splits it at the waterline and pushes it by the water it displaces and drags it by the water it
## moves through, and `Actor::CalcBuoyance` samples that every tenth substep from the nodes as they
## are and as they will be, the substeps between interpolated. The sea is the terrain's, flat at its
## water height (upstream's waves are off unless a player turns them on). Compared step by step with
## those functions compiled from the pinned submodule (`tools/build_parity.sh`), then a corpus boat
## dropped on water and on a dry map.
##
## Ours read the options as nothing but contact: every boat sank to the sea bed.

const ORACLE: String = "build/parity/upstream_oracle"
const CASES: int = 200
const STEPS: int = 60
const MOD_DIR: String = "assets/corpus/189_weasel-class-boat"
const BOAT: String = "780dUIDweasel.boat"
const WATER: float = 10.0
const SUBSTEP: float = 1.0 / 2000.0


static func meta() -> Dictionary:
    return {
        "name": "a_boat_floats_as_upstreams",
        "proves": "buoyant cab triangles float and drag a rig as upstream's Buoyance and CalcBuoyance do, on the terrain's water",
        "builds_on": [],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "every node force of %d cases x %d substeps identical to upstream's; the Weasel floats within 2 m of the water after 10 s and sinks to the bed without it" % [CASES, STEPS],
        "why": "buoyant cabs were read as contact only: every boat sank.",
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    # The spawner's buoycabs: one per buoyant option, b r s then any of D F S, in that order.
    var options: Dictionary = {"b": [0], "r": [1], "s": [2], "D": [0], "cF": [0], "S": [0], "bD": [0, 0], "srb": [0, 1, 2], "c": [], "n": []}
    for option: String in options:
        if RigBuilder._buoyancy_types(option) != (options[option] as Array):
            return fail("cab options '%s' made buoycabs %s; upstream's spawner makes %s" % [option, RigBuilder._buoyancy_types(option), options[option]])
    var root: String = SourceScan.repo_root()
    var report: String = ""
    var mod_dir: String = root.path_join(MOD_DIR)
    if DirAccess.dir_exists_absolute(mod_dir):
        var afloat: float = _drop(mod_dir, true)
        var dry: float = _drop(mod_dir, false)
        if absf(afloat - WATER) > 2.0 or dry > WATER - 5.0:
            return fail("the Weasel's middle sits %.2f m on water at %.0f m and %.2f m without it; it should float near the water and sink to the bed" % [afloat, WATER, dry], afloat)
        report = "the Weasel floats at %.2f m on water at %.0f m and sinks to %.2f m on a dry map" % [afloat, WATER, dry]
    else:
        report = "the Weasel is not present"
    if not FileAccess.file_exists(root.path_join(ORACLE)):
        return ok(report + "; parity skipped: the upstream oracle is not built. Run tools/build_parity.sh", 0)
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = 20261014
    var cases: Array = []
    var lines: PackedStringArray = PackedStringArray()
    for n: int in CASES:
        var count: int = rng.randi_range(3, 8)
        var cabs: Array = []
        var parts: PackedStringArray = PackedStringArray()
        for c: int in rng.randi_range(1, 6):
            var cab: PackedInt32Array = PackedInt32Array([rng.randi_range(0, count - 1), rng.randi_range(0, count - 1), rng.randi_range(0, count - 1), rng.randi_range(0, 2)])
            cabs.append(cab)
            parts.append_array([str(cab[0]), str(cab[1]), str(cab[2]), str(cab[3])])
        var used: int = 0
        for cab: PackedInt32Array in cabs:
            used = maxi(used, maxi(cab[0], maxi(cab[1], cab[2])) + 1)
        var height: float = rng.randf_range(-5.0, 50.0)
        var positions: PackedVector3Array = PackedVector3Array()
        var velocities: PackedVector3Array = PackedVector3Array()
        for k: int in used:
            positions.append(Vector3(rng.randf_range(-3.0, 3.0), height + rng.randf_range(-2.0, 1.0), rng.randf_range(-3.0, 3.0)))
            velocities.append(Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(-3.0, 3.0), rng.randf_range(-6.0, 6.0)))
        var steps: Array = []
        var line: PackedStringArray = PackedStringArray(["buoy", str(used), str(cabs.size()), str(STEPS), _n(height)])
        line.append_array(parts)
        for step: int in STEPS:
            var v: PackedVector3Array = PackedVector3Array()
            for k: int in used:
                positions[k] += velocities[k] * SUBSTEP
                velocities[k] += Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))
                positions[k] = Vector3(_f1(positions[k].x), _f1(positions[k].y), _f1(positions[k].z))
                velocities[k] = Vector3(_f1(velocities[k].x), _f1(velocities[k].y), _f1(velocities[k].z))
            v.append_array(positions)
            v.append_array(velocities)
            steps.append(v)
            for p: Vector3 in v:
                line.append_array([_n(p.x), _n(p.y), _n(p.z)])
        cases.append([height, cabs, steps])
        lines.append(" ".join(line))
    var path: String = root.path_join("build/parity/buoy_cases.txt")
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
    var pushed: int = 0
    for i: int in CASES:
        var ours: PackedStringArray = RorSolver.buoyancy_probe(cases[i][0], cases[i][1], cases[i][2])
        for step: int in STEPS:
            var theirs: String = results[i * STEPS + step].strip_edges()
            if ours[step].strip_edges() != theirs:
                return fail("case %d, step %d:\n upstream %s\n ours     %s" % [i, step, theirs, ours[step]])
            for value: String in theirs.split(" ", false):
                if value.to_float() != 0.0:
                    pushed += 1
                    break
    return ok(report + "; %d cases x %d substeps identical to upstream's, %d of them pushed" % [CASES, STEPS, pushed], 0)


## The middle height of the Weasel 10 s after it is let go just above water at `WATER`, or with no
## water, the bed 20 m below.
func _drop(mod_dir: String, water: bool) -> float:
    var rig: Dictionary = RigBuilder.from_file(mod_dir, BOAT, 0.0)
    var solver: RorSolver = rig["solver"]
    var truck: TruckParser = rig["truck"]
    solver.set_ground(WATER - 20.0, true)
    solver.set_water(water, WATER)
    RigBuilder.place(solver, truck, Vector3(0, WATER + 0.5, 0), 0.0, 0.0)
    solver.step(SUBSTEP, 20000)
    var positions: PackedVector3Array = solver.get_positions()
    var box: AABB = AABB(positions[0], Vector3.ZERO)
    for p: Vector3 in positions:
        box = box.expand(p)
    return box.get_center().y


func _f1(x: float) -> float:
    return PackedFloat32Array([x])[0]


func _n(value: float) -> String:
    return String.num_scientific(value)
