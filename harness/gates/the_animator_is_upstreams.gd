extends GateBase
## An `animators` row is upstream's animator: `ParseAnimator` reads its options, `ProcessAnimator`
## makes them a hydro's flags and parameter with its beam's limits, and `CalcHydros` moves the beam
## by what `CalcAnimators` reads of the vehicle — engine torque, the rev counter, boost, the pedals,
## the clutch, the parking brake, the gear lever four ways, the speedometer, the differential, the
## air-speed, climb and altitude gauges, roll and pitch. Compared step by step with those functions
## compiled from the pinned submodule (`tools/build_parity.sh`), with an airplane's flaps, air
## brakes, wing 4's angle of attack and aero engines, and a boat's screw props.
##
## Ours read no animators: 30 corpus files declare 257, the moving gauges, levers and pistons of a
## cab and an engine bay. Then an airplane's read nothing of it: flaps that never lowered, gauges
## that never moved.
##
## Animators here run without inertia; the inertia they take is the hydros' own, held by
## `a_hydro_follows_…`.

const ORACLE: String = "build/parity/upstream_oracle"
const CASES: int = 200
const STEPS: int = 60
## Upstream's flag bits for the options a ground vehicle's animator can read.
const FLAGS: Array[int] = [1 << 0, 1 << 1, 1 << 3, 1 << 4, 1 << 5, 1 << 6, 1 << 7, 1 << 10, 1 << 11, 1 << 12,
        1 << 13, 1 << 14, 1 << 15, 1 << 16, 1 << 21, 1 << 23, 1 << 28, 1 << 29]
## And an airplane's: angle of attack, flaps, air brakes, then the aero engines' throttle, rpm,
## torque, pitch and status, which read the engine the parameter names.
const AIRPLANE: Array[int] = [1 << 3, 1 << 4, 1 << 5]
const AERO_ENGINE: Array[int] = [1 << 8, 1 << 9, 1 << 18, 1 << 19, 1 << 20]
## And a boat's: its screw props' rudder and throttle.
const BOAT: Array[int] = [1 << 28, 1 << 29]
const SHIFTER: int = 1 << 17
const ALTIMETER: int = 1 << 2


