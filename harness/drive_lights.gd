class_name DriveLights
extends RefCounted
## A driven vehicle's lights: its `LightState`, the keys that work its switches, and the lamps shown
## every frame. Upstream's keys where this window can have them: N the low beams (Ctrl+N cycles
## side, low and main), K the main beam, F the fog lights, Z/C the indicators (the same again
## cancels), X off, minus the hazards, Ctrl+1 to Ctrl+0 the user lights.

var state: LightState
var _seconds: float = -1.0


func _init(truck: TruckParser) -> void:
    state = LightState.of(truck)


## Handles `action` (a `DriveKeys` action) or a Ctrl+digit; true when it was a light key.
func on_key(action: String, keycode: Key, truck: TruckParser) -> bool:
    var ctrl: bool = Input.is_key_pressed(KEY_CTRL)
    if ctrl and keycode >= KEY_0 and keycode <= KEY_9:
        var number: int = 9 if keycode == KEY_0 else int(keycode - KEY_1)
        state.toggle_custom(number)
        print("DRIVE  light %d %s" % [number + 1, "on" if state.custom[number] else "off"])
        return true
    match action:
        "lights":
            if ctrl:
                state.cycle(truck)
            else:
                state.toggle_low_beams()
            print("DRIVE  lights %s" % ("on" if state.headlights else "off"))
        "main_beam":
            state.high_beams = not state.high_beams
            print("DRIVE  main beam %s" % ("on" if state.high_beams else "off"))
        "fog_lights":
            state.fog_lights = not state.fog_lights
            print("DRIVE  fog lights %s" % ("on" if state.fog_lights else "off"))
        "indicator_left":
            state.toggle_blink(LightState.Blink.LEFT)
        "indicator_right":
            state.toggle_blink(LightState.Blink.RIGHT)
        "hazards":
            state.toggle_blink(LightState.Blink.WARN)
        "indicators_off":
            state.blink = LightState.Blink.NONE
        _:
            return false
    return true


func set_headlights(on: bool) -> void:
    if state.headlights != on:
        state.toggle_low_beams()


## Shows the lamps for the controls as they stand, `seconds` being the window's clock.
## `engine` is the frame's snapshot: {"contact", "running", "rpm"}.
func apply(lamps: Array[Node3D], truck: TruckParser, seconds: float, brake: float, parking: bool, gear: int,
        engine: Dictionary = {}) -> void:
    var dt: float = 0.0 if _seconds < 0.0 else maxf(seconds - _seconds, 0.0)
    _seconds = seconds
    state.follow_controls(brake, parking, gear)
    state.follow_engine(bool(engine.get("contact", false)), bool(engine.get("running", false)),
            float(engine.get("rpm", 0.0)))
    var camera: Variant = null
    if not lamps.is_empty() and lamps[0].is_inside_tree() and lamps[0].get_viewport().get_camera_3d() != null:
        camera = lamps[0].get_viewport().get_camera_3d().global_position
    FlareBuilder.apply_lights(lamps, truck, state, state.update(dt), camera)
