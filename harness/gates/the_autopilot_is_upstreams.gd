extends GateBase
## An airplane's autopilot is upstream's (`Autopilot`): wings level, a heading held by banking at
## most 45 degrees, an altitude or a vertical speed held through the elevator, an airspeed through
## every engine's throttle, the settings stepped as its dashboard steps them; made with the first
## aero engine and referenced, as the wings close, to the first run's last wing's tips and the
## fuselage drag's node, as upstream's spawner does. Compared step by step with upstream's methods
## compiled from the pinned submodule (`tools/build_parity.sh`).
##
## Ours had none. ILS approaches need a terrain's localizers, which are not read: as upstream with
## none in range, NAV disconnects itself. Its warnings are sounds, and there are none yet.

const ORACLE: String = "build/parity/upstream_oracle"
const CASES: int = 200
const STEPS: int = 300
const FRAME: float = 1.0 / 60.0
const MOD_DIR: String = "assets/corpus/181_supermarine-spitfire"


static func meta() -> Dictionary:
    return {
        "name": "the_autopilot_is_upstreams",
        "proves": "the autopilot's aileron, elevator and throttle are upstream's Autopilot's in every mode, wired to an airplane's surfaces, hydros and engines as upstream's",
        "builds_on": [],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "every output and setting of %d cases x %d steps identical to upstream's; on the Spitfire HDG banks the ailerons, IAS opens the throttle, NAV disconnects, a respawn resets" % [CASES, STEPS],
        "why": "airplanes had no autopilot.",
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var root: String = SourceScan.repo_root()
    var report: String = ""
    var mod_dir: String = root.path_join(MOD_DIR)
    if DirAccess.dir_exists_absolute(mod_dir):
        var spitfire: String = _spitfire(mod_dir)
        if spitfire.begins_with("!"):
            return fail(spitfire.substr(1))
        report = spitfire
    else:
        report = "the Spitfire is not present"
    if not FileAccess.file_exists(root.path_join(ORACLE)):
        return ok(report + "; parity skipped: the upstream oracle is not built. Run tools/build_parity.sh", 0)
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = 20261014
    var cases: Array = []
    var lines: PackedStringArray = PackedStringArray()
    for n: int in CASES:
        var half: float = rng.randf_range(2.0, 8.0)
        var start: PackedVector3Array = PackedVector3Array([Vector3(0, 0, half), Vector3(0, 0, -half), Vector3(4, 0, 0)])
        var parts: PackedStringArray = PackedStringArray(["autopilot", str(STEPS)])
        for p: Vector3 in start:
            parts.append_array([_n(p.x), _n(p.y), _n(p.z)])
        var steps: Array = []
        var height: float = rng.randf_range(0.0, 3000.0)
        var bank: float = 0.0
        var vel: Vector3 = Vector3(rng.randf_range(-80.0, 80.0), rng.randf_range(-10.0, 10.0), rng.randf_range(-80.0, 80.0))
        var throttle: float = rng.randf()
        for step: int in STEPS:
            var action: int = 0
            var value: int = 0
            if rng.randf() < 0.08:
                action = rng.randi_range(2, 11)
                value = [rng.randi_range(-200, 200), rng.randi_range(-3000, 3000), rng.randi_range(-4000, 4000), rng.randi_range(-120, 120)][maxi(action - 8, 0) % 4]
            height = clampf(height + rng.randf_range(-3.0, 3.0), -10.0, 9000.0)
            bank = clampf(bank + rng.randf_range(-0.05, 0.05), -1.4, 1.4)
            vel += Vector3(rng.randf_range(-3.0, 3.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-3.0, 3.0))
            throttle = clampf(throttle + rng.randf_range(-0.05, 0.05), 0.0, 1.0)
            var v: PackedFloat32Array = PackedFloat32Array([action, value])
            var ys: Array[float] = [height - sin(bank) * half, height + sin(bank) * half, height + rng.randf_range(-1.0, 1.0)]
            for k: int in 3:
                var nv: Vector3 = vel + Vector3(0, rng.randf_range(-2.0, 2.0), 0)
                v.append_array([ys[k], nv.x, nv.y, nv.z])
            v.append_array([throttle, FRAME])
            steps.append(v)
            parts.append_array([str(action), str(value)])
            for k: int in range(2, v.size()):
                parts.append(_n(v[k]))
        cases.append([start, steps])
        lines.append(" ".join(parts))
    var path: String = root.path_join("build/parity/autopilot_cases.txt")
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
    var moving: int = 0
    for i: int in CASES:
        var ours: PackedStringArray = RorSolver.autopilot_probe(cases[i][0], cases[i][1])
        for step: int in STEPS:
            if ours[step].strip_edges() != results[i * STEPS + step].strip_edges():
                return fail("case %d, step %d:\n upstream %s\n ours     %s" % [i, step, results[i * STEPS + step], ours[step]])
            moving += 1 if not results[i * STEPS + step].begins_with("0 0 ") else 0
    return ok(report + "; %d cases x %d steps identical to upstream's, %d steps with the autopilot acting" % [CASES, STEPS, moving], 0)


## The Spitfire standing still: HDG 090 moves its aileron hydros (still, its course reads 0, so it
## wants the full 45 degrees), IAS opens every engine's throttle by a fifteenth a second from upstream's 0.02 floor, NAV with no
## approach disconnects on the next frame's input, and a respawn resets it.
func _spitfire(mod_dir: String) -> String:
    var rig: Dictionary = RigBuilder.from_file(mod_dir, "spitfire_Vb.airplane", 0.0)
    var solver: RorSolver = rig["solver"]
    solver.set_gravity(Vector3.ZERO)
    if (solver.autopilot("state") as Dictionary).is_empty():
        return "!the Spitfire has aero engines but no autopilot"
    var keys: AirplaneKeys = AirplaneKeys.new()
    var truck: TruckParser = rig["truck"]
    var aileron_beam: int = -1
    for hydro: Dictionary in truck.hydros:
        if hydro["flags"] == 4:
            aileron_beam = hydro["beam"]
    if aileron_beam < 0:
        return "!the Spitfire has no aileron hydro"
    var rest: float = solver.get_beam_rest_length(aileron_beam)
    solver.autopilot("adj_hdg", 90)
    solver.autopilot("hdg")
    for frame: int in 30:
        keys.read(solver, FRAME)
        solver.step(1.0 / 2000.0, 33)
    var deflected: float = absf(solver.get_beam_rest_length(aileron_beam) - rest)
    if deflected < 1e-3:
        return "!HDG 090 at rest moved the aileron hydro %.5f m; upstream's banks the ailerons" % deflected
    solver.autopilot("ias")
    var before: float = solver.aero_state(0)["throttle"]
    keys.read(solver, FRAME)
    var after: float = solver.aero_state(0)["throttle"]
    # Upstream's hold opens it by dt/15 and keeps it between 0.02 and 1.
    var want: float = clampf(before + FRAME / 15.0, 0.02, 1.0)
    if absf(after - want) > 1e-5:
        return "!IAS at rest moved the throttle %.5f to %.5f; upstream's opens it to %.5f" % [before, after, want]
    keys.read(solver, FRAME)
    want = clampf(after + FRAME / 15.0, 0.02, 1.0)
    if absf(solver.aero_state(0)["throttle"] - want) > 1e-5:
        return "!IAS's second frame took the throttle to %.5f, not upstream's %.5f" % [solver.aero_state(0)["throttle"], want]
    solver.autopilot("nav")
    solver.step(1.0 / 2000.0, 1)
    keys.read(solver, FRAME)
    if solver.autopilot("state")["heading_mode"] != "":
        return "!NAV with no approach is still on as '%s'; upstream's disconnects" % solver.autopilot("state")["heading_mode"]
    solver.autopilot("alt")
    solver.repair()
    var state: Dictionary = solver.autopilot("state")
    if state["alt_mode"] != "" or state["heading"] != 0 or state["ias"] != 150:
        return "!a respawn left the autopilot at %s" % state
    return "Spitfire: HDG moves the aileron hydros %.3f m, IAS opens the throttle, NAV disconnects, a respawn resets" % deflected


func _n(value: float) -> String:
    return String.num_scientific(value)
