extends GateBase
## A command key with inertia ramps up and down by its curve instead of acting at once, from the
## row's own inertia fields or from `set_inertia_defaults`, with upstream's curves.
##
## Upstream's `CmdKeyInertia`: each substep a key's output moves towards its input by the curve's
## value times 0.001, the start curve while it rises in magnitude and the stop curve while it falls.
## 134 of the corpus's files set inertia defaults and their rams were reaching full speed at once.
##
## The oracle is arithmetic that does not depend on any curve's shape: upstream's `constant` curve is
## 1 everywhere, so a key on it climbs exactly 0.001 a substep and takes 1000 substeps to full. A ram
## of rate r held for one second (2000 substeps) then travels r x (1 + 2 + ... + 1000 + 1000 x 1000)
## / 1000 / 2000 = 0.75025 r instead of r, and let go it runs on another r x 499.5 / 2000 = 0.24975 r
## while the key falls. The same from `set_inertia_defaults`, and none after a negative one resets
## them. Upstream's curves are data; `InertiaModels.MODELS` has to equal upstream's file.

const SUBSTEP_HZ: float = 2000.0
const CHUNK: int = 33
const RATE: float = 0.25
const HELD_SHARE: float = 1500.5 / 2000.0
const RUN_ON_SHARE: float = 499.5 / 2000.0
const TOLERANCE: float = 0.001
const UPSTREAM_CFG: String = "vendor/rigs-of-rods/resources/skeleton/config/inertia_models.cfg"


static func meta() -> Dictionary:
    return {
        "name": "a_command_key_ramps_by_its_inertia_curve",
        "proves": "a command key with inertia ramps by upstream's curve from the row or from set_inertia_defaults, and the curves are upstream's",
        "builds_on": ["a_ram_moves_by_its_rate_and_stops_at_its_bounds"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "constant curve: held 1 s moves %.5f r, let go runs on %.5f r, within %.1f%%; no inertia moves r; models equal upstream's file" % [HELD_SHARE, RUN_ON_SHARE, TOLERANCE * 100.0],
        "why": "every ram reached full speed the moment its key went down; 134 corpus files ask for it to ramp.",
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var models: String = _check_models()
    if models != "":
        return fail(models)
    var report: PackedStringArray = PackedStringArray()
    var cases: Array[Dictionary] = [
        {"name": "row", "header": "", "inertia": "1, 1, constant, constant", "ramps": true},
        {"name": "defaults", "header": "set_inertia_defaults 1, 1, constant, constant", "inertia": "0, 0, 0, 0", "ramps": true},
        {"name": "reset", "header": "set_inertia_defaults 1, 1, constant, constant\nset_inertia_defaults -1", "inertia": "0, 0, 0, 0", "ramps": false},
        {"name": "none", "header": "", "inertia": "0, 0, 0, 0", "ramps": false},
    ]
    for case: Dictionary in cases:
        var solver: RefCounted = _ram(case["header"] as String, case["inertia"] as String)
        if solver == null:
            return fail("the %s case's rig did not build" % case["name"])
        var start: float = solver.get_beam_rest_length(0)
        _hold(solver, 1.0, true)
        var held: float = solver.get_beam_rest_length(0) - start
        _hold(solver, 1.0, false)
        var run_on: float = solver.get_beam_rest_length(0) - start - held
        var want_held: float = RATE * (HELD_SHARE if bool(case["ramps"]) else 1.0)
        var want_run_on: float = RATE * (RUN_ON_SHARE if bool(case["ramps"]) else 0.0)
        if absf(held - want_held) > want_held * TOLERANCE:
            return fail("%s: held 1 s the ram moved %.6f m, the curve says %.6f" % [case["name"], held, want_held], held)
        if absf(run_on - want_run_on) > maxf(want_run_on * TOLERANCE, 1e-6):
            return fail("%s: let go the ram ran on %.6f m, the curve says %.6f" % [case["name"], run_on, want_run_on], run_on)
        report.append("%s %.6f + %.6f" % [case["name"], held, run_on])
    return ok("r = %.2f m/s, held 1 s + let go 1 s: %s; models equal upstream's" % [RATE, ", ".join(report)], 0)


## `InertiaModels.MODELS` against upstream's file, when the submodule is checked out. "" if equal.
func _check_models() -> String:
    var path: String = SourceScan.repo_root().path_join(UPSTREAM_CFG)
    if not FileAccess.file_exists(path):
        return ""
    var upstream: Dictionary = InertiaModels.parse(FileAccess.get_file_as_string(path).replace("\r", ""))
    if upstream.size() != InertiaModels.MODELS.size():
        return "upstream has %d inertia models, the copy %d" % [upstream.size(), InertiaModels.MODELS.size()]
    for name: String in upstream:
        var ours: Array = InertiaModels.MODELS.get(name, []) as Array
        var theirs: Array = upstream[name] as Array
        if ours.size() != theirs.size():
            return "inertia model %s has %d numbers upstream and %d in the copy" % [name, theirs.size(), ours.size()]
        for i: int in ours.size():
            if not is_equal_approx(float(ours[i]), float(theirs[i])):
                return "inertia model %s differs from upstream at %d: %s against %s" % [name, i, ours[i], theirs[i]]
    return ""


## A two-node rig whose one beam is a 1 m ram lengthening at `RATE` on key 2, drawing no engine.
func _ram(header: String, inertia: String) -> RefCounted:
    var text: String = "\n".join([
        "inertiatest",
        "globals", "20, 0, tracks/semi",
        "nodes", "0, 0.0, 1.0, 0.0", "1, 1.0, 1.0, 0.0",
        header,
        "commands2",
        "0, 1, %.2f, %.2f, 0.5, 100.0, 1, 2, n, ram, %s, 0, 0" % [RATE, RATE, inertia],
        "end",
    ])
    var truck: TruckParser = TruckParser.new()
    if truck.parse_text(text) != "" or truck.commands.size() != 1:
        return null
    var built: Dictionary = RigBuilder.build(truck, 0.0)
    if (built["error"] as String) != "":
        return null
    var solver: RefCounted = built["solver"] as RefCounted
    solver.set_gravity(Vector3.ZERO)
    for node: int in 2:
        solver.set_node_immovable(node, true)
    return solver


## Key 2 held (or let go) for exactly `seconds` of substeps.
func _hold(solver: RefCounted, seconds: float, down: bool) -> void:
    solver.set_command_key(2, 1.0 if down else 0.0)
    var left: int = int(round(seconds * SUBSTEP_HZ))
    while left > 0:
        var take: int = mini(CHUNK, left)
        solver.step(1.0 / SUBSTEP_HZ, take)
        left -= take
