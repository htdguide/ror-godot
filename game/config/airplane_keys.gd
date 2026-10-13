class_name AirplaneKeys
extends RefCounted
## An airplane's controls, upstream's `GameContext::UpdateAirplaneInputEvents` and its default keys:
## the arrows bank (aileron, which also steers the nose wheel through the hydros) and pitch
## (elevator), Z and X the rudder, B the brake, P the parking brake, 1 and 2 a step of flaps less or
## more, Ctrl+1 and Ctrl+2 none or full, 3 and 4 the air brakes the same way; PgUp and PgDn a
## twentieth of throttle more or less every tenth of a second held, Ctrl+PgUp and Ctrl+PgDn full and none, Ctrl+Home the engines on or off,
## R the reversers. The three surfaces follow their keys at 4 a second, as upstream's
## `smoothValue` moves them.
##
## A vehicle is an airplane, as upstream decides it, when it has aero engines (`ar_driveable`).

const COMMAND_RATE: float = 4.0
## Upstream's brake for an aircraft, two thirds of a truck's.
const BRAKE: float = 0.66

var aileron: float = 0.0
var elevator: float = 0.0
var rudder: float = 0.0
var flap: int = 0
## Upstream's `ar_airbrake_intensity`, 0 to 5: 3 and 4 a step less or more, Ctrl+3 and Ctrl+4 none and full.
var airbrake: int = 0
var parking: bool = false
## Keys held on screen (`AirplanePad`), counted as held on the keyboard.
var held: Dictionary = {}
## Upstream's `getEventBoolValueBounce(..., 0.1)`: a held throttle key repeats every tenth of a second.
var _throttle_wait: float = 0.0


## One frame: the surfaces smoothed towards the keys, the brake, all handed to `solver`.
func read(solver: RefCounted, delta: float) -> void:
    var steer: float = _key(KEY_RIGHT) - _key(KEY_LEFT)
    var pitch: float = _key(KEY_DOWN) - _key(KEY_UP)
    var yaw: float = _key(KEY_Z) - _key(KEY_X)
    aileron = smooth(aileron, steer, delta * COMMAND_RATE)
    elevator = smooth(elevator, pitch, delta * COMMAND_RATE)
    rudder = smooth(rudder, yaw, delta * COMMAND_RATE)
    solver.set_aero_controls(aileron, rudder, elevator, flap)
    # Upstream's `ar_hydro_dir_command = ar_aileron`, in the solver's own sign (right positive).
    solver.set_steer_command(aileron)
    solver.set_parking_brake(parking)
    if not parking:
        solver.set_brake(_key(KEY_B) * BRAKE)
    var step: float = _key(KEY_PAGEUP) - _key(KEY_PAGEDOWN)
    _throttle_wait -= delta
    if step == 0.0 or Input.is_key_pressed(KEY_CTRL):
        _throttle_wait = 0.0
    elif _throttle_wait <= 0.0:
        solver.aero_command("throttle_step", 0.05 * step)
        _throttle_wait = 0.1


## A key press: the flaps and the parking brake, `ctrl` as if Ctrl were held. Whether it was one of these.
func on_key(keycode: Key, solver: RefCounted = null, ctrl: bool = false) -> bool:
    ctrl = ctrl or Input.is_key_pressed(KEY_CTRL)
    if solver != null:
        var command: Array = [] if not ctrl and keycode != KEY_R else \
                {KEY_PAGEUP: ["throttle", 1.0], KEY_PAGEDOWN: ["throttle", 0.0], KEY_HOME: ["start", 0.0], KEY_R: ["reverse", 0.0]}.get(keycode, [])
        if not command.is_empty():
            solver.aero_command(command[0], command[1])
            print("DRIVE  engines: %s" % command[0])
            return true
    match keycode:
        KEY_P:
            parking = not parking
        KEY_1:
            flap = 0 if ctrl else maxi(flap - 1, 0)
        KEY_2:
            flap = 5 if ctrl else mini(flap + 1, 5)
        KEY_3, KEY_4:
            if solver == null:
                return false
            var more: bool = keycode == KEY_4
            airbrake = (5 if more else 0) if ctrl else clampi(airbrake + (1 if more else -1), 0, 5)
            solver.aero_command("airbrake", airbrake)
        _:
            return false
    print("DRIVE  flaps %d, air brakes %d, parking brake %s" % [flap, airbrake, "on" if parking else "off"])
    return true


## Upstream's `smoothValue`: `value` clamped to -1..1, approached from `ref` by `rate`.
static func smooth(ref: float, value: float, rate: float) -> float:
    value = clampf(value, -1.0, 1.0)
    if ref > value:
        ref -= rate
        if ref < value:
            ref = value
    elif ref < value:
        ref += rate
    return ref


func _key(keycode: Key) -> float:
    return 1.0 if Input.is_key_pressed(keycode) or held.has(keycode) else 0.0
