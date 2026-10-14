class_name GearboxKeys
extends RefCounted
## A ground vehicle's gearbox keys, upstream's `Engine::UpdateInputEvents` and its default keys:
## PgUp and PgDn move the automatic selector (automatic only), Q steps through the gearbox modes
## (automatic, semi-automatic, manual, manual stick, manual with ranges), Left Shift is the manual
## clutch pedal (it acts in the manual modes), A and Z shift up and down a gear in the automatic,
## semi-automatic and sequential manual modes, and D shifts to neutral outside automatic. A held key
## repeats every fifth of a second, upstream's `getEventBoolValueBounce`.
##
## The stick modes take a gear while its key is held, and upstream binds none: with no gear held
## its stick goes to neutral every frame, as it does here.

const BOUNCE: float = 0.2
const MANUAL: int = 2

## Per action, the seconds until it may act again.
var _bounce: Dictionary = {}


## One frame, after the pedals, handed to `solver`.
func read(solver: RefCounted, keys: Dictionary, delta: float) -> void:
    for action: String in _bounce.keys():
        _bounce[action] = float(_bounce[action]) - delta
    var state: Dictionary = solver.gearbox("")
    var mode: int = state["mode_index"]
    if mode == 0:
        if _bounced(keys, "auto_up"):
            solver.gearbox("auto_up")
        if _bounced(keys, "auto_down"):
            solver.gearbox("auto_down")
    if _bounced(keys, "shift_mode"):
        state = solver.gearbox("mode")
        mode = state["mode_index"]
        print("DRIVE  gearbox %s" % state["mode"])
    solver.gearbox("clutch", 1.0 if DriveKeys.held(keys, "clutch") else 0.0)
    if mode <= MANUAL:
        if _bounced(keys, "shift_up"):
            solver.gearbox("up")
        elif _bounced(keys, "shift_down"):
            solver.gearbox("down")
        elif mode != 0 and _bounced(keys, "shift_neutral"):
            solver.gearbox("neutral")
    elif int(state["gear"]) != 0 or not DriveKeys.held(keys, "shift_neutral"):
        # A stick with no gear key held goes to neutral (upstream's `if (!found) shiftTo(0)`).
        solver.gearbox("to", 0.0)


func _bounced(keys: Dictionary, action: String) -> bool:
    if float(_bounce.get(action, 0.0)) > 0:
        return false
    if not DriveKeys.held(keys, action):
        return false
    _bounce[action] = BOUNCE
    return true
