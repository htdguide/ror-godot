extends GateBase
## A `triggers` row is upstream's trigger: `ActorSpawner::ProcessTrigger` builds it and
## `Actor::CalcTriggers`, from the beam pass, has it press a command key, block other triggers
## (`B`, `A`) or keys (`b`, a -1 long action), swap two keys (`s`), work smoothly (`t`), lock or
## unlock a hook group (`H`, `h`) or drive the engine (`E`), as its beam leaves or re-enters its
## bounds, shock style or command style (`c`), disabled at the start with `x`. Compared step by
## step with those functions compiled from the pinned submodule (`tools/build_parity.sh`), with
## the line of `CalcCommands` that turns a key's trigger input into its value.
##
## Ours read no triggers: 85 corpus files declare 371 rows, mostly the hook triggers that let a
## hooklift or a trailer lock and let go by itself.
##
## Then in a world: a hook-locking trigger squeezed past its bound on a frame's first substep has
## its hook group locked before the next frame's step, as upstream's message queue does.

const ORACLE: String = "build/parity/upstream_oracle"
const CASES: int = 200
const STEPS: int = 40
const OPTIONS: PackedStringArray = ["", "i", "c", "ci", "x", "cx", "b", "cb", "B", "cB", "A", "cA", "s", "cs", "h", "H", "ch",
        "cH", "t", "ct", "E", "cE", "ctE", "tE", "cbt", "xB", "sb"]
const HOOK_RIG: String = """hooker
globals
300, 0, tracks/semi
nodes
0, 0.0, 0.0, 0.0
1, 1.0, 0.0, 0.0
2, 0.5, 1.0, 0.0, h
3, 0.0, 2.0, 0.0
4, 1.0, 2.0, 0.0
beams
0, 1
1, 2
0, 2
0, 3
hooks
2, hookgroup, -3
triggers
3, 4, 0.2, 0.2, -3, -3, Hi
end"""
const LOAD: String = """load
globals
30, 0, tracks/semi
nodes
0, 0.5, 1.3, 0.0
1, 0.5, 1.38, 0.0
2, 1.5, 1.3, 0.0
beams
0, 1
1, 2
0, 2
end"""


