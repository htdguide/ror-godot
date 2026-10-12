class_name AirplaneKeys
extends RefCounted
## An airplane's controls, upstream's `GameContext::UpdateAirplaneInputEvents` and its default keys:
## the arrows bank (aileron, which also steers the nose wheel through the hydros) and pitch
## (elevator), Z and X the rudder, B the brake, P the parking brake, 1 and 2 a step of flaps less or
## more, Ctrl+1 and Ctrl+2 none or full. The three surfaces follow their keys at 4 a second, as
## upstream's `smoothValue` moves them.
##
## A vehicle is an airplane, as upstream decides it, when it has aero engines (`ar_driveable`).

const COMMAND_RATE: float = 4.0
## Upstream's brake for an aircraft, two thirds of a truck's.
const BRAKE: float = 0.66

var aileron: float = 0.0
var elevator: float = 0.0
var rudder: float = 0.0
var flap: int = 0
var parking: bool = false


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


## A key press: the flaps and the parking brake. Whether it was one of these.
func on_key(keycode: Key) -> bool:
    var ctrl: bool = Input.is_key_pressed(KEY_CTRL)
    match keycode:
        KEY_P:
            parking = not parking
        KEY_1:
            flap = 0 if ctrl else maxi(flap - 1, 0)
        KEY_2:
            flap = 5 if ctrl else mini(flap + 1, 5)
        _:
            return false
    print("DRIVE  flaps %d, parking brake %s" % [flap, "on" if parking else "off"])
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
    return 1.0 if Input.is_key_pressed(keycode) else 0.0
