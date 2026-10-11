extends GateBase
## `shocks2` and `shocks3` beams run upstream's own laws, `Actor::CalcShocks2` and `CalcShocks3`,
## on the rates their rows state.
##
## Until now a `shocks2` beam ran the plain `shocks` law on its in rates, ignoring its rebound
## rates and progression, and a `shocks3` beam was a plain beam on the beam defaults with no travel
## and no pre-compression at all. 19 vehicle files in the library declare `shocks2`; of the corpus,
## 147 declare `shocks2` and 25 `shocks3`.
##
## Two halves. The first compares the laws case by case against upstream's functions compiled from
## the pinned submodule (`tools/build_parity.sh`), across both directions, inside and past both
## bounds, soft bump on and off, and speeds either side of `shocks3`'s split and clamps. The
## second builds each kind from a row and checks the beam's force after one substep is what the law
## says for its extension and speed: the row's fields reached the law in the right places.

const ORACLE: String = "build/parity/upstream_oracle"
const TOLERANCE_RELATIVE: float = 1e-5
const SUBSTEP_HZ: float = 2000.0
const BUILT_TOLERANCE: float = 1e-4
## Rows of each kind with every rate distinct, so a field read into the wrong place shows.
const ROWS: Dictionary = {
    "shocks2": "0, 1, 50000, 2000, 2.0, 1.5, 60000, 3000, 3.0, 2.5, 0.2, 0.3, 0.9, s",
    "shocks3": "0, 1, 50000, 2000, 1.2, 0.08, 0.4, 60000, 3000, 1.1, 0.1, 0.5, 0.2, 0.3, 0.9",
}