static func meta() -> Dictionary:
    return {
        "name": "the_animator_is_upstreams",
        "proves": "animator rows are read and move their beams as upstream's ParseAnimator, ProcessAnimator, CalcHydros and CalcAnimators do, every input a ground vehicle or an airplane has",
        "builds_on": [],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "every beam length and the shared memory of %d cases x %d steps identical to upstream's; options read to upstream's flags, parameter and limits" % [CASES, STEPS],
        "why": "30 corpus files declare 257 animators and none was read: no gauge, lever or piston moved.",
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var ids: Dictionary = {"3": 3, "4": 4}
    var parsed: Dictionary = AnimatorRows.read("3, 4, 0.5, tacho | inv | shortlimit:0.1 | longlimit: 0.2", ids)
    if parsed["flags"] != 1 << 13 or parsed["short_limit"] != 0.1 or parsed["long_limit"] != 0.2 or not parsed["invisible"]:
        return fail("'tacho|inv|shortlimit:0.1|longlimit: 0.2' read as %s" % [parsed])
    parsed = AnimatorRows.read("3, 4, 1, shifterlin|altimeter10k", ids)
    if parsed["flags"] != SHIFTER | ALTIMETER or parsed["param"] != 2.0:
        return fail("'shifterlin|altimeter10k' read as flags %d, param %.1f; upstream's spawner leaves 10k's 2" % [parsed["flags"], parsed["param"]])
    if not is_nan(AnimatorRows.read("3, 4, 1, sequential", ids)["short_limit"]):
        return fail("an animator stating no limit was given one")
    var report: String = "options read as upstream"

    var root: String = SourceScan.repo_root()
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
    var path: String = root.path_join("build/parity/anim_cases.txt")
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
    var moved: int = 0
    for i: int in CASES:
        var c: Dictionary = cases[i]
        var ours: PackedStringArray = RorSolver.animator_probe(c["rows"], c["steps"])
        for step: int in STEPS:
            var theirs: String = results[i * STEPS + step]
            if ours[step] != theirs:
                return fail("case %d (flags %s), step %d:\n upstream %s\n ours     %s" % [i, c["kinds"], step, theirs, ours[step]])
        moved += 1 if results[i * STEPS + STEPS - 1] != results[i * STEPS] else 0
    return ok(report + "; %d cases x %d steps identical to upstream's, %d of them moving" % [CASES, STEPS, moved], 0)


func _case(rng: RandomNumberGenerator) -> Dictionary:
    var rows: Array = []
    var kinds: PackedStringArray = PackedStringArray()
    for a: int in rng.randi_range(1, 4):
        var flags: int = 0
        var param: float = 0.0
        for k: int in rng.randi_range(1, 3):
            var pick: int = rng.randi_range(0, FLAGS.size() + 4)
            if pick == FLAGS.size() + 2:
                flags |= AIRPLANE[rng.randi_range(0, AIRPLANE.size() - 1)]
            elif pick == FLAGS.size() + 4:
                flags |= BOAT[rng.randi_range(0, 1)]
            elif pick == FLAGS.size() + 3:
                flags |= AERO_ENGINE[rng.randi_range(0, AERO_ENGINE.size() - 1)]
                param = float(rng.randi_range(0, 3))
            elif pick == FLAGS.size():
                flags |= SHIFTER
                param = float(rng.randi_range(1, 4))
            elif pick == FLAGS.size() + 1:
                flags |= ALTIMETER
                param = float(rng.randi_range(1, 3))
            else:
                flags |= FLAGS[pick]
        var short: float = 0.99999 if rng.randf() < 0.5 else _f1(rng.randf_range(0.0, 0.5))
        var long: float = 1000000.0 if rng.randf() < 0.5 else _f1(rng.randf_range(0.0, 0.5))
        rows.append([flags, param, _f1(rng.randf_range(-2.0, 2.0)), _f1(rng.randf_range(0.3, 2.0)), short, long])
        kinds.append(str(flags))
    var steps: Array = []
    # The airplane: a wing count either side of upstream's wing 4, up to three engines, props or not.
    var num_wings: int = [0, 4, 5, 8][rng.randi_range(0, 3)]
    var engines: int = rng.randi_range(0, 3)
    var screws: int = rng.randi_range(0, 3)
    var xprop: Array[float] = [1.0, 0.0, 1.0]
    var max_torque: Array[float] = [_f1(rng.randf_range(500.0, 5000.0)), 0.0, _f1(rng.randf_range(500.0, 5000.0))]
    var flap: int = 0
    var airbrake: int = 0
    var gear: int = 1
    var crank: float = 1.0
    var pitch: float = 0.0
    var roll: float = 0.0
    var yaw: float = rng.randf_range(-PI, PI)
    for step: int in STEPS:
        if rng.randf() < 0.15:
            gear = rng.randi_range(-1, 6)
        crank = clampf(crank + rng.randf_range(-1.0, 1.0), 0.0, 5.0)
        pitch = clampf(pitch + rng.randf_range(-0.3, 0.3), -1.5, 1.5)
        roll = wrapf(roll + rng.randf_range(-0.5, 0.5), -PI, PI)
        var basis: Basis = Basis.from_euler(Vector3(pitch, yaw, roll))
        var pos: Vector3 = Vector3(rng.randf_range(-5.0, 5.0), rng.randf_range(0.0, 3.0), rng.randf_range(-5.0, 5.0))
        var dir: Vector3 = pos + basis.z * rng.randf_range(0.5, 2.0)
        var roll_node: Vector3 = pos - basis.x * rng.randf_range(0.5, 2.0)
        var values: Array = [
            0.0 if rng.randf() < 0.1 else 1.0, crank, float(gear), float(rng.randi_range(4, 8)),
            1.0 if rng.randf() < 0.2 else 0.0, rng.randf_range(-5.0, 40.0), [140.0, 200.0][rng.randi_range(0, 1)],
            rng.randf_range(500.0, 4000.0), rng.randf_range(3000.0, 5000.0), rng.randf_range(0.0, 30.0),
            rng.randf_range(0.0, 1.0), rng.randf_range(0.0, 1.0), rng.randf_range(0.0, 1.0), float(rng.randi_range(-1, 3)),
            rng.randf_range(-30.0, 30.0), rng.randf_range(-8.0, 8.0), rng.randf_range(-30.0, 30.0), rng.randf_range(-50.0, 4000.0),
            pos.x, pos.y, pos.z, dir.x, dir.y, dir.z, roll_node.x, roll_node.y, roll_node.z,
        ]
        flap = clampi(flap + rng.randi_range(-1, 1), 0, 5)
        airbrake = clampi(airbrake + rng.randi_range(-1, 1), 0, 5)
        values.append_array([float(flap), float(airbrake), float(num_wings), rng.randf_range(-30.0, 30.0), float(engines)])
        for e: int in engines:
            values.append_array([rng.randf_range(0.0, 130.0), rng.randf_range(0.0, 1.0), xprop[e],
                    rng.randf_range(0.0, 6000.0), max_torque[e], rng.randf_range(-10.0, 90.0),
                    1.0 if rng.randf() < 0.8 else 0.0, 1.0 if rng.randf() < 0.1 else 0.0])
        values.append(float(screws))
        for e: int in screws:
            values.append_array([rng.randf_range(-45.0, 45.0), rng.randf_range(-1.0, 1.0)])
        var packed: PackedFloat32Array = PackedFloat32Array(values)
        steps.append(packed)
    return {"rows": rows, "steps": steps, "kinds": ",".join(kinds)}


func _line(c: Dictionary) -> String:
    var parts: PackedStringArray = PackedStringArray(["anim", str((c["rows"] as Array).size()), str(STEPS)])
    for row: Array in c["rows"]:
        parts.append_array([str(row[0]), _n(row[1]), _n(row[2]), _n(row[3]), _n(row[4]), _n(row[5])])
    for step: PackedFloat32Array in c["steps"]:
        for k: int in step.size():
            var screws_at: int = 32 + 8 * int(step[31])
            var whole: bool = k in [0, 2, 3, 4, 13, 27, 28, 29, 31, screws_at] or (k >= 32 and k < screws_at and (k - 32) % 8 in [2, 6, 7])
            parts.append(str(int(step[k])) if whole else _n(step[k]))
    return " ".join(parts)


func _f1(x: float) -> float:
    return PackedFloat32Array([x])[0]


func _n(value: float) -> String:
    return String.num_scientific(value)
