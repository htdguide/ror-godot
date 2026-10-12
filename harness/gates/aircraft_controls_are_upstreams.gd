extends GateBase
## An airplane's controls are upstream's (`GameContext::UpdateAirplaneInputEvents`, its default
## keys): the arrows move the aileron and the elevator, Z and X the rudder, each towards its key at
## 4 a second (`smoothValue`); B brakes at two thirds; P toggles the parking brake; 1 and 2 step the
## flaps, Ctrl+1 and Ctrl+2 to none and full. Each wing then deflects by the controls its control
## surface follows (`Actor::updateVisual`): ailerons both ways, rudder, elevator and stabilators,
## flaps, elevons, flaperons, tailerons and ruddervators, scaled by its own limits.
##
## Ours had none: wings stayed centred.
##
## The oracle is upstream's code read rule by rule: key events through the engine's own input, and
## a rig with one wing of every kind.

const FRAME: float = 1.0 / 60.0
const FLAP_ANGLES: Array[float] = [0.0, -0.07, -0.17, -0.33, -0.67, -1.0]
const KINDS: String = "abrefSTcdVUghij"


static func meta() -> Dictionary:
    return {
        "name": "aircraft_controls_are_upstreams",
        "proves": "airplane keys move the aileron, elevator, rudder, flaps and brakes as upstream's UpdateAirplaneInputEvents does, and every wing kind deflects as updateVisual makes it",
        "builds_on": [],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "smoothing 4/s frame by frame, flap steps and limits, brake 0.66, every wing kind's deflection exact",
        "why": "aircraft had no controls: every wing flew centred.",
        "budget_s": 20.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var keys: AirplaneKeys = AirplaneKeys.new()
    var solver: RorSolver = _plane()
    _press(KEY_RIGHT, true)
    _press(KEY_UP, true)
    # Upstream's `smoothValue` stops a falling value at its target but not a rising one: the
    # aileron overshoots 1 by up to a frame's step and comes back the frame after; the elevator,
    # falling to -1, stops there. The wings clamp the controls to -1..1 before they read them.
    var rising: float = 0.0
    var falling: float = 0.0
    var overshot: bool = false
    for frame: int in 20:
        keys.read(solver, FRAME)
        if rising > 1.0:
            rising = maxf(rising - FRAME * 4.0, 1.0)
        elif rising < 1.0:
            rising += FRAME * 4.0
        falling = maxf(falling - FRAME * 4.0, -1.0)
        overshot = overshot or rising > 1.0
        if absf(keys.aileron - rising) > 1e-9 or absf(keys.elevator - falling) > 1e-9:
            return fail("frame %d holding right and up: aileron %.4f, elevator %.4f; upstream's smoothing gives %.4f and %.4f" % [
                frame, keys.aileron, keys.elevator, rising, falling])
    if not overshot or keys.aileron != 1.0:
        return fail("the aileron never overshot 1 and came back as upstream's smoothValue does (now %.4f)" % keys.aileron)
    _press(KEY_RIGHT, false)
    _press(KEY_UP, false)
    keys.read(solver, FRAME)
    if absf(keys.aileron - (1.0 - FRAME * 4.0)) > 1e-9:
        return fail("let go, the aileron went to %.4f, not back by one frame's 4/s" % keys.aileron)
    _press(KEY_Z, true)
    for frame: int in 30:
        keys.read(solver, FRAME)
    _press(KEY_Z, false)
    if keys.rudder != 1.0:
        return fail("Z held for half a second left the rudder at %.3f, not full left" % keys.rudder)
    for k: int in 7:
        keys.on_key(KEY_2)
    if keys.flap != 5:
        return fail("seven steps of flaps reached %d, not upstream's top 5" % keys.flap)
    _press(KEY_CTRL, true)
    keys.on_key(KEY_1)
    _press(KEY_CTRL, false)
    if keys.flap != 0:
        return fail("Ctrl+1 left the flaps at %d" % keys.flap)
    _press(KEY_B, true)
    keys.read(solver, FRAME)
    if absf(solver.brake_command() - 0.66) > 1e-6:
        return fail("B braked %.3f, not upstream's 0.66" % solver.brake_command())
    # With the parking brake on upstream leaves the brake where it was: letting go of B changes nothing.
    keys.on_key(KEY_P)
    _press(KEY_B, false)
    keys.read(solver, FRAME)
    if not keys.parking or absf(solver.brake_command() - 0.66) > 1e-6:
        return fail("with the parking brake on, letting go of B changed the brake to %.3f" % solver.brake_command())

    # Every wing kind, at a mixed set of controls.
    var aileron: float = 0.6
    var rudder: float = -0.3
    var elevator: float = 0.45
    var flap: int = 3
    solver.set_aero_controls(aileron, rudder, elevator, flap)
    solver.step(1.0 / 2000.0, 1)
    var f: float = FLAP_ANGLES[flap]
    var values: Dictionary = {
        "a": aileron, "b": -aileron, "r": rudder, "e": elevator, "S": elevator, "T": elevator, "f": f,
        "c": (aileron + elevator) / 2.0, "V": (aileron + elevator) / 2.0, "d": (-aileron + elevator) / 2.0,
        "U": (-aileron + elevator) / 2.0, "g": (aileron + f) / 2.0, "h": (-aileron + f) / 2.0,
        "i": (-elevator + rudder) / 2.0, "j": (elevator + rudder) / 2.0,
    }
    for i: int in KINDS.length():
        var kind: String = KINDS[i]
        var v: float = _f1(values[kind])
        var expect: float = _f1(-v * 10.0) if v < 0.0 else _f1(v * 20.0)
        var got: float = solver.wing_state(i)["deflection"]
        if absf(got - expect) > 1e-6:
            return fail("a '%s' wing deflected %.4f; upstream's updateVisual gives %.4f" % [kind, got, expect])
    return ok("smoothing 4/s, flaps 0 to 5, brake 0.66 and the parking brake, and all %d wing kinds deflect as upstream's" % KINDS.length(), 0)


## A rig with one wing of each kind, limits 10 down and 20 up.
func _plane() -> RorSolver:
    var text: String = "plane\nglobals\n1000, 0, tracks/semi\nnodes\n"
    var rows: String = ""
    for i: int in KINDS.length():
        var z: float = float(i) * 2.0
        for k: int in 8:
            text += "%d, %s, %s, %s\n" % [i * 8 + k, 2.0 * float(k % 2), 0.1 * float((k / 2) % 2), z + float(k / 4)]
        rows += "%d, %d, %d, %d, %d, %d, %d, %d, 0, 0, 1, 0, 0, 1, 1, 1, %s, 0.75, 10, 20, NACA0009.afl\n" % [
            i * 8, i * 8 + 1, i * 8 + 2, i * 8 + 3, i * 8 + 4, i * 8 + 5, i * 8 + 6, i * 8 + 7, KINDS[i]]
    text += "beams\n0, 1\nwings\n" + rows + "end"
    var truck: TruckParser = TruckParser.new()
    truck.parse_text(text)
    var solver: RorSolver = RigBuilder.build(truck, 0.0)["solver"] as RorSolver
    solver.set_gravity(Vector3.ZERO)
    return solver


func _press(keycode: Key, down: bool) -> void:
    var event: InputEventKey = InputEventKey.new()
    event.keycode = keycode
    event.physical_keycode = keycode
    event.pressed = down
    Input.parse_input_event(event)
    Input.flush_buffered_events()


func _f1(x: float) -> float:
    return PackedFloat32Array([x])[0]