static func meta() -> Dictionary:
    return {
        "name": "the_trigger_is_upstreams",
        "proves": "triggers are built and act as upstream's ProcessTrigger and CalcTriggers do, on keys, blockers, switches, hook groups and the engine, and a hook trigger locks its group in a world",
        "builds_on": [],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "every step of %d cases identical to upstream's: trigger states, key values and blocks, hook requests, engine calls, brake; the hook group locked the frame after" % CASES,
        "why": "85 corpus files declare 371 triggers and none was read: no hooklift or trailer locked by itself.",
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var truck: TruckParser = TruckParser.new()
    truck.parse_text(HOOK_RIG)
    if truck.links.triggers.size() != 1 or truck.links.triggers[0]["options"] != "Hi":
        return fail("the triggers row read as %s" % [truck.links.triggers])
    var world: RorWorld = RorWorld.new()
    var hooker: RorSolver = _held(HOOK_RIG)
    var load: RorSolver = _held(LOAD)
    world.add_solver(hooker)
    world.add_solver(load)
    if hooker.trigger_count() != 1:
        return fail("the trigger row built %d triggers" % hooker.trigger_count())
    # Squeezed to half its length: past its 0.2 contraction bound.
    hooker.set_node_position(4, Vector3(0.5, 2.0, 0.0))
    world.step(1.0 / 2000.0, 2)
    if hooker.hook_state(0) != "unlocked":
        return fail("the hook locked in the frame its trigger fired; upstream's request waits for the next")
    world.step(1.0 / 2000.0, 1)
    if hooker.hook_state(0) == "unlocked":
        return fail("the hook trigger's request to lock group -3 did not lock the group's hook the next frame")
    var report: String = "a squeezed H trigger locked hook group -3 the next frame"

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
    var path: String = root.path_join("build/parity/trigger_cases.txt")
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
    var acted: Dictionary = {}
    for i: int in CASES:
        var c: Dictionary = cases[i]
        var ours: PackedStringArray = RorSolver.trigger_probe(c["positions"], c["rows"], c["steps"])
        for step: int in STEPS:
            var theirs: String = results[i * STEPS + step]
            if ours[step] != theirs:
                return fail("case %d (%s), step %d:\n upstream %s\n ours     %s" % [i, c["kinds"], step, theirs, ours[step]])
            for part: String in ["K ", "H lock", "H unlock", "E clutch", "E acc", "E shift"]:
                if theirs.contains(part) and not theirs.contains(part + "B") and not theirs.contains(part + "H") and not theirs.contains(part + "E") and not theirs.contains(part + "R"):
                    acted[part.strip_edges()] = true
    return ok(report + "; %d cases x %d steps identical to upstream's, acting on %s" % [CASES, STEPS, ", ".join(acted.keys())], 0)


## Triggers on their own pairs of nodes, so each beam's length is set freely, step by step.
func _case(rng: RandomNumberGenerator) -> Dictionary:
    var count: int = rng.randi_range(1, 6)
    var positions: PackedVector3Array = PackedVector3Array()
    var rows: Array = []
    var kinds: PackedStringArray = PackedStringArray()
    for t: int in count:
        positions.append(Vector3(0.0, float(t) * 3.0, 0.0))
        positions.append(Vector3(1.0, float(t) * 3.0, 0.0))
        var options: String = OPTIONS[rng.randi_range(0, OPTIONS.size() - 1)]
        var short: int = rng.randi_range(1, 8)
        var long: int = rng.randi_range(1, 8) if rng.randf() < 0.8 else -1
        if options.contains("B") or options.contains("A"):
            short = rng.randi_range(0, 3)
            long = rng.randi_range(0, 3)
        elif options.contains("h") or options.contains("H"):
            short = rng.randi_range(-5, 2)
            long = rng.randi_range(-5, 2)
        elif options.contains("E"):
            short = 0
            long = rng.randi_range(0, 5)
        var contraction: float = _f1(rng.randf_range(0.5, 0.95) if options.contains("c") else rng.randf_range(0.05, 0.5))
        var expansion: float = _f1(rng.randf_range(1.05, 1.5) if options.contains("c") else rng.randf_range(0.05, 0.5))
        var timer: float = 0.0 if rng.randf() < 0.5 else _f1(rng.randf_range(0.001, 0.01))
        rows.append([2 * t, 2 * t + 1, contraction, expansion, short, long, options, timer])
        kinds.append(options if options != "" else "-")
    var steps: Array = []
    var stretch: PackedFloat32Array = PackedFloat32Array()
    stretch.resize(count)
    stretch.fill(1.0)
    for step: int in STEPS:
        var at: PackedVector3Array = PackedVector3Array()
        for t: int in count:
            if rng.randf() < 0.3:
                stretch[t] = [0.3, 0.6, 0.9, 1.0, 1.1, 1.4, 1.8][rng.randi_range(0, 6)]
            elif rng.randf() < 0.3:
                stretch[t] = clampf(stretch[t] + rng.randf_range(-0.15, 0.15), 0.2, 2.0)
            at.append(positions[2 * t])
            at.append(_f(positions[2 * t] + Vector3(stretch[t], 0.0, 0.0)))
        steps.append([step % 3 == 0, at])
    return {"positions": positions, "rows": rows, "steps": steps, "kinds": ",".join(kinds)}


func _line(c: Dictionary) -> String:
    var positions: PackedVector3Array = c["positions"]
    var parts: PackedStringArray = PackedStringArray(["trigger", str(positions.size()), str((c["rows"] as Array).size()), str(STEPS)])
    for p: Vector3 in positions:
        parts.append_array([_n(p.x), _n(p.y), _n(p.z)])
    for row: Array in c["rows"]:
        parts.append_array([str(row[0]), str(row[1]), _n(row[2]), _n(row[3]), str(row[4]), str(row[5]),
                row[6] if row[6] != "" else "-", _n(row[7])])
    for step: Array in c["steps"]:
        parts.append("1" if step[0] else "0")
        for p: Vector3 in step[1] as PackedVector3Array:
            parts.append_array([_n(p.x), _n(p.y), _n(p.z)])
    return " ".join(parts)


func _held(text: String) -> RorSolver:
    var truck: TruckParser = TruckParser.new()
    truck.parse_text(text)
    var solver: RorSolver = RigBuilder.build(truck, 0.0)["solver"] as RorSolver
    solver.set_gravity(Vector3.ZERO)
    solver.set_ground(-100.0, false)
    for node: int in solver.node_count():
        solver.set_node_immovable(node, true)
    return solver


func _f(v: Vector3) -> Vector3:
    return Vector3(_f1(v.x), _f1(v.y), _f1(v.z))


func _f1(x: float) -> float:
    return PackedFloat32Array([x])[0]


func _n(value: float) -> String:
    return String.num_scientific(value)
