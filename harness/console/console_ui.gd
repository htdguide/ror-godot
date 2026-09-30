class_name ConsoleUi
extends CanvasLayer
## The drop-down console: the third front end onto `ConsoleTable`, and the one a person uses.
##
## Quake and Counter-Strike shaped this deliberately. It is the interaction Rigs of Rods players
## and developers already have in their hands, and it is the one piece of UI that is useful
## before any other UI exists — PLAN C1 builds a menu and a vehicle selector on top of a client
## that can already be driven from here.
##
## It dispatches into the same table as the agent's channel and nothing else. There is no
## "console command" that only the keyboard can reach, and `console_fronts_agree` drives this
## front end's own submit path to hold that.
##
## Opens on ` or F1, over whatever is running, without pausing it: a console that pauses the
## simulation cannot be used to look at the simulation.

## How much of the screen it covers when open, and how fast it gets there.
const HEIGHT_SHARE: float = 0.45
const SLIDE_SECONDS: float = 0.12
const HISTORY_FILE: String = "console/history.txt"
const MAX_HISTORY: int = 200
const MAX_OUTPUT_LINES: int = 500

## Severity colours. Deliberately few: a console that colours everything reads as a Christmas
## tree and a person stops seeing the one red line that matters.
const COLOUR_ECHO: Color = Color(0.62, 0.66, 0.72)
const COLOUR_OK: Color = Color(0.86, 0.88, 0.92)
const COLOUR_ERROR: Color = Color(0.94, 0.45, 0.40)
const COLOUR_HINT: Color = Color(0.48, 0.70, 0.90)

var _table: ConsoleTable = null
var _panel: PanelContainer = null
var _output: RichTextLabel = null
var _input: LineEdit = null
var _open: bool = false
var _history: PackedStringArray = PackedStringArray()
var _history_at: int = 0
## `keycode -> command line`, from `bind`. The UI's own, unlike aliases: a key is a property of
## a keyboard and means nothing to the agent's channel.
var _binds: Dictionary = {}
## Completions offered for the current input, and where in them Tab has walked.
var _cycle: PackedStringArray = PackedStringArray()
var _cycle_at: int = -1
var _cycle_for: String = ""


func setup(table: ConsoleTable) -> void:
    _table = table
    # A suite run is minutes long. Without this the console shows nothing until it is over,
    # which is the same as showing nothing.
    _table.progress.connect(_on_progress)
    layer = CONSOLE_LAYER
    _build()
    _load_history()
    _say("console ready. `help` lists commands, Tab completes, Up recalls.", COLOUR_HINT)


## Above the HUD and the settings panel: a console that opens behind something is a console
## nobody can read.
const CONSOLE_LAYER: int = 128


func _build() -> void:
    _panel = PanelContainer.new()
    _panel.name = "ConsolePanel"
    _panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
    _panel.anchor_bottom = HEIGHT_SHARE
    _panel.visible = false
    var style: StyleBoxFlat = StyleBoxFlat.new()
    style.bg_color = Color(0.05, 0.06, 0.08, 0.92)
    style.border_color = Color(0.20, 0.24, 0.30, 1.0)
    style.border_width_bottom = 2
    style.content_margin_left = 10.0
    style.content_margin_right = 10.0
    style.content_margin_top = 8.0
    style.content_margin_bottom = 8.0
    _panel.add_theme_stylebox_override("panel", style)

    var column: VBoxContainer = VBoxContainer.new()
    _output = RichTextLabel.new()
    _output.bbcode_enabled = true
    _output.scroll_following = true
    _output.selection_enabled = true
    _output.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _output.add_theme_font_size_override("normal_font_size", 14)
    column.add_child(_output)

    _input = LineEdit.new()
    _input.placeholder_text = "command"
    _input.caret_blink = true
    _input.add_theme_font_size_override("font_size", 14)
    _input.text_submitted.connect(_on_submitted)
    # Tab and the history keys have to be seen before the LineEdit consumes them.
    _input.gui_input.connect(_on_input_key)
    column.add_child(_input)
    _panel.add_child(column)
    add_child(_panel)


## --------------------------------------------------------------------------------
## Opening and keys


func _unhandled_key_input(event: InputEvent) -> void:
    var key: InputEventKey = event as InputEventKey
    if key == null or not key.pressed or key.echo:
        return
    if key.keycode == KEY_QUOTELEFT or key.keycode == KEY_F1:
        toggle()
        get_viewport().set_input_as_handled()
        return
    if _open and key.keycode == KEY_ESCAPE:
        set_open(false)
        get_viewport().set_input_as_handled()
        return
    if not _open and _binds.has(key.keycode):
        _submit(_binds[key.keycode] as String)
        get_viewport().set_input_as_handled()


func toggle() -> void:
    set_open(not _open)


func set_open(open: bool) -> void:
    _open = open
    _panel.visible = open
    var to: float = 0.0 if open else -_panel.size.y
    var tween: Tween = create_tween()
    tween.tween_property(_panel, "position:y", to, SLIDE_SECONDS)
    if open:
        _input.grab_focus()
        _input.clear()
    else:
        _input.release_focus()


func is_open() -> bool:
    return _open


