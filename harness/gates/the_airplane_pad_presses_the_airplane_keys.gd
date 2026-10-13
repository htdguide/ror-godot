extends GateBase
## The play window's on-screen airplane buttons (`AirplanePad`) are the airplane's keys: a held
## button is its key held, a tapped one its key pressed, the Ctrl ones with Ctrl, for a keyboard
## without Home, PgUp and PgDn.
##
## Ours had none: on a Mac the engines could not be started, nor the throttle moved.
##
## The oracle is `AirplaneKeys` itself, read through the keyboard in `aircraft_controls_are_upstreams`.

const FRAME: float = 1.0 / 60.0


static func meta() -> Dictionary:
    return {
        "name": "the_airplane_pad_presses_the_airplane_keys",
        "proves": "the on-screen airplane buttons hold and press the airplane's keys, the Ctrl ones with Ctrl, and light when pressed; the autopilot panel toggles and steps it",
        "builds_on": ["aircraft_controls_are_upstreams"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "held roll gives full aileron and letting go starts it back; brake 0.66; flaps step, the parking brake toggles; the throttle steps 0.05 and Full throttle (Ctrl+PgUp) reaches 1",
        "why": "a Mac keyboard has no Home, PgUp or PgDn: the engines could not be started.",
        "budget_s": 10.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join("assets/corpus/181_supermarine-spitfire")
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: the Spitfire is not present", 0)
    var solver: RorSolver = RigBuilder.from_file(mod_dir, "spitfire_Vb.airplane", 0.0)["solver"]
    var keys: AirplaneKeys = AirplaneKeys.new()
    var pad: AirplanePad = AirplanePad.new(keys, solver)
    pad.button("Roll right").button_down.emit()
    pad.button("Brake").button_down.emit()
    for frame: int in 30:
        keys.read(solver, FRAME)
    if pad.button("Brake").modulate != AirplanePad.LIT:
        pad.free()
        return fail("the held Brake button is not lit")
    if keys.aileron != 1.0 or absf(solver.brake_command() - 0.66) > 1e-6:
        pad.free()
        return fail("held, Roll right left the aileron at %.3f and Brake braked %.3f" % [keys.aileron, solver.brake_command()])
    pad.button("Roll right").button_up.emit()
    keys.read(solver, FRAME)
    if keys.aileron >= 1.0:
        pad.free()
        return fail("let go, Roll right still holds the aileron at %.3f" % keys.aileron)
    pad.button("Flaps +").pressed.emit()
    pad.button("Flaps +").pressed.emit()
    if keys.flap != 2:
        pad.free()
        return fail("two taps of Flaps + gave flaps %d" % keys.flap)
    pad.button("Flaps -").pressed.emit()
    pad.button("Parking brake").pressed.emit()
    if keys.flap != 1 or not keys.parking or pad.button("Parking brake").modulate != AirplanePad.LIT:
        pad.free()
        return fail("Flaps - gave flaps %d, Parking brake left it %s, its button lit %s" % [keys.flap, keys.parking, pad.button("Parking brake").modulate == AirplanePad.LIT])
    var start: float = solver.aero_state(0)["throttle"]
    pad.button("Throttle +").button_down.emit()
    keys.read(solver, FRAME)
    pad.button("Throttle +").button_up.emit()
    var stepped: float = solver.aero_state(0)["throttle"]
    pad.button("Full throttle").pressed.emit()
    var full: float = solver.aero_state(0)["throttle"]
    # The autopilot's panel: HDG on and lit, HDG + steps the heading by one.
    pad.button("HDG").pressed.emit()
    pad.button("HDG +").pressed.emit()
    pad._process(FRAME)
    var ap: Dictionary = solver.autopilot("state")
    var lit: bool = pad.button("HDG").modulate == AirplanePad.LIT and pad.button("WLV").modulate != AirplanePad.LIT
    pad.free()
    if ap["heading_mode"] != "hdg" or ap["heading"] != 1 or not lit:
        return fail("HDG and HDG + left the autopilot at %s, HDG lit alone %s" % [ap, lit])
    if absf(stepped - start - 0.05) > 1e-6 or full != 1.0:
        return fail("Throttle + took the throttle %.3f to %.3f, Full throttle to %.3f" % [start, stepped, full])
    return ok("held roll and brake, flaps stepped, parking brake, throttle stepped %.2f and full %.2f" % [stepped, full], 0)
