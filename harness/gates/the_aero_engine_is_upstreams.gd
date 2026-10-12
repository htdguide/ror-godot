extends GateBase
## An aero engine is upstream's: a `turboprops`/`turboprops2`/`pistonprops` row is a `Turboprop`,
## blade-element lift and drag on each of its two to four blades through its airfoil, its pitch
## governed towards 1010 rpm (or fixed, for a piston prop), a warm-up, a torque reaction on its
## couple node, failure when its hub leaves the blades, and the prop wash it blows over the wings;
## a `turbojets` row is a `Turbojet`, spooling up, warming up, an afterburner, a reverser, and
## failure when it is stretched. Compared step by step with those classes compiled from the pinned
## submodule (`tools/build_parity.sh`); the turboprop's constructor, which also builds its smoke,
## is its physics lines transcribed there.
##
## Ours had none: the corpus's 67 engines in 23 files were read and dropped, so no aircraft had thrust.
##
## Also: each row kind read and built (-1 is no node where a node may be missing; any other negative
## number is its absolute value, as upstream's sequential importer reads it); a wing 0-15 m behind a prop, within its
## radius in height, washed by the share of its span the disc covers (`WashCalculator`); and the
## throttle keys, PgUp stepping a twentieth every tenth of a second held, Ctrl+PgUp/PgDn full and
## none, Ctrl+Home the engines on.

const ORACLE: String = "build/parity/upstream_oracle"
const CASES: int = 90
const STEPS: int = 1000
## Upstream ignores a start in the engine's first 0.3 s (its `flipStart` debounce from a timer at 0):
## the engines are started after that.
const START_STEP: int = 620
const ROWS: String = """plane
globals
1000, 0, tracks/semi
nodes
0, 0, 0, 0
1, -1, 0, 0
2, 0, 1, 0
3, 0, -1, 0
4, 3, 0, 2
5, 3, 0, -2
6, 3, 0.1, 2
7, 3, 0.1, -2
8, 4, 0, 2
9, 4, 0, -2
10, 4, 0.1, 2
11, 4, 0.1, -2
beams
0, 1
turboprops2
0, 1, 2, 3, -1, -1, -1, 500, NACA0009.afl
pistonprops
0, 1, 2, -3, -1, -1, -1, 300, 20, NACA0009.afl
turboprops
0, 1, 2, 3, -1, -1, 400, NACA0009.afl
turbojets
0, 1, 2, 1, 50, 80, 0.8, 1.0, 1.5
wings
4, 5, 6, 7, 8, 9, 10, 11, 0, 0, 1, 0, 0, 1, 1, 1, n, -1, -1, -1, NACA0009.afl
end"""
const AIRFOILS: PackedStringArray = [
    "vendor/rigs-of-rods/resources/airfoils/NACA0009.afl", "vendor/rigs-of-rods/resources/airfoils/Clark-Y.afl",
    "vendor/rigs-of-rods/resources/airfoils/NACA64.1.412.afl", "-",
]


