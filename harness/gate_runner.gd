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
## Where the caption sits and how hard it is outlined, so it stays legible over a bright sky and
## over a black darkroom alike.
const CAPTION_MARGIN_PX: int = 16
const CAPTION_PAD_PX: float = 14.0
const CAPTION_RADIUS_PX: int = 8
## Big enough to read from across a desk, which is where somebody watching a suite run is sitting.
const CAPTION_FONT_PX: int = 26

var _screen: TextureRect = null
var _caption: Label = null
var _index: int = 0
var _total: int = 0
## The last result row this runner produced, for a caller that schedules gate by gate and wants
## the row rather than only the exit code.
var last_row: Dictionary = {}


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
    harness.gate_depth += 1
    # Only the outermost run puts anything on screen, and it takes it down again.
    #
    # A gate may run gates, and each nested run used to build its own full-window `TextureRect`
    # and leave it in the tree: three nested runs in `console_fronts_agree`, three nodes, under
    # the container leak check's slack of eight and so invisible. Adding a caption made it nine
    # and the check caught all of it at once, which is the check working.
    var showing: bool = harness.gate_depth == 1
    if showing:
        _screen = _build_screen(harness)
        _caption = _build_caption(harness)
    _total = names.size()
    _index = 0
    var failed: int = 0
    for name: String in names:
        var outcome: int = await _run_one_gate(harness, name.strip_edges())
        if outcome == USAGE:
            out["usage_error"] = true
            _close_display(showing)
            harness.gate_depth -= 1
            return out
        if outcome != OK:
            failed += 1
    _close_display(showing)
    harness.gate_depth -= 1
    if names.size() > 1:
        print("HARNESS_SUITE " + JSON.stringify({
            "gates": names.size(), "failed": failed, "windows": 1,
        }))
    out["failed"] = failed
    return out


## Takes the screen and the caption back out of the tree.
func _close_display(showing: bool) -> void:
    if not showing:
        return
    if _caption != null and _caption.get_parent() != null:
        _caption.get_parent().queue_free()
    _caption = null
    if _screen != null:
        _screen.queue_free()
    _screen = null


## What the gate is, written over the picture of it.
##
## Watching the suite without this is watching ninety unlabelled scenes go past, several of which
## look alarming on purpose — one points the camera into the sun, another lays a grey plane over
## the ground and relights it at night. A person cannot tell those from a fault without being told
## what each one is for, so each gate says its name, what it claims to prove, the threshold it is
## held to, and then how it did.
##
## Drawn over the container rather than inside it, so nothing measured ever sees these pixels: a
## capture reads the container viewport and this is a sibling of it.
func _build_caption(harness: Node) -> Label:
    # On its own panel, not floating over the picture.
    #
    # An outlined label was the first attempt and it was not readable: a gate can be a white sky
    # or a black darkroom from one scene to the next, so no text colour works against all of them,
    # and the pass green over a bright frame was the worst of it. A solid dark panel makes the
    # caption independent of whatever the gate happens to be rendering.
    var panel: PanelContainer = PanelContainer.new()
    panel.name = "ContainerCaption"
    panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
    panel.offset_left = CAPTION_MARGIN_PX
    panel.offset_right = -CAPTION_MARGIN_PX
    panel.offset_top = CAPTION_MARGIN_PX
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var background: StyleBoxFlat = StyleBoxFlat.new()
    background.bg_color = Color(0.04, 0.05, 0.07, 0.88)
    background.corner_radius_top_left = CAPTION_RADIUS_PX
    background.corner_radius_top_right = CAPTION_RADIUS_PX
    background.corner_radius_bottom_left = CAPTION_RADIUS_PX
    background.corner_radius_bottom_right = CAPTION_RADIUS_PX
    for side: int in 4:
        background.set_content_margin(side as Side, CAPTION_PAD_PX)
    panel.add_theme_stylebox_override("panel", background)

    var caption: Label = Label.new()
    caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    caption.add_theme_font_size_override("font_size", CAPTION_FONT_PX)
    panel.add_child(caption)
    harness.add_child(panel)
    return caption


## What the caption says while a gate runs, and what it says afterwards.
func _say(name: String, meta_dict: Dictionary, verdict: String, detail: String) -> void:
    if _caption == null:
        return
    var lines: PackedStringArray = PackedStringArray([
        "[%d/%d]  %s  —  %s" % [_index, _total, name, verdict],
        "proves: %s" % (meta_dict.get("proves", "") as String),
        "threshold: %s" % (meta_dict.get("threshold", "") as String),
        "oracle: %s   milestone: %s   budget: %.0fs" % [
            meta_dict.get("oracle", "?"), meta_dict.get("milestone", "?"),
            float(meta_dict.get("budget_s", 0.0)),
        ],
    ])
    if detail != "":
        lines.append(detail)
    _caption.text = "\n".join(lines)
    _caption.add_theme_color_override("font_color", _verdict_colour(verdict))


## Green for a pass, red for a failure, white while it is still running.
static func _verdict_colour(verdict: String) -> Color:
    if verdict.begins_with("PASS"):
        return Color(0.55, 1.0, 0.6)
    if verdict.begins_with("FAIL"):
        return Color(1.0, 0.5, 0.45)
    return Color(1.0, 1.0, 1.0)


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
        _report_usage(harness, name, "no gate '%s' at %s" % [name, script_path])
        return USAGE
    var gate_script: GDScript = load(script_path) as GDScript
    if gate_script == null or not gate_script.can_instantiate():
        _report_usage(harness, name, "gate '%s' failed to compile; see the parse errors above" % name)
        return USAGE
    var meta_dict: Dictionary = gate_script.call("meta") as Dictionary
    var meta_error: String = GateBase.validate_meta(meta_dict)
    if meta_error != "":
        _report_usage(harness, name, "gate '%s' metadata invalid: %s" % [name, meta_error])
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
    _index += 1
    _say(name, meta_dict, "running", "")
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
    # A result produced by a gate that is itself running inside another gate says so. It is a
    # real result and worth printing — a nested run that failed matters — but it is not one of
    # the two runs an order check is comparing, and pairing lines by name without this made two
    # gates compare pass one against pass one.
    if harness.gate_depth > 1:
        row["nested"] = true
    last_row = row
    _say(
        name, meta_dict,
        "%s in %.2fs" % ["PASS" if row["pass"] else "FAIL", elapsed_s],
        row["detail"] as String
    )
    print("HARNESS_GATE_RESULT " + JSON.stringify(row))
    gate_finished.emit(row)
    return OK if row["pass"] else FAIL


## A usage failure for one gate, printed in the same shape as a result so a suite run does not
## have two formats to parse.
func _report_usage(harness: Node, name: String, message: String) -> void:
    printerr("HARNESS_ERROR " + message)
    var row: Dictionary = {
        "gate": name, "pass": false, "detail": message, "measured": null,
    }
    # Marked the same way a result is. A gate that asks for a gate which does not exist is the
    # commonest nested line of all — `console_fronts_agree` asks three times, once per front end —
    # and without this the order check counted six top-level results for a name that was never
    # run at the top level at all.
    if harness.gate_depth > 1:
        row["nested"] = true
    print("HARNESS_GATE_RESULT " + JSON.stringify(row))


