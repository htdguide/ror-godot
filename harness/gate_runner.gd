class_name GateRunner
extends RefCounted
## Runs gates: one container each, many in one window, one result line per gate.
##
## Extracted from `Harness` when it went over the source cap, and it is its own responsibility
## rather than a slice taken to please the counter: the harness owns arguments, determinism,
## capture and the exit code, and this owns the question "what does it take to run a gate and
## know nothing leaked out of it".
##
## The container is the point. Before D0 this was one OS window per gate, so isolation was the
## operating system's job and nothing here had to think about it. In one window a gate inherits
## whatever the one before it left, so every gate gets a fresh `GateContainer` and the counters
## the harness exposes are reset around it. A gate that leaks fails itself rather than the gate
## that runs after it.

## Emitted as each gate finishes, before the next one opens its container.
##
## A suite run is minutes long and a summary printed at the end of it tells a person nothing
## while they wait. The console shows these as they arrive; the agent's channel deliberately
## does not, and still gets one line for the whole command — the two front ends want opposite
## things from the same run and a signal is how both get what they want from one runner.
signal gate_finished(row: Dictionary)

const GATE_DIR: String = "res://harness/gates"
## Exit codes, matching `Harness`'s own so a caller sees one set.
const OK: int = 0
const FAIL: int = 1
const USAGE: int = 2

## What the window shows: the container that is running. One window for the whole suite, which is
## the point of D0, and a session can watch a gate build its world in place.
var _screen: TextureRect = null


## Runs each named gate in its own container, in the order given, and exits non-zero if any of
## them failed. One window for all of them.
##
## The order is the caller's and is not sorted here, because `--gate` in a chosen order is how
## order-independence is checked: the same names in a different order must produce the same
## results, and a runner that sorted them would make that untestable.
func run(harness: Node, names: PackedStringArray) -> Dictionary:
    var out: Dictionary = {"failed": 0, "usage_error": false}
    if names.is_empty():
        printerr("HARNESS_ERROR --gate needs at least one gate name")
        out["usage_error"] = true
        return out
    _screen = _build_screen(harness)
    var failed: int = 0
    for name: String in names:
        var outcome: int = await _run_one_gate(harness, name.strip_edges())
        if outcome == USAGE:
            out["usage_error"] = true
            return out
        if outcome != OK:
            failed += 1
    if names.size() > 1:
        print("HARNESS_SUITE " + JSON.stringify({
            "gates": names.size(), "failed": failed, "windows": 1,
        }))
    out["failed"] = failed
    return out


## A full-window texture showing whichever container is running, so one window is enough to
## watch the whole suite. Purely a display: nothing measured is read back through it.
func _build_screen(harness: Node) -> TextureRect:
    var screen: TextureRect = TextureRect.new()
    screen.name = "ContainerScreen"
    screen.set_anchors_preset(Control.PRESET_FULL_RECT)
    screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    screen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    harness.add_child(screen)
    return screen


## Runs one gate in a fresh container and prints its result. Returns an exit code.
func _run_one_gate(harness: Node, name: String) -> int:
    var script_path: String = "%s/%s.gd" % [GATE_DIR, name]
    if not ResourceLoader.exists(script_path):
        _report_usage(name, "no gate '%s' at %s" % [name, script_path])
        return USAGE
    var gate_script: GDScript = load(script_path) as GDScript
    if gate_script == null or not gate_script.can_instantiate():
        _report_usage(name, "gate '%s' failed to compile; see the parse errors above" % name)
        return USAGE
    var meta_dict: Dictionary = gate_script.call("meta") as Dictionary
    var meta_error: String = GateBase.validate_meta(meta_dict)
    if meta_error != "":
        _report_usage(name, "gate '%s' metadata invalid: %s" % [name, meta_error])
        return USAGE
    var gate: GateBase = gate_script.new() as GateBase

    # Every gate starts from the same state: a fresh container, and the run counters reset. A
    # gate that read `frame_index` expecting it to start at zero was correct with one gate per
    # process and would otherwise be wrong from the second gate onward.
    var container: GateContainer = GateContainer.new()
    container.open(harness, name, Vector2i(HarnessCfg.WIDTH, HarnessCfg.HEIGHT))
    # The harness reads this to decide where a world is built and what a capture reads, so it is
    # handed over before the gate runs and cleared before the next one opens.
    harness.container = container
    harness.terrain = container.terrain
    # Seeded the same for every gate, so a gate's numbers do not depend on how many draws the
    # gates before it made. This was `extension_parity`'s order dependence.
    harness.rng = container.rng
    if _screen != null:
        _screen.texture = container.viewport.get_texture()
    harness.frame_index = 0
    harness.preset_name = ""
    harness.preset = {}
    harness.world = null
    harness.camera = null

    print("HARNESS_GATE_BEGIN " + JSON.stringify(meta_dict))
    var started_usec: int = Time.get_ticks_usec()
    var result: Dictionary = await gate.run(harness)
    var elapsed_s: float = float(Time.get_ticks_usec() - started_usec) / 1000000.0

    if _screen != null:
        _screen.texture = null
    var closed: Dictionary = await container.close()
    harness.container = null
    harness.world = null
    harness.camera = null

    var passed: bool = result.get("pass", false) as bool
    var over_budget: bool = elapsed_s > float(meta_dict["budget_s"])
    var leaked: String = closed["leaked"] as String
    var row: Dictionary = {
        "gate": name,
        "pass": passed and not over_budget and leaked == "",
        "detail": result.get("detail", "") as String,
        "measured": result.get("measured"),
        "threshold": meta_dict["threshold"],
        "oracle": meta_dict["oracle"],
        "elapsed_s": snappedf(elapsed_s, 0.01),
        "budget_s": meta_dict["budget_s"],
        "over_budget": over_budget,
    }
    # A leak is the container's finding about this gate, not the gate's own, so it is reported
    # separately and it fails the gate that caused it. Silently carrying it means the gate that
    # runs next is blamed.
    if leaked != "":
        row["leaked"] = leaked
        row["detail"] = "%s [container leak: %s]" % [row["detail"], leaked]
    print("HARNESS_GATE_RESULT " + JSON.stringify(row))
    gate_finished.emit(row)
    return OK if row["pass"] else FAIL


## A usage failure for one gate, printed in the same shape as a result so a suite run does not
## have two formats to parse.
func _report_usage(name: String, message: String) -> void:
    printerr("HARNESS_ERROR " + message)
    print("HARNESS_GATE_RESULT " + JSON.stringify({
        "gate": name, "pass": false, "detail": message, "measured": null,
    }))