func _on_input_key(event: InputEvent) -> void:
    var key: InputEventKey = event as InputEventKey
    if key == null or not key.pressed:
        return
    match key.keycode:
        KEY_TAB:
            _complete()
            _input.accept_event()
        KEY_UP:
            _recall(-1)
            _input.accept_event()
        KEY_DOWN:
            _recall(1)
            _input.accept_event()


## --------------------------------------------------------------------------------
## Completion and history


## Tab completes to the single match, or cycles the matches and shows them once.
##
## Cycling rather than only completing the common prefix, because most of this table's argument
## completions are long and similar — gate names especially — and a person looking for one of
## seventy-eight gates wants to walk them, not to type enough to disambiguate.
func _complete() -> void:
    var line: String = _input.text
    if _cycle_at < 0 or line != _cycle_for:
        _cycle = _table.complete(line)
        _cycle_at = -1
        _cycle_for = line
        if _cycle.is_empty():
            return
        if _cycle.size() == 1:
            _apply_completion(line, _cycle[0])
            return
        _say("  " + "  ".join(_cycle), COLOUR_HINT)
    if _cycle.is_empty():
        return
    _cycle_at = (_cycle_at + 1) % _cycle.size()
    _apply_completion(_cycle_for, _cycle[_cycle_at])


## Replaces the last word of `line` with `completion`, keeping what came before it.
func _apply_completion(line: String, completion: String) -> void:
    var head: String = ""
    if not line.ends_with(" "):
        var cut: int = line.rfind(" ")
        head = line.substr(0, cut + 1) if cut >= 0 else ""
        # A completion of a multi-word command name replaces the whole line, not its last word.
        if completion.begins_with(line):
            head = ""
    else:
        head = line
    _input.text = head + completion
    _input.caret_column = _input.text.length()


func _recall(direction: int) -> void:
    if _history.is_empty():
        return
    _history_at = clampi(_history_at + direction, 0, _history.size())
    _input.text = "" if _history_at >= _history.size() else _history[_history_at]
    _input.caret_column = _input.text.length()


func _load_history() -> void:
    var path: String = HarnessCapture.resolve_dir("").path_join(HISTORY_FILE)
    if not FileAccess.file_exists(path):
        _history_at = 0
        return
    for line: String in FileAccess.get_file_as_string(path).split("\n"):
        if not line.strip_edges().is_empty():
            _history.append(line)
    if _history.size() > MAX_HISTORY:
        _history = _history.slice(_history.size() - MAX_HISTORY)
    _history_at = _history.size()


func _save_history() -> void:
    var path: String = HarnessCapture.resolve_dir("").path_join(HISTORY_FILE)
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    var handle: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    if handle == null:
        return
    for line: String in _history:
        handle.store_line(line)
    handle.close()


## --------------------------------------------------------------------------------
## Running a line


func _on_submitted(text: String) -> void:
    _input.clear()
    _submit(text)


## Runs one line through the table and shows the result. The same entry point a bind uses, and
## the one `console_fronts_agree` drives, so what the gate checks is what a person does.
func submit(text: String) -> void:
    await _submit(text)


func _submit(text: String) -> void:
    var line: String = text.strip_edges()
    if line.is_empty():
        return
    _remember(line)
    _say("> " + line, COLOUR_ECHO)
    # `bind` is the UI's own: a key means nothing to the agent's channel, so it never reaches
    # the table.
    if line.begins_with("bind "):
        _say(_bind(line.substr(5)), COLOUR_HINT)
        return
    if line == "clear":
        _output.clear()
        return
    var result: Dictionary = await _table.dispatch(line)
    var detail: String = result.get("detail", "") as String
    var artifact: String = result.get("artifact", "") as String
    if artifact != "":
        detail = "%s -> %s" % [detail, artifact]
    _say(detail, COLOUR_OK if result.get("ok", false) else COLOUR_ERROR)


func _remember(line: String) -> void:
    if _history.is_empty() or _history[_history.size() - 1] != line:
        _history.append(line)
        if _history.size() > MAX_HISTORY:
            _history = _history.slice(_history.size() - MAX_HISTORY)
        _save_history()
    _history_at = _history.size()
    _cycle_at = -1


## `bind <key> <line>`, where the key is a name Godot knows: F2, HOME, K.
func _bind(rest: String) -> String:
    var cut: int = rest.find(" ")
    if cut < 0:
        return "usage: bind <key> <command>"
    var key_name: String = rest.substr(0, cut).strip_edges().to_upper()
    var keycode: int = OS.find_keycode_from_string(key_name)
    if keycode == KEY_NONE:
        return "no key called '%s'" % key_name
    _binds[keycode] = rest.substr(cut + 1).strip_edges()
    return "%s runs '%s' while the console is closed" % [key_name, _binds[keycode]]


## A gate finished while a command is still running: show it now, not at the end.
func _on_progress(text: String, ok: bool) -> void:
    _say(text, COLOUR_OK if ok else COLOUR_ERROR)


func _say(text: String, colour: Color) -> void:
    _output.push_color(colour)
    _output.add_text(text)
    _output.pop()
    _output.newline()
    if _output.get_line_count() > MAX_OUTPUT_LINES:
        _output.remove_paragraph(0)