static func meta() -> Dictionary:
    return {
        "name": "the_aero_engine_is_upstreams",
        "proves": "turboprops, piston props and turbojets push, spin, govern, warm up, fail and blow as upstream's Turboprop and Turbojet do, force for force",
        "builds_on": [],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "every node force, rpm, prop wash, pitch, failure and ignition of %d cases x %d steps bit-identical to upstream's" % [CASES, STEPS],
        "why": "aero engines were read and dropped: no aircraft had thrust.",
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var truck: TruckParser = TruckParser.new()
    truck.parse_text(ROWS)
    var plane: RorSolver = RigBuilder.build(truck, 0.0)["solver"] as RorSolver
    plane.set_gravity(Vector3.ZERO)
    var engines: int = 0
    while not plane.aero_state(engines).is_empty():
        engines += 1
    if engines != 4:
        return fail("the four engine rows built %d engines" % engines)
    # Upstream spawns turbojets, then piston props, then turboprops: the jet is engine 0. Its radius
    # 0.5 at node 1 covers z -0.5..0.5 of the wing's -2..2 span, a quarter; each prop's disc, radius
    # 1 about the origin, covers z -1..1, half.
    var wash: Array = plane.wing_state(0)["wash"]
    var want_wash: Array = [Vector2(0, 0.25), Vector2(1, 0.5), Vector2(2, 0.5), Vector2(3, 0.5)]
    if wash != want_wash:
        return fail("the wing's prop wash is %s (engine, share); upstream's WashCalculator gives %s" % [wash, want_wash])
    var keys: AirplaneKeys = AirplaneKeys.new()
    _press(KEY_PAGEUP, true)
    for frame: int in 15:
        keys.read(plane, 1.0 / 60.0)
    _press(KEY_PAGEUP, false)
    if absf(float(plane.aero_state(0)["throttle"]) - 0.15) > 1e-6:
        return fail("PgUp held a quarter of a second set the throttle to %.3f, not three steps of 0.05" % plane.aero_state(0)["throttle"])
    _press(KEY_CTRL, true)
    keys.on_key(KEY_PAGEUP, plane)
    var full: float = plane.aero_state(3)["throttle"]
    keys.on_key(KEY_PAGEDOWN, plane)
    plane.step(1.0 / 2000.0, 700)
    keys.on_key(KEY_HOME, plane)
    _press(KEY_CTRL, false)
    if full != 1.0 or plane.aero_state(3)["throttle"] != 0.0 or not plane.aero_state(0)["ignition"]:
        return fail("Ctrl+PgUp gave %.2f, Ctrl+PgDn %.2f, Ctrl+Home ignition %s" % [full, plane.aero_state(3)["throttle"], plane.aero_state(0)["ignition"]])
    var report: String = "rows built, the wing's wash as upstream's, the throttle and start keys"

    var root: String = SourceScan.repo_root()
    if not FileAccess.file_exists(root.path_join(ORACLE)):
        return ok(report + "; parity skipped: the upstream oracle is not built. Run tools/build_parity.sh", 0)
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = 20261013
    var cases: Array[Dictionary] = []
    var lines: PackedStringArray = PackedStringArray()
    for n: int in CASES:
        var c: Dictionary = _prop(rng) if n % 3 != 2 else _jet(rng)
        cases.append(c)
        lines.append(_line(c, root))
    var path: String = root.path_join("build/parity/aero_cases.txt")
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
    var running: int = 0
    var failed: int = 0
    for i: int in CASES:
        var c: Dictionary = cases[i]
        var afl: String = "" if c["afl"] == "-" else FileAccess.get_file_as_string(root.path_join(c["afl"]))
        var ours: PackedStringArray = RorSolver.aero_probe(c["kind"], c["ids"], c["params"], c["positions"], c["masses"], afl, c["steps"])
        for step: int in STEPS:
            var theirs: String = results[i * STEPS + step]
            if ours[step] != theirs:
                return fail("case %d (%s), step %d:\n upstream %s\n ours     %s" % [i, c["kind"], step, theirs, ours[step]])
        var last: String = results[i * STEPS + STEPS - 1]
        running += 1 if last.ends_with(" 0 1") else 0
        failed += 1 if last.ends_with(" 1 1") or last.ends_with(" 1 0") else 0
    return ok(report + "; %d engines x %d steps bit-identical to upstream's, %d running at the end, %d failed" % [CASES, STEPS, running, failed], 0)


## A prop of two to four blades spinning about its axis while the aircraft moves.
func _prop(rng: RandomNumberGenerator) -> Dictionary:
    var blades: int = rng.randi_range(2, 4)
    var radius: float = rng.randf_range(0.8, 2.0)
    var basis: Basis = Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-PI, PI), rng.randf_range(-0.3, 0.3)))
    var origin: Vector3 = Vector3(rng.randf_range(-5, 5), rng.randf_range(0, 3000), rng.randf_range(-5, 5))
    var couple: bool = rng.randf() < 0.6
    # Nodes: ref 0, back 1, blades 2.., couple last.
    var count: int = 2 + blades + (1 if couple else 0)
    var ids: PackedInt32Array = PackedInt32Array([0, 1, 2, 3, 4 if blades > 2 else -1, 5 if blades > 3 else -1, count - 1 if couple else -1])
    var masses: PackedFloat32Array = PackedFloat32Array()
    for k: int in count:
        masses.append(_f1(rng.randf_range(2.0, 20.0)))
    var piston: bool = rng.randf() < 0.4
    var params: Array = [_f1(rng.randf_range(100.0, 1500.0)), piston, _f1(rng.randf_range(5.0, 40.0)) if piston else -10.0]
    var spin: float = rng.randf_range(0.0, 150.0)
    var angle: float = 0.0
    var forward: Vector3 = basis.z * rng.randf_range(-60.0, 80.0)
    var steps: Array = []
    var broken: bool = false
    var positions: PackedVector3Array = _prop_nodes(basis, origin, radius, blades, couple, angle, false)
    for step: int in STEPS:
        spin = clampf(spin + rng.randf_range(-3.0, 4.0), 0.0, 200.0)
        angle += spin * 0.0005
        broken = broken or rng.randf() < 0.0002
        var at: PackedVector3Array = _prop_nodes(basis, origin + forward * float(step) * 0.0005, radius, blades, couple, angle, broken)
        var vel: PackedVector3Array = PackedVector3Array()
        for k: int in count:
            var v: Vector3 = forward
            if k >= 2 and k < 2 + blades:
                v += (basis * Vector3(0, 0, 1)).cross(at[k] - at[0]) * spin
            vel.append(_f(v + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))))
        var throttle: float = [0.0, 0.3, 0.7, 1.0][(step / 90) % 4]
        steps.append([_f1(throttle), step == 900 and rng.randf() < 0.3, step == 0 or step == START_STEP, step % 10 == 0, at, vel])
    return {"kind": "prop", "ids": ids, "params": params, "positions": positions, "masses": masses,
            "afl": AIRFOILS[rng.randi_range(0, AIRFOILS.size() - 1)], "steps": steps}


