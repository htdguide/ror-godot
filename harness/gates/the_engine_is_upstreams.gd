extends GateBase
## The engine, gearbox and clutch are upstream's `Engine` (gameplay/Engine.cpp): its constructor
## and `SetEngineOptions`, `UpdateEngine` (the turbo, the torque balance, the starter and stall,
## the clutch, the shift timing, the auto clutch, the automatic box's gear choice from its 50- and
## 200-frame averages with kickdown, and the over-rev guard), the gearbox modes and `toggleAutoMode`,
## `shift`, the automatic selector (`autoShiftUp`, `autoShiftDown`, `autoShiftSet`), the manual
## clutch, `startEngine` and `offStart`, and the torque curve through Ogre's `SimpleSpline`.
## Compared step by step with those functions compiled from the pinned submodule
## (`tools/build_parity.sh`), on random engines, gearboxes and drivers.
##
## Not reached by these cases (a mutation to either passes): the kickdown delay that holds a
## downshift back for 100 frames after a redline upshift, and the g-force hold on an averaged
## shift. Both guard narrow branches of the averaged gear choice that random driving does not find.
##
## Ours was a reduction of upstream's: the automatic box shifted on rpm alone, a shift did not ramp
## the throttle back, the clutch smoothing used `std::exp` where upstream uses `approx_exp`, and there
## was no manual gearbox or clutch.

const ORACLE: String = "build/parity/upstream_oracle"
const CASES: int = 60
const STEPS: int = 16000


