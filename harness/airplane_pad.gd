class_name AirplanePad
extends CanvasLayer
## On-screen buttons for an airplane's or a boat's keys, for a keyboard without Home, PgUp and PgDn
## (a Mac's).
## A held button counts as its key held (`AirplaneKeys.held`); a tapped one is its key pressed,
## the Ctrl ones as if Ctrl were down. Press Esc to free the mouse first, then click. A button
## lights while held, flashes when tapped, and the parking brake stays lit while it is on.
##
## On the left, the autopilot's panel, which upstream works from the airplane dashboard with the
## mouse (`OverlayWrapper`): its modes, lit while on, the steps its settings take, and what it holds.

const LIT: Color = Color(1.0, 0.8, 0.2)

## Label, key: held while the button is down.
const HELD: Array = [
    ["Throttle +", KEY_PAGEUP], ["Throttle -", KEY_PAGEDOWN], ["Roll left", KEY_LEFT], ["Roll right", KEY_RIGHT],
    ["Stick forward", KEY_UP], ["Stick back", KEY_DOWN], ["Rudder left", KEY_Z], ["Rudder right", KEY_X],
    ["Brake", KEY_B],
]
## Label, key, with Ctrl: one press per click.
const TAPPED: Array = [
    ["Engines on/off", KEY_HOME, true], ["Full throttle", KEY_PAGEUP, true], ["Idle", KEY_PAGEDOWN, true],
    ["Reverse", KEY_R, false], ["Flaps -", KEY_1, false], ["Flaps +", KEY_2, false], ["Air brakes -", KEY_3, false],
    ["Air brakes +", KEY_4, false], ["Parking brake", KEY_P, false],
]

## Autopilot mode buttons: label, the action that toggles it, and the state that says it is on.
const AUTOPILOT_MODES: Array = [
    ["HDG", "hdg", "heading_mode"], ["WLV", "wlv", "heading_mode"], ["NAV", "nav", "heading_mode"],
    ["ALT", "alt", "alt_mode"], ["V/S", "vs", "alt_mode"], ["IAS", "ias", "ias_mode"], ["GPWS", "gpws", "gpws"],
]
## Autopilot setting steps: label, action, step (upstream's dashboard trims).
const AUTOPILOT_STEPS: Array = [
    ["HDG -", "adj_hdg", -1], ["HDG +", "adj_hdg", 1], ["ALT -", "adj_alt", -100], ["ALT +", "adj_alt", 100],
    ["V/S -", "adj_vs", -100], ["V/S +", "adj_vs", 100], ["IAS -", "adj_ias", -1], ["IAS +", "adj_ias", 1],
]

## A boat's: every control is held, the rudder centred and the reverser toggled by a short hold.
const BOAT_HELD: Array = [
    ["Throttle +", KEY_UP], ["Throttle -", KEY_DOWN], ["Rudder left", KEY_LEFT], ["Rudder right", KEY_RIGHT],
    ["Center rudder", KEY_PAGEDOWN], ["Reverse", KEY_PAGEUP],
]

var _keys: RefCounted
var _solver: RefCounted
var _autopilot_label: Label = null


func _init(keys: RefCounted, solver: RefCounted) -> void:
    _keys = keys
    _solver = solver
    name = "AirplanePad"
    layer = 3
    var grid: GridContainer = GridContainer.new()
    grid.columns = 2
    grid.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
    grid.grow_horizontal = Control.GROW_DIRECTION_BEGIN
    grid.grow_vertical = Control.GROW_DIRECTION_BOTH
    add_child(grid)
    var boat: bool = keys is BoatKeys
    for row: Array in (BOAT_HELD if boat else HELD):
        var key: Key = row[1]
        var button: Button = _button(grid, row[0])
        button.button_down.connect(func() -> void:
            _keys.held[key] = true
            button.modulate = LIT)
        button.button_up.connect(func() -> void:
            _keys.held.erase(key)
            button.modulate = Color.WHITE)
    for row: Array in ([] if boat else TAPPED):
        var key: Key = row[1]
        var ctrl: bool = row[2]
        var button: Button = _button(grid, row[0])
        button.pressed.connect(func() -> void:
            _keys.on_key(key, _solver, ctrl)
            _flash(button, key == KEY_P and bool(_keys.get("parking"))))
    if not boat and not (_solver.autopilot("state") as Dictionary).is_empty():
        _build_autopilot()


func _process(_delta: float) -> void:
    if _autopilot_label == null:
        return
    var state: Dictionary = _solver.autopilot("state")
    _autopilot_label.text = "Autopilot  HDG %03d   ALT %d ft   V/S %d   IAS %d kt%s" % [
        state["heading"], state["alt"], state["vs"], state["ias"], "" if state["ils"] else "   (no ILS)"]
    for row: Array in AUTOPILOT_MODES:
        var value: Variant = state[row[2]]
        var on: bool = value == row[1] if value is String else bool(value)
        button(row[0]).modulate = LIT if on else Color.WHITE


func _build_autopilot() -> void:
    var column: VBoxContainer = VBoxContainer.new()
    column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 12)
    column.grow_vertical = Control.GROW_DIRECTION_BOTH
    add_child(column)
    _autopilot_label = Label.new()
    column.add_child(_autopilot_label)
    var grid: GridContainer = GridContainer.new()
    grid.columns = 2
    column.add_child(grid)
    for row: Array in AUTOPILOT_MODES:
        var action: String = row[1]
        _button(grid, row[0]).pressed.connect(func() -> void: _solver.autopilot(action))
    for row: Array in AUTOPILOT_STEPS:
        var action: String = row[1]
        var step: int = row[2]
        var trim: Button = _button(grid, row[0])
        trim.pressed.connect(func() -> void:
            _solver.autopilot(action, step)
            _flash(trim, false))


## The button labelled `label`, for a gate to press.
func button(label: String) -> Button:
    return find_child(label.validate_node_name(), true, false) as Button


## Lit, then faded back over a quarter second unless `stay` keeps it lit.
func _flash(button: Button, stay: bool) -> void:
    button.modulate = LIT
    if not stay and button.is_inside_tree():
        button.create_tween().tween_property(button, "modulate", Color.WHITE, 0.25).set_delay(0.1)


func _button(grid: GridContainer, label: String) -> Button:
    var button: Button = Button.new()
    button.text = label
    button.name = label.validate_node_name()
    button.focus_mode = Control.FOCUS_NONE
    button.custom_minimum_size = Vector2(130, 34)
    grid.add_child(button)
    return button