func _prop_nodes(basis: Basis, origin: Vector3, radius: float, blades: int, couple: bool, angle: float, broken: bool) -> PackedVector3Array:
    var out: PackedVector3Array = PackedVector3Array([_f(origin), _f(origin + basis * Vector3(0, 0, -1.0))])
    for b: int in blades:
        var a: float = angle + TAU * float(b) / float(blades)
        var tip: Vector3 = Vector3(cos(a), sin(a), 0.0) * radius
        if broken and b == 0:
            tip += Vector3(0, 0, 2.0)
        out.append(_f(origin + basis * tip))
    if couple:
        out.append(_f(origin + basis * Vector3(0.6, 0.0, -0.5)))
    return out


## A jet along its axis, its afterburner reachable, sometimes stretched to failing.
func _jet(rng: RandomNumberGenerator) -> Dictionary:
    var basis: Basis = Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-PI, PI), 0.0))
    var length: float = rng.randf_range(1.0, 4.0)
    var origin: Vector3 = Vector3(rng.randf_range(-5, 5), rng.randf_range(0, 3000), rng.randf_range(-5, 5))
    var local: Array[Vector3] = [Vector3(0, 0, length), Vector3.ZERO, Vector3(0.5, 0, length * 0.5)]
    var positions: PackedVector3Array = PackedVector3Array()
    for p: Vector3 in local:
        positions.append(_f(origin + basis * p))
    var dry: float = _f1(rng.randf_range(10.0, 80.0))
    # A starting rpm (upstream's `setRPM`) puts the afterburner within reach once it is lit.
    var params: Array = [rng.randf() < 0.5, dry, _f1(dry * rng.randf_range(1.2, 2.0)) if rng.randf() < 0.6 else 0.0, _f1(rng.randf_range(0.5, 1.5)),
            _f1(rng.randf_range(0.0, 100.0))]
    var steps: Array = []
    var stretch: float = 0.0
    for step: int in STEPS:
        if rng.randf() < 0.0005:
            stretch = rng.randf_range(0.05, 0.3)
        var at: PackedVector3Array = PackedVector3Array()
        var vel: PackedVector3Array = PackedVector3Array()
        for k: int in 3:
            var p: Vector3 = local[k]
            if k == 0:
                p += Vector3(0, 0, stretch)
            at.append(_f(origin + basis * p))
            vel.append(_f(basis.z * rng.randf_range(-80.0, 0.0)))
        var throttle: float = [0.2, 0.6, 1.0, 0.93][(step / 90) % 4]
        steps.append([_f1(throttle), step == 900 and rng.randf() < 0.4, step == 0 or step == START_STEP, step % 10 == 0, at, vel])
    return {"kind": "jet", "ids": PackedInt32Array([0, 1, 2]), "params": params, "positions": positions,
            "masses": PackedFloat32Array([10, 10, 10]), "afl": "-", "steps": steps}


func _line(c: Dictionary, root: String) -> String:
    var parts: PackedStringArray = PackedStringArray(["aero", c["kind"], str((c["positions"] as PackedVector3Array).size())])
    var p: Array = c["params"]
    for id: int in c["ids"] as PackedInt32Array:
        parts.append(str(id))
    if c["kind"] == "prop":
        parts.append_array([_n(p[0]), "1" if p[1] else "0", _n(p[2]), c["afl"] if c["afl"] == "-" else root.path_join(c["afl"])])
    else:
        parts.append_array(["1" if p[0] else "0", _n(p[1]), _n(p[2]), _n(p[3]), _n(p[4])])
    parts.append(str(STEPS))
    var masses: PackedFloat32Array = c["masses"]
    var positions: PackedVector3Array = c["positions"]
    for k: int in positions.size():
        parts.append_array([_n(positions[k].x), _n(positions[k].y), _n(positions[k].z), _n(masses[k])])
    for step: Array in c["steps"]:
        parts.append_array([_n(step[0]), "1" if step[1] else "0", "1" if step[2] else "0", "1" if step[3] else "0"])
        var at: PackedVector3Array = step[4]
        var vel: PackedVector3Array = step[5]
        for k: int in at.size():
            parts.append_array([_n(at[k].x), _n(at[k].y), _n(at[k].z), _n(vel[k].x), _n(vel[k].y), _n(vel[k].z)])
    return " ".join(parts)


func _f(v: Vector3) -> Vector3:
    return Vector3(_f1(v.x), _f1(v.y), _f1(v.z))


func _f1(x: float) -> float:
    return PackedFloat32Array([x])[0]


func _n(value: float) -> String:
    return String.num_scientific(value)


func _press(keycode: Key, down: bool) -> void:
    var event: InputEventKey = InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.pressed = down
    Input.parse_input_event(event)
    Input.flush_buffered_events()
