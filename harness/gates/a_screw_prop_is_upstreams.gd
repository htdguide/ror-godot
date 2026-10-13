extends GateBase
## A `screwprops` row is upstream's screw prop: `ParseScrewprops` reads its nodes and power,
## `Screwprop::updateForces` pushes the reference node along the line to its back node, turned
## about the line to its up node by the rudder at up to 45 degrees, while that node is under water,
## and the boat keys (`UpdateBoatInputEvents`) step the throttle by a twentieth every tenth of a
## second, move the rudder by the time held, centre it and toggle the reverser. Compared step by
## step with those methods compiled from the pinned submodule (`tools/build_parity.sh`), then the
## Weasel driven on water and on a dry map.
##
## Ours read the rows as nothing: no boat could move.

const ORACLE: String = "build/parity/upstream_oracle"
const CASES: int = 200
const STEPS: int = 80
const FRAME: float = 1.0 / 60.0
const SUBSTEP: float = 1.0 / 2000.0
const MOD_DIR: String = "assets/corpus/189_weasel-class-boat"
const BOAT: String = "780dUIDweasel.boat"
const WATER: float = 10.0
const BOATS: Array[String] = ["189_weasel-class-boat/780dUIDweasel.boat", "189_weasel-class-boat/780dUIDweaselciv.boat",
        "191_m-v-nordia-express/korppi-201011141613-nordiaexpress.boat", "193_gypsea-12-jon-boat-now-with-trailer/Gypsea.boat"]


static func meta() -> Dictionary:
    return {
        "name": "a_screw_prop_is_upstreams",
        "proves": "screwprops rows push a boat as upstream's Screwprop does, on upstream's boat keys, only under water",
        "builds_on": ["a_boat_floats_as_upstreams"],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "every force, throttle and rudder of %d cases x %d steps identical to upstream's; the keys' steps exact; every corpus screw prop builds; the Weasel moves on water and not on land" % [CASES, STEPS],
        "why": "screw props were read as nothing: no boat could move.",
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var root: String = SourceScan.repo_root()
    var report: String = ""
    var props: int = 0
    for file: String in BOATS:
        var path: String = root.path_join("assets/corpus").path_join(file)
        if not FileAccess.file_exists(path):
            continue
        var truck: TruckParser = TruckParser.new()
        truck.parse_file(path)
        var solver: RorSolver = RigBuilder.build(truck, 0.0)["solver"] as RorSolver
        if truck.links.screwprops.is_empty() or (solver.boat_command("") ["throttle"] as Array).size() != truck.links.screwprops.size():
            return fail("%s: %d screwprops rows, %d built" % [file, truck.links.screwprops.size(), (solver.boat_command("")["throttle"] as Array).size()])
        props += truck.links.screwprops.size()
    var mod_dir: String = root.path_join(MOD_DIR)
    if DirAccess.dir_exists_absolute(mod_dir):
        var keys: String = _keys(mod_dir)
        if keys.begins_with("!"):
            return fail(keys.substr(1))
        var wet: float = _drive(mod_dir, true)
        var dry: float = _drive(mod_dir, false)
        if wet < 5.0 or dry > 1.0:
            return fail("full throttle for 10 s moved the Weasel %.2f m on water and %.2f m on land; upstream's pushes only under water" % [wet, dry], wet)
        report = "%d corpus screw props build; %s; full throttle moved the Weasel %.1f m on water, %.2f m on land" % [props, keys, wet, dry]
    if not FileAccess.file_exists(root.path_join(ORACLE)):
        return ok(report + "; parity skipped: the upstream oracle is not built. Run tools/build_parity.sh", 0)
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = 20261014
    var cases: Array = []
    var lines: PackedStringArray = PackedStringArray()
    for n: int in CASES:
        var power: float = rng.randf_range(100.0, 20000.0)
        var parts: PackedStringArray = PackedStringArray(["screw", str(STEPS), _n(power)])
        var steps: Array = []
        var ref: Vector3 = Vector3(rng.randf_range(-5, 5), rng.randf_range(-2, 2), rng.randf_range(-5, 5))
        for step: int in STEPS:
            var action: int = rng.randi_range(1, 4) if rng.randf() < 0.3 else 0
            var value: float = rng.randf_range(-0.6, 0.6)
            ref += Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2))
            var back: Vector3 = ref + Vector3(rng.randf_range(-2, 2), rng.randf_range(-0.5, 0.5), rng.randf_range(-2, 2))
            var up: Vector3 = ref + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.3, 2.0), rng.randf_range(-0.3, 0.3))
            var v: PackedFloat32Array = PackedFloat32Array([action, value, rng.randf_range(-1.0, 1.0)])
            for p: Vector3 in [ref, back, up]:
                v.append_array([p.x, p.y, p.z])
            steps.append(v)
            parts.append(str(action))
            for k: int in range(1, v.size()):
                parts.append(_n(v[k]))
        cases.append([power, steps])
        lines.append(" ".join(parts))
    var path: String = root.path_join("build/parity/screw_cases.txt")
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
    var pushing: int = 0
    for i: int in CASES:
        var ours: PackedStringArray = RorSolver.screwprop_probe(PackedInt32Array([0, 1, 2]), cases[i][0], cases[i][1])
        for step: int in STEPS:
            var theirs: String = results[i * STEPS + step].strip_edges()
            if ours[step].strip_edges() != theirs:
                return fail("case %d, step %d:\n upstream %s\n ours     %s" % [i, step, theirs, ours[step]])
            pushing += 0 if theirs.begins_with("0 0 0 ") else 1
    return ok(report + "; %d cases x %d steps identical to upstream's, %d pushing" % [CASES, STEPS, pushing], 0)