static func meta() -> Dictionary:
    return {
        "name": "shocks2_and_shocks3_are_upstreams_laws",
        "proves": "shocks2 and shocks3 beams choose spring and damping exactly as upstream's CalcShocks2 and CalcShocks3, from the fields their rows state",
        "builds_on": ["bounded_beams_oracle"],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "every case within %s of upstream's k and d; a built beam's force within %s of -k x - d v" % [String.num_scientific(TOLERANCE_RELATIVE), String.num_scientific(BUILT_TOLERANCE)],
        "why": "shocks2 ignored its rebound rates and progression and shocks3 was a plain beam with no travel: 19 library and 172 corpus files had the wrong suspension.",
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var solver: RefCounted = ClassDB.instantiate("RorSolver") as RefCounted
    var built: String = _built_rows(solver)
    if built.begins_with("FAIL "):
        return fail(built.substr(5))
    var root: String = SourceScan.repo_root()
    if not FileAccess.file_exists(root.path_join(ORACLE)):
        return ok("rows: %s; parity skipped: the upstream oracle is not built. Run tools/build_parity.sh" % built, 0)
    var cases: Array[Dictionary] = _cases()
    var lines: PackedStringArray = PackedStringArray()
    for one: Dictionary in cases:
        var beam: PackedFloat32Array = one["beam"] as PackedFloat32Array
        var fields: PackedStringArray = PackedStringArray([one["kind_name"], "1" if one["soft"] else "0"])
        for value: float in [beam[0], beam[1], beam[2], beam[3], beam[4], beam[5], beam[6], one["x"], one["v"]]:
            fields.append(String.num_scientific(value))
        for value: float in one["rates"] as PackedFloat32Array:
            fields.append(String.num_scientific(value))
        lines.append(" ".join(fields))
    var path: String = root.path_join("build/parity/shock_cases.txt")
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
    for i: int in cases.size():
        var one: Dictionary = cases[i]
        var pair: PackedStringArray = results[i].split(" ", false)
        var theirs: Vector2 = Vector2(pair[0].to_float(), pair[1].to_float())
        var ours: Vector2 = solver.shock_law_probe(one["kind"], one["rates"], one["soft"], one["beam"], one["x"], one["v"])
        for axis: int in 2:
            var difference: float = absf(theirs[axis] - ours[axis]) / maxf(absf(theirs[axis]), 1.0)
            if difference > worst:
                worst = difference
                worst_at = i
    if worst > TOLERANCE_RELATIVE:
        var one: Dictionary = cases[worst_at]
        return fail("case %d (%s, x %.4f, v %.3f, soft %s): upstream %s, ours %s" % [worst_at, one["kind_name"],
                one["x"], one["v"], one["soft"], results[worst_at], solver.shock_law_probe(one["kind"],
                one["rates"], one["soft"], one["beam"], one["x"], one["v"])], worst)
    return ok("%d cases against upstream's CalcShocks2/3, worst %s; rows: %s" % [cases.size(), String.num_scientific(worst), built], worst)


## Builds a two-node rig of each kind from its row, checks what was parsed, then stretches and
## moves it and compares the beam's force after one substep with the law's. A summary, or "FAIL ...".
func _built_rows(probe: RefCounted) -> String:
    var report: PackedStringArray = PackedStringArray()
    for section: String in ROWS:
        var text: String = "\n".join(["shocktest", "globals", "20, 0, tracks/semi", "nodes",
                "0, 0.0, 1.0, 0.0", "1, 1.0, 1.0, 0.0", section, ROWS[section], "end"])
        var fields: PackedStringArray = TruckLexer.fields(ROWS[section])
        var bound_at: int = int(BeamRows.SHOCK_BOUND_FIELD[section])
        for state: Array in [[0.05, 0.4], [-0.1, -2.0], [0.4, 0.1], [-0.35, -0.05]]:
            var truck: TruckParser = TruckParser.new()
            if truck.parse_text(text) != "" or truck.bounded_beams.size() != 1:
                return "FAIL the %s row did not parse to one shock" % section
            var entry: Dictionary = truck.bounded_beams[0]
            var rates: PackedFloat32Array = entry["rates"] as PackedFloat32Array
            if rates.size() != bound_at - 2 or rates[0] != fields[2].to_float() or rates[-1] != fields[bound_at - 1].to_float():
                return "FAIL the %s row's rates read as %s" % [section, rates]
            var solver: RefCounted = RigBuilder.build(truck, 0.0)["solver"] as RefCounted
            solver.set_gravity(Vector3.ZERO)
            # Both ends held: a substep integrates before it evaluates beams, and a free end would
            # have moved on from the extension being checked.
            solver.set_node_immovable(0, true)
            solver.set_node_immovable(1, true)
            var origin: Vector3 = solver.get_node_position(0)
            var rest: float = solver.get_beam_rest_length(0)
            solver.set_node_position(1, origin + Vector3(rest + float(state[0]) * rest, 0.0, 0.0))
            solver.set_node_velocity(1, Vector3(float(state[1]), 0.0, 0.0))
            var length: float = solver.get_beam_length(0)
            var extension: float = length - rest
            # The beam's rate of stretch as upstream computes it: the dot product over the same fast
            # inverse square root its length is, so off the true speed by the same fraction.
            var exact: float = solver.get_node_position(1).distance_to(origin)
            var speed: float = float(state[1]) * length / exact
            solver.step(1.0 / SUBSTEP_HZ, 1)
            var beam: PackedFloat32Array = PackedFloat32Array([rest, entry["short_bound"], entry["long_bound"],
                    entry["bound_spring"], entry["bound_damp"], fields[2].to_float(), fields[3].to_float()])
            var kind: int = entry["bound"] as int
            var law: Vector2 = probe.shock_law_probe(kind, rates, entry["soft_bump"], beam, extension, speed)
            var want: float = -law.x * extension - law.y * speed
            var got: float = solver.get_beam_stress(0)
            if absf(got - want) > BUILT_TOLERANCE * maxf(absf(want), 1.0):
                return "FAIL %s at x %.3f, v %.2f: the beam pulled %.1f N, its law says %.1f" % [section, extension, state[1], got, want]
            report.append("%s x %+.3f v %+.2f: %.0f N" % [section, extension, state[1], got])
    return ", ".join(report)


## Deterministic cases: each kind, soft bump either way for shocks2, extensions across and past
## both bounds and speeds across both directions, the split and the clamps.
func _cases() -> Array[Dictionary]:
    var cases: Array[Dictionary] = []
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = 20261012
    for n: int in 600:
        var kind: int = BeamRows.BOUND_SHOCK2 if n % 2 == 0 else BeamRows.BOUND_SHOCK3
        var rest: float = rng.randf_range(0.3, 1.5)
        var short_bound: float = rng.randf_range(0.05, 0.6) if n % 7 != 0 else 0.0
        var long_bound: float = rng.randf_range(0.05, 0.6) if n % 11 != 0 else 0.0
        var beam: PackedFloat32Array = PackedFloat32Array([rest, short_bound, long_bound,
                rng.randf_range(1e5, 9e6), rng.randf_range(100.0, 8000.0),
                rng.randf_range(1e3, 2e5), rng.randf_range(10.0, 8000.0)])
        var rates: PackedFloat32Array = PackedFloat32Array()
        for i: int in (8 if kind == BeamRows.BOUND_SHOCK2 else 10):
            rates.append(rng.randf_range(0.0, 3.0) if i in [2, 3, 6, 7] or (kind == BeamRows.BOUND_SHOCK3 and i in [3, 4, 8, 9])
                    else rng.randf_range(100.0, 1e5))
        var span: float = maxf(short_bound, long_bound) * rest + 0.05
        var speeds: Array[float] = [-25.0, -4.0, -0.5, -0.1, 0.0, 0.1, 0.5, 4.0, 25.0]
        cases.append({
            "kind": kind, "kind_name": "shock2" if kind == BeamRows.BOUND_SHOCK2 else "shock3",
            "soft": kind == BeamRows.BOUND_SHOCK2 and n % 4 == 0,
            "beam": beam, "rates": rates,
            "x": rng.randf_range(-1.4, 1.4) * span,
            "v": speeds[n % speeds.size()] * rng.randf_range(0.5, 1.5),
        })
    # `shocks3`'s speed clamp only shows when the split is under it: below the split the damping
    # is the same at any speed. Speeds either side of both clamps, with splits of 0.05 m/s.
    for v: float in [0.08, 0.12, 0.149, 0.2, 19.5, 21.0, -0.08, -0.12, -0.2, -21.0]:
        cases.append({
            "kind": BeamRows.BOUND_SHOCK3, "kind_name": "shock3", "soft": false,
            "beam": PackedFloat32Array([1.0, 0.3, 0.3, 9e6, 12000.0, 50000.0, 2000.0]),
            "rates": PackedFloat32Array([50000.0, 2000.0, 1.2, 0.05, 0.4, 60000.0, 3000.0, 1.1, 0.05, 0.5]),
            "x": 0.01, "v": v,
        })
    return cases
