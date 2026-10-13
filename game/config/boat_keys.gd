class_name BoatKeys
extends RefCounted
## A boat's controls, upstream's `GameContext::UpdateBoatInputEvents` and its default keys: Up and
## Down a twentieth of throttle more or less every tenth of a second held, Left and Right the
## rudder by the time held (it stays where it is let go), PgDn the rudder centred, PgUp the
## reverser toggled. Every screw prop takes the same command. A vehicle is a boat, as upstream
## decides it, when it has screw props (`ar_driveable`).

## Keys held on screen (`AirplanePad`), counted as held on the keyboard.
var held: Dictionary = {}
## Upstream's `getEventBoolValueBounce`: per key, the seconds until it may act again.
var _bounce: Dictionary = {}


## One frame, handed to `solver`.
func read(solver: RefCounted, delta: float) -> void:
    for key: Key in _bounce.keys():
        _bounce[key] = float(_bounce[key]) - delta
    if _bounced(KEY_DOWN, 0.1):
        solver.boat_command("throttle_step", -0.05)
    if _bounced(KEY_UP, 0.1):
        solver.boat_command("throttle_step", 0.05)
    var sum_steer: float = (_key(KEY_LEFT) - _key(KEY_RIGHT)) * delta
    if absf(sum_steer) > 0:
        solver.boat_command("rudder_step", sum_steer)
    if _bounced(KEY_PAGEDOWN, 0.1):
        solver.boat_command("center")
    if _bounced(KEY_PAGEUP, 0.2):
        solver.boat_command("reverse")


## No key presses of its own: every boat control is read as held, in `read`.
func on_key(_keycode: Key, _solver: RefCounted = null, _ctrl: bool = false) -> bool:
    return false


func _bounced(keycode: Key, time: float) -> bool:
    if float(_bounce.get(keycode, 0.0)) > 0:
        return false
    if _key(keycode) == 0.0:
        return false
    _bounce[keycode] = time
    return true


func _key(keycode: Key) -> float:
    return 1.0 if Input.is_key_pressed(keycode) or held.has(keycode) else 0.0
