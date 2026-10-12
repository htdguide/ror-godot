extends GateBase
## An `engturbo` row is upstream's turbo: `ParseEngturbo` reads it, `SetTurboOptions` sets it up,
## the turbo pass at the top of `Engine::UpdateEngine` spins it with the throttle and the engine,
## and `getTurboPower` adds its torque to the engine's, as version 1 extra torque or version 2
## boost through a blow-off valve, a wastegate and anti-lag. Compared step by step with that code
## compiled from the pinned submodule (`tools/build_parity.sh`), anti-lag's `frand` included:
## upstream's is a fixed sequence from 1.
##
## Ours had no turbo: 61 corpus files declare one, and every one of them drove without it.
##
## Cases cover both versions, one to four turbos, an operating rpm, the blow-off valve, the
## wastegate's flutter, compressor surge and anti-lag, under throttle that comes and goes with the
## engine sweeping its range and sometimes stalled.

const ORACLE: String = "build/parity/upstream_oracle"
const DT: float = 0.0005
const CASES: int = 120
const STEPS: int = 2000
const DRAGRAM: String = "assets/corpus/607_1994-dodge-ram-pack"


static func meta() -> Dictionary:
    return {
        "name": "the_turbo_is_upstreams",
        "proves": "engturbo rows are read as upstream reads them and the turbo spins and adds torque as upstream's SetTurboOptions, turbo pass and getTurboPower do, bit for bit",
        "builds_on": [],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "every turbo rpm, blow-off rpm and added torque of %d cases x %d steps bit-identical to upstream's; a short row's missing parameters 9999 and five turbos read as four; the Dodge Ram's turbo builds boost under throttle" % [CASES, STEPS],
        "why": "61 corpus files declare a turbo and none had one.",
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var drive: Dictionary = DriveRows.empty()
    var error: String = DriveRows.read("engturbo", PackedStringArray(["2", "0.5", "5", "17", "1250"]), drive)
    var turbo: Dictionary = drive.get("turbo", {})
    if error != "" or turbo.get("count", 0) != 4 or (turbo["params"] as PackedFloat32Array)[2] != 9999.0 \
            or (turbo["params"] as PackedFloat32Array)[1] != 1250.0:
        return fail("the row '2, 0.5, 5, 17, 1250' read as %s (%s); upstream: four turbos, param2 1250, the rest 9999" % [turbo, error])
    if DriveRows.read("engturbo", PackedStringArray(["1", "1", "1"]), DriveRows.empty()) == "":
        return fail("a three-field engturbo row was taken; upstream needs four")
    var report: String = "rows read as upstream"

    var mod_dir: String = SourceScan.repo_root().path_join(DRAGRAM)
    if DirAccess.dir_exists_absolute(mod_dir):
        var rig: Dictionary = RigBuilder.from_file(mod_dir, "1994DodgeRam12VDrag.truck", 0.0)
        var solver: RorSolver = rig["solver"]
        solver.set_gravity(Vector3.ZERO)
        solver.start_engine()
        solver.set_throttle(1.0)
        solver.step(DT, 2000)
        if solver.turbo_psi() <= 0.0:
            return fail("the Dodge Ram's turbo made no boost in a second of full throttle")
        # The boost reaches the crank: version 2 adds 6.8% of the engine's torque per psi.
        var bare: Dictionary = RigBuilder.from_file(mod_dir, "1994DodgeRam12VDrag.truck", 0.0)
        var truck: TruckParser = bare["truck"]
        truck.drivetrain.erase("turbo")
        var unboosted: RorSolver = RigBuilder.build(truck, 0.0)["solver"]
        var added: float = solver.engine_power_at(2000.0) - unboosted.engine_power_at(2000.0)
        var want: float = solver.turbo_psi() * 6.8 * float(truck.drivetrain["torque_nm"]) / 100.0
        if absf(added - want) > 1e-3 * want:
            return fail("at %.2f psi the engine gained %.2f Nm; upstream's getTurboPower adds %.2f" % [solver.turbo_psi(), added, want], added)
        report += "; the Dodge Ram at %.2f psi after a second of full throttle, +%.1f Nm at the crank" % [solver.turbo_psi(), added]

    var root: String = SourceScan.repo_root()
    if not FileAccess.file_exists(root.path_join(ORACLE)):
        return ok(report + "; parity skipped: the upstream oracle is not built. Run tools/build_parity.sh", 0)
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = 20261014
    var cases: Array[Dictionary] = []
    var lines: PackedStringArray = PackedStringArray()
    for n: int in CASES:
        var c: Dictionary = _case(rng, n)
        cases.append(c)
        lines.append(_line(c))
    var path: String = root.path_join("build/parity/turbo_cases.txt")
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
    var boosted: int = 0
    for i: int in CASES:
        var c: Dictionary = cases[i]
        var ours: PackedFloat32Array = RorSolver.turbo_probe(c["version"], c["inertia"], c["count"], c["params"],
                c["acc"], c["cur_acc"], c["rpm"], c["running"], c["max_rpm"], c["torque"], DT)
        for step: int in STEPS:
            var theirs: PackedStringArray = results[i * STEPS + step].split(" ", false)
            for k: int in 9:
                var want: float = _f1(theirs[k].to_float())
                var have: float = ours[step * 9 + k]
                if want != have:
                    return fail("case %d (version %d, %d turbos, %s), step %d, value %d: upstream %s, ours %s" % [
                        i, c["version"], c["count"], c["kind"], step, k, theirs[k], String.num_scientific(have)], absf(want - have))
        boosted += 1 if ours[(STEPS - 1) * 9 + 8] != 0.0 else 0
    return ok(report + "; %d cases x %d steps identical to upstream's turbo, %d ending with added torque" % [CASES, STEPS, boosted], 0)


func _case(rng: RandomNumberGenerator, n: int) -> Dictionary:
    var version: int = 1 if n % 3 == 0 else 2
    var count: int = rng.randi_range(1, 4)
    var params: PackedFloat32Array = PackedFloat32Array()
    for k: int in 11:
        params.append(9999.0)
    var kind: String = "plain"
    params[0] = _f1(rng.randf_range(100.0, 3000.0) if version == 1 else rng.randf_range(8.0, 30.0))
    if n % 4 != 0:
        params[1] = _f1(rng.randf_range(0.0, 2500.0))
    if version == 2:
        if n % 2 == 0:
            params[2] = 1.0
            params[3] = _f1(rng.randf_range(5.0, 15.0))
            kind = "bov"
        if n % 5 < 3:
            params[4] = 1.0
            params[5] = _f1(rng.randf_range(5.0, 25.0))
            params[6] = _f1(rng.randf_range(0.0, 0.1))
            kind += "+wastegate"
        if n % 7 < 3:
            params[7] = 1.0
            params[8] = _f1(rng.randf_range(0.0, 0.9))
            params[9] = _f1(rng.randf_range(1000.0, 4000.0))
            params[10] = _f1(rng.randf_range(1.0, 200.0))
            kind += "+antilag"
    var max_rpm: float = _f1(rng.randf_range(3000.0, 8000.0))
    var acc: PackedFloat32Array = PackedFloat32Array()
    var cur_acc: PackedFloat32Array = PackedFloat32Array()
    var rpm: PackedFloat32Array = PackedFloat32Array()
    var running: PackedByteArray = PackedByteArray()
    var throttle: float = 0.0
    var engine: float = rng.randf_range(0.5, 1.0) * max_rpm
    for step: int in STEPS:
        if step % 250 == 0:
            throttle = [0.0, 0.03, 0.4, 1.0, 1.0][rng.randi_range(0, 4)]
        engine = clampf(engine + rng.randf_range(-40.0, 60.0) * (1.0 if throttle > 0.1 else -1.0), 500.0, max_rpm * 1.1)
        cur_acc.append(_f1(throttle))
        acc.append(_f1(maxf(throttle, 0.1 if engine < 900.0 else 0.0)))
        rpm.append(_f1(engine))
        running.append(0 if step % 700 > 690 else 1)
    return {"version": version, "inertia": _f1(rng.randf_range(0.05, 1.5)), "count": count, "params": params, "kind": kind,
            "max_rpm": max_rpm, "torque": _f1(rng.randf_range(200.0, 2000.0)),
            "acc": acc, "cur_acc": cur_acc, "rpm": rpm, "running": running}


func _line(c: Dictionary) -> String:
    var parts: PackedStringArray = PackedStringArray(["turbo", str(c["version"]), _n(c["inertia"]), str(c["count"])])
    for p: float in c["params"] as PackedFloat32Array:
        parts.append(_n(p))
    parts.append_array([_n(c["max_rpm"]), _n(c["torque"]), _n(DT), str(STEPS)])
    for step: int in STEPS:
        parts.append_array([_n(c["acc"][step]), _n(c["cur_acc"][step]), _n(c["rpm"][step]), str(c["running"][step])])
    return " ".join(parts)


func _f1(x: float) -> float:
    return PackedFloat32Array([x])[0]


func _n(value: float) -> String:
    return String.num_scientific(value)