static func meta() -> Dictionary:
    return {
        "name": "the_engine_is_upstreams",
        "proves": "the engine, gearbox and clutch step as upstream's Engine does in every gearbox mode, with its torque curve",
        "builds_on": [],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "rpm, throttle, clutch, clutch torque, gear, selector, mode and shift state of %d cases x %d substeps identical to upstream's" % [CASES, STEPS],
        "why": "the engine was a reduction of upstream's: no averaged gear choice, no throttle ramp after a shift, no manual gearbox or clutch.",
        "budget_s": 120.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var root: String = SourceScan.repo_root()
    var keys_report: String = _keys(root)
    if keys_report.begins_with("!"):
        return fail(keys_report.substr(1))
    if not FileAccess.file_exists(root.path_join(ORACLE)):
        return ok("parity skipped: the upstream oracle is not built. Run tools/build_parity.sh", 0)
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = 20261015
    var cases: Array = []
    var lines: PackedStringArray = PackedStringArray()
    for n: int in CASES:
        var config: PackedFloat32Array = PackedFloat32Array()
        var min_rpm: float = rng.randf_range(500, 1500)
        var max_rpm: float = min_rpm + rng.randf_range(1500, 5000)
        config.append_array([min_rpm, max_rpm, rng.randf_range(200, 3000), rng.randf_range(2, 6), rng.randf_range(2, 5), rng.randf_range(5, 15)])
        var n_gears: int = rng.randi_range(3, 12)
        config.append(n_gears)
        var gear: float = rng.randf_range(3, 8)
        for g: int in n_gears:
            config.append(gear)
            gear *= rng.randf_range(0.6, 0.85)
        var type: String = ["t", "c", "e"][rng.randi_range(0, 2)]
        config.append_array([rng.randf_range(0.3, 6), type.unicode_at(0), [-1.0, rng.randf_range(2000, 15000)][rng.randi_range(0, 1)],
                rng.randf_range(0.2, 1.0), rng.randf_range(0.1, 0.5), rng.randf_range(0.1, 0.4), rng.randf_range(100, 400),
                rng.randf_range(500, 900), [-1.0, 0.2][rng.randi_range(0, 1)], [-1.0, 0.05][rng.randi_range(0, 1)], [-1.0, rng.randf_range(100, 900)][rng.randi_range(0, 1)]])
        var curve: Array = [[0, 1000, 10000], [1.0, 1.0, 1.0]] if rng.randf() < 0.3 else [[0, 1000, 2000, 3000, 4000, 5000], [0.0, 0.8, 0.95, 1.0, 0.9, 0.7]]
        config.append((curve[0] as Array).size())
        for i: int in (curve[0] as Array).size():
            config.append_array([curve[0][i], curve[1][i]])
        # Two cases in three drive a vehicle: the clutch's torque spins the wheels, drag slows them.
        var coupled: bool = rng.randf() < 0.67
        config.append_array([rng.randf_range(0.2, 2.0) if coupled else 0.0, rng.randf_range(0.05, 1.0)])
        var parts: PackedStringArray = PackedStringArray(["engine", str(STEPS)])
        for i: int in 7:
            parts.append(_n(config[i]) if i != 6 else str(n_gears))
        for i: int in range(7, 7 + n_gears):
            parts.append(_n(config[i]))
        var o: int = 7 + n_gears
        parts.append(_n(config[o]))
        parts.append(type)
        for i: int in range(o + 2, o + 11):
            parts.append(_n(config[i]))
        parts.append(str(int(config[o + 11])))
        for i: int in range(o + 12, config.size()):
            parts.append(_n(config[i]))
        # (the last two are the vehicle's gain and drag)
        var steps: Array = []
        var acc: float = 0.0
        var wheel: float = 0.0
        var pedal: float = 0.0
        var dir: Vector3 = Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 0.2), rng.randf_range(-1, 1))
        for step: int in STEPS:
            var action: int = 8 if step == 0 else (rng.randi_range(1, 9) if rng.randf() < 0.0005 else 0)
            var value: int = [rng.randi_range(-1, 1), 0, 0, 0, rng.randi_range(0, 4), rng.randi_range(0, 1), rng.randi_range(0, 1), 0, 0][maxi(action - 1, 0)]
            if step % 800 == 0:
                # Floored now and then, the automatic box's kickdown and averages have work to do.
                acc = 1.0 if rng.randf() < 0.25 else clampf(acc + rng.randf_range(-0.5, 0.5), 0.0, 1.0)
                pedal = 0.0 if rng.randf() < 0.6 else rng.randf()
            wheel = clampf(wheel + rng.randf_range(-3.0, 3.5), -300.0, 3000.0)
            var vel: Vector3 = dir * wheel * 0.004 + Vector3(0, rng.randf_range(-0.1, 0.1), 0)
            # A frame every 8 substeps (250 a second): more of the gear choice, which runs once a frame.
            var v: PackedFloat32Array = PackedFloat32Array([action, value, acc, wheel, 1 if step % 8 == 0 else 0, pedal,
                    1 if rng.randf() < 0.01 else 0, rng.randf_range(0, 5) if rng.randf() < 0.02 else 0.0,
                    vel.x, vel.y, vel.z, dir.x, dir.y, dir.z, rng.randf_range(0.3, 0.6), rng.randf() if rng.randf() < 0.1 else 0.0,
                    rng.randf_range(0.2, 0.35) * (1.0 if rng.randf() < 0.5 else -1.0) if rng.randf() < 0.5 else rng.randf_range(-0.2, 0.2)])
            steps.append(v)
            for k: int in v.size():
                parts.append(str(int(v[k])) if k in [0, 1, 4, 6] else _n(v[k]))
        cases.append([config, steps])
        lines.append(" ".join(parts))
    var path: String = root.path_join("build/parity/engine_cases.txt")
    var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    file.store_string("\n".join(lines) + "\n")
    file.close()
    var output: Array = []
    var status: int = OS.execute("/bin/sh", ["-c", "'%s' < '%s'" % [root.path_join(ORACLE), path]], output, true)
    if status != 0:
        return fail("the upstream oracle exited %d: %s" % [status, "\n".join(output).left(400)])
    var results: PackedStringArray = ("\n".join(output)).strip_edges().split("\n")
    if results.size() != CASES * STEPS:
        return fail("the oracle printed %d steps, not %d" % [results.size(), CASES * STEPS])
    var shifted: int = 0
    var modes: Dictionary = {}
    for i: int in CASES:
        var ours: PackedStringArray = RorSolver.engine_probe(cases[i][0], cases[i][1])
        var last_gear: String = ""
        for step: int in STEPS:
            var theirs: String = results[i * STEPS + step].strip_edges()
            if ours[step].strip_edges() != theirs:
                return fail("case %d, step %d:\n upstream %s\n ours     %s" % [i, step, theirs, ours[step]])
            var f: PackedStringArray = theirs.split(" ")
            modes[f[6]] = true
            if last_gear != "" and f[4] != last_gear:
                shifted += 1
            last_gear = f[4]
    return ok("%s; %d cases x %d substeps identical to upstream's; %d gear changes, modes %s seen" % [keys_report, CASES, STEPS, shifted, modes.keys()], 0)