## The boat keys on the Weasel: Up held a quarter second steps the throttle three times (at 0, 0.1
## and 0.2 s), Left held half a second puts the rudder at half and it stays when let go, PgDn
## centres it, PgUp reverses with the throttle cut.
func _keys(mod_dir: String) -> String:
    var solver: RorSolver = RigBuilder.from_file(mod_dir, BOAT, 0.0)["solver"]
    var keys: BoatKeys = BoatKeys.new()
    keys.held[KEY_UP] = true
    for frame: int in 15:
        keys.read(solver, FRAME)
    keys.held.erase(KEY_UP)
    var throttle: float = solver.boat_command("")["throttle"][0]
    keys.held[KEY_LEFT] = true
    for frame: int in 30:
        keys.read(solver, FRAME)
    keys.held.erase(KEY_LEFT)
    keys.read(solver, FRAME)
    var rudder: float = solver.boat_command("")["rudder"][0]
    keys.held[KEY_PAGEDOWN] = true
    keys.read(solver, FRAME)
    keys.held.erase(KEY_PAGEDOWN)
    var centred: float = solver.boat_command("")["rudder"][0]
    keys.held[KEY_PAGEUP] = true
    keys.read(solver, FRAME)
    keys.held.erase(KEY_PAGEUP)
    var reversed: float = solver.boat_command("")["throttle"][0]
    if absf(throttle - 0.15) > 1e-5 or absf(rudder - 0.5) > 1e-3 or centred != 0.0 or not (reversed == 0.0 and is_equal_approx(1.0 / reversed if reversed != 0.0 else -INF, -INF)):
        return "!Up for 0.25 s gave throttle %.4f (upstream's 0.15), Left for 0.5 s rudder %.4f (0.5), PgDn %.4f (0), PgUp %.4f (-0)" % [throttle, rudder, centred, reversed]
    return "Up 0.25 s throttle 0.15, Left 0.5 s rudder 0.50 and held, PgDn centres, PgUp reverses"


## How far the Weasel's middle moves level in 10 s at full throttle, set down on water at `WATER`
## (the bed 20 m below) or on dry ground at that height.
func _drive(mod_dir: String, water: bool) -> float:
    var rig: Dictionary = RigBuilder.from_file(mod_dir, BOAT, 0.0)
    var solver: RorSolver = rig["solver"]
    var truck: TruckParser = rig["truck"]
    solver.set_ground(WATER - 20.0 if water else WATER, true)
    solver.set_water(water, WATER)
    RigBuilder.place(solver, truck, Vector3(0, WATER + 0.5, 0), 0.0, 0.0)
    solver.step(SUBSTEP, 4000)
    var start: Vector3 = _middle(solver)
    solver.boat_command("throttle", 1.0)
    solver.step(SUBSTEP, 20000)
    var moved: Vector3 = _middle(solver) - start
    return Vector2(moved.x, moved.z).length()


func _middle(solver: RorSolver) -> Vector3:
    var positions: PackedVector3Array = solver.get_positions()
    var box: AABB = AABB(positions[0], Vector3.ZERO)
    for p: Vector3 in positions:
        box = box.expand(p)
    return box.get_center()


func _n(value: float) -> String:
    return String.num_scientific(value)
