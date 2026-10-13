extends GateBase
## A `hydros` row follows what its options say, as upstream's `GetArgHydroOptions`, `ProcessHydro`
## and `CalcHydros` make it: `n` (or no option) the steering, `s` the steering fading out by 12 m/s,
## `a`, `r` and `e` an airplane's aileron, rudder and elevator, `u v x y g h` two of them at once,
## some reversed, averaged; each surface's state chasing its command at 4 a second and falling back
## at 1. Compared step by step with those functions compiled from the pinned submodule
## (`tools/build_parity.sh`).
##
## Ours steered with every hydro: on the Spitfire the elevators and the rudder moved with the
## ailerons, and nothing moved with the elevator or rudder keys.

const ORACLE: String = "build/parity/upstream_oracle"
const CASES: int = 200
const STEPS: int = 1200
const OPTIONS: PackedStringArray = ["", "n", "i", "s", "a", "r", "e", "u", "v", "x", "y", "g", "h", "ai", "ei", "ri", "sn", "ia", "aer", "j"]
## Upstream's flags for those options, as `ProcessHydro` builds them.
const EXPECT: Array[int] = [2, 2, 2, 1, 4, 8, 16, 20, 48, 12, 40, 24, 136, 4, 16, 8, 3, 6, 28, 0]
const MOD_DIR: String = "assets/corpus/181_supermarine-spitfire"


static func meta() -> Dictionary:
    return {
        "name": "hydros_follow_their_flags_as_upstreams",
        "proves": "hydro options are read to upstream's flags and each hydro follows the steering, speed, aileron, rudder or elevator its flags name, as CalcHydros moves it",
        "builds_on": [],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "every beam length and state of %d cases x %d steps identical to upstream's; %d option strings read to upstream's flags; on the Spitfire roll moves only the aileron hydros" % [CASES, STEPS, OPTIONS.size()],
        "why": "every hydro steered: an airplane's elevators and rudder moved with its ailerons.",
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    for i: int in OPTIONS.size():
        if CommandRows.hydro_flags(OPTIONS[i]) != EXPECT[i]:
            return fail("hydro options '%s' read as flags %d, upstream's are %d" % [OPTIONS[i], CommandRows.hydro_flags(OPTIONS[i]), EXPECT[i]])
    var report: String = "%d option strings read as upstream" % OPTIONS.size()
    var root: String = SourceScan.repo_root()
    if DirAccess.dir_exists_absolute(root.path_join(MOD_DIR)):
        var spitfire: String = _spitfire(root.path_join(MOD_DIR))
        if spitfire.begins_with("!"):
            return fail(spitfire.substr(1))
        report += "; " + spitfire
    if not FileAccess.file_exists(root.path_join(ORACLE)):
        return ok(report + "; parity skipped: the upstream oracle is not built. Run tools/build_parity.sh", 0)
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = 20261013
    var cases: Array[Dictionary] = []
    var lines: PackedStringArray = PackedStringArray()
    for n: int in CASES:
        var c: Dictionary = _case(rng)
        cases.append(c)
        lines.append(_line(c))
    var path: String = root.path_join("build/parity/hydro_cases.txt")
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
    for i: int in CASES:
        var c: Dictionary = cases[i]
        var ours: PackedStringArray = RorSolver.hydro_probe(c["rows"], c["steps"])
        for step: int in STEPS:
            var theirs: String = results[i * STEPS + step]
            if ours[step] != theirs:
                return fail("case %d (options %s), step %d:\n upstream %s\n ours     %s" % [i, c["options"], step, theirs, ours[step]])
    return ok(report + "; %d cases x %d steps identical to upstream's" % [CASES, STEPS], 0)


## The Spitfire held at full roll: its aileron hydros (`ai`) move, its elevator (`ei`) and rudder
## (`ri`) hydros do not; then full elevator moves the elevator ones.
func _spitfire(mod_dir: String) -> String:
    var rig: Dictionary = RigBuilder.from_file(mod_dir, "spitfire_Vb.airplane", 0.0)
    var truck: TruckParser = rig["truck"]
    var solver: RorSolver = rig["solver"]
    solver.set_gravity(Vector3.ZERO)
    var rest: PackedFloat32Array = PackedFloat32Array()
    for hydro: Dictionary in truck.hydros:
        rest.append(solver.get_beam_rest_length(hydro["beam"]))
    solver.set_aero_controls(1.0, 0.0, 0.0, 0)
    solver.step(1.0 / 2000.0, 1000)
    var moved: Dictionary = {}
    for i: int in truck.hydros.size():
        var hydro: Dictionary = truck.hydros[i]
        var flags: int = hydro["flags"]
        var changed: bool = absf(solver.get_beam_rest_length(hydro["beam"]) - rest[i]) > 1e-4
        if changed != (flags == 4):
            return "!held at full roll, the Spitfire's hydro %d (flags %d) %s" % [i, flags, "moved" if changed else "stayed"]
        moved[flags] = moved.get(flags, 0) + (1 if changed else 0)
    solver.set_aero_controls(0.0, 0.0, 1.0, 0)
    solver.step(1.0 / 2000.0, 2000)
    for i: int in truck.hydros.size():
        var hydro: Dictionary = truck.hydros[i]
        var changed: bool = absf(solver.get_beam_rest_length(hydro["beam"]) - rest[i]) > 1e-4
        if changed != (hydro["flags"] == 16):
            return "!held at full elevator, the Spitfire's hydro %d (flags %d) %s" % [i, hydro["flags"], "moved" if changed else "stayed"]
    return "on the Spitfire roll moves its %d aileron hydros only, elevator its elevator ones only" % moved.get(4, 0)


func _case(rng: RandomNumberGenerator) -> Dictionary:
    var rows: Array = []
    var options: PackedStringArray = PackedStringArray()
    for k: int in rng.randi_range(1, 4):
        var option: String = OPTIONS[rng.randi_range(0, OPTIONS.size() - 1)]
        options.append(option)
        rows.append([CommandRows.hydro_flags(option), _f1(rng.randf_range(-0.5, 0.5)), _f1(rng.randf_range(0.2, 2.0))])
    var steps: Array = []
    var held: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0, 0])
    for step: int in STEPS:
        if step % rng.randi_range(100, 400) == 0:
            for k: int in 4:
                var pick: int = rng.randi_range(0, 3)
                held[k] = [0.0, 1.0, -1.0, _f1(rng.randf_range(-1.0, 1.0))][pick]
            held[4] = _f1(rng.randf_range(0.0, 20.0))
        steps.append(held.duplicate())
    return {"rows": rows, "steps": steps, "options": options}


func _line(c: Dictionary) -> String:
    var parts: PackedStringArray = PackedStringArray(["hydro", str((c["rows"] as Array).size()), str(STEPS)])
    for row: Array in c["rows"]:
        parts.append_array([str(row[0]), _n(row[1]), _n(row[2])])
    for step: PackedFloat32Array in c["steps"]:
        for k: int in step.size():
            parts.append(_n(step[k]))
    return " ".join(parts)


func _f1(x: float) -> float:
    return PackedFloat32Array([x])[0]


func _n(value: float) -> String:
    return String.num_scientific(value)