## Upstream's keys on the hero, through real key events: Q to semi-automatic, A a gear up (a timed
## shift), Z back down, D to neutral; Q to manual, where Left Shift held disengages the clutch; Q
## A grinds with the clutch engaged and goes in with it held; Q twice more to the stick modes, where no gear key held means neutral; Q back to automatic.
func _keys(root: String) -> String:
    var mod_dir: String = root.path_join("assets/mods/ChevyS1023")
    if not DirAccess.dir_exists_absolute(mod_dir):
        return "keys skipped: the hero is not present"
    var rig: Dictionary = RigBuilder.from_file(mod_dir, "S10offroad.truck", 0.0)
    var solver: RorSolver = rig["solver"]
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, rig["truck"], Vector3.ZERO, 0.0, 0.15)
    solver.start_engine()
    var keys: GearboxKeys = GearboxKeys.new()
    var map: Dictionary = DriveKeys.SOLO
    var frame: float = 1.0 / 60.0
    var tap: Callable = func(key: Key) -> void:
        _press(key, true)
        keys.read(solver, map, frame)
        _press(key, false)
        for i: int in 20:
            keys.read(solver, map, frame)
            solver.step(1.0 / 2000.0, 33)
    tap.call(KEY_Q)
    var semi: Dictionary = solver.gearbox("")
    tap.call(KEY_A)
    var up: int = solver.gearbox("")["gear"]
    tap.call(KEY_Z)
    var down: int = solver.gearbox("")["gear"]
    tap.call(KEY_D)
    var neutral: int = solver.gearbox("")["gear"]
    tap.call(KEY_Q)
    _press(KEY_SHIFT, true)
    keys.read(solver, map, frame)
    var pedal: float = solver.gearbox("")["clutch"]
    _press(KEY_SHIFT, false)
    keys.read(solver, map, frame)
    var released: float = solver.gearbox("")["clutch"]
    # Without the clutch a gear grinds and stays out; with it down, it goes in.
    tap.call(KEY_A)
    var grind: int = solver.gearbox("")["gear"]
    _press(KEY_SHIFT, true)
    tap.call(KEY_A)
    _press(KEY_SHIFT, false)
    var manual_gear: int = solver.gearbox("")["gear"]
    tap.call(KEY_Q)
    var stick_engaged: int = solver.gearbox("")["gear"]
    _press(KEY_SHIFT, true)
    tap.call(KEY_SHIFT)
    var stick: Dictionary = solver.gearbox("")
    tap.call(KEY_Q)
    tap.call(KEY_Q)
    var back: Dictionary = solver.gearbox("")
    if semi["mode_index"] != 1 or up != 2 or down != 1 or neutral != 0 or pedal != 0.0 or released != 1.0 or grind != 0 or manual_gear != 1 or stick_engaged != 1 or stick["mode_index"] != 3 or stick["gear"] != 0 or back["mode_index"] != 0:
        return "!keys: Q gave %s, A gear %d, Z %d, D %d; manual: Shift clutch %.2f then %.2f, A without it gear %d, with it %d; stick engaged gear %d, clutch down %s; back %s" % [
            semi["mode"], up, down, neutral, pedal, released, grind, manual_gear, stick_engaged, stick, back["mode"]]
    return "keys as upstream's: Q steps the modes, A/Z shift, D neutral, Left Shift the clutch (manual shifts need it), a stick with no gear held drops to neutral with the clutch down"


func _press(keycode: Key, down: bool) -> void:
    var event: InputEventKey = InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.pressed = down
    Input.parse_input_event(event)
    Input.flush_buffered_events()


func _n(value: float) -> String:
    return String.num_scientific(value)
