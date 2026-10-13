class_name AirplanePad
extends CanvasLayer
## On-screen buttons for an airplane's keys, for a keyboard without Home, PgUp and PgDn (a Mac's).
## A held button counts as its key held (`AirplaneKeys.held`); a tapped one is its key pressed,
## the Ctrl ones as if Ctrl were down. Press Esc to free the mouse first, then click. A button
## lights while held, flashes when tapped, and the parking brake stays lit while it is on.

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

var _keys: AirplaneKeys
var _solver: RefCounted


func _init(keys: AirplaneKeys, solver: RefCounted) -> void:
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
    for row: Array in HELD:
        var key: Key = row[1]
        var button: Button = _button(grid, row[0])
        button.button_down.connect(func() -> void:
            _keys.held[key] = true
            button.modulate = LIT)
        button.button_up.connect(func() -> void:
            _keys.held.erase(key)
            button.modulate = Color.WHITE)
    for row: Array in TAPPED:
        var key: Key = row[1]
        var ctrl: bool = row[2]
        var button: Button = _button(grid, row[0])
        button.pressed.connect(func() -> void:
            _keys.on_key(key, _solver, ctrl)
            _flash(button, key == KEY_P and _keys.parking))


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
