class_name PlayRig
extends Node
## Interactive controls for a human session.
##
## Automated gates catch regressions; they do not say whether something looks right.
## This is what a person is handed: a free camera, a live readout, and one key per
## effect so that "this effect is wrong" can be told apart from "this scene is wrong"
## without a rebuild.

const MOVE_SPEED: float = 8.0
const BOOST_MULTIPLIER: float = 4.0
const MOUSE_SENSITIVITY: float = 0.0025
const PITCH_LIMIT: float = 1.5
const HUD_MARGIN: int = 12
const HUD_FONT_SIZE: int = 15
const HUD_REFRESH_FRAMES: int = 10

var _camera: Camera3D
var _world: Node3D
var _hud: Label
var _weather_names: Array[String] = []
var _weather_index: int = 0
var _looking: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _frames: int = 0
var _shots: int = 0


func setup(camera: Camera3D, world: Node3D, weather: String) -> void:
    _camera = camera
    _world = world
    _yaw = camera.rotation.y
    _pitch = camera.rotation.x
    for key: String in WeatherCfg.PRESETS.keys():
        _weather_names.append(key)
    _weather_index = maxi(0, _weather_names.find(weather))
    _hud = _build_hud()
    _print_help()


func _build_hud() -> Label:
    var layer: CanvasLayer = CanvasLayer.new()
    layer.name = "HUD"
    var label: Label = Label.new()
    label.name = "HudText"
    label.position = Vector2(HUD_MARGIN, HUD_MARGIN)
    label.add_theme_font_size_override("font_size", HUD_FONT_SIZE)
    label.add_theme_color_override("font_shadow_color", Color.BLACK)
    label.add_theme_constant_override("shadow_offset_x", 1)
    label.add_theme_constant_override("shadow_offset_y", 1)
    layer.add_child(label)
    add_child(layer)
    return label


func _print_help() -> void:
    print(
        (
            "PLAY  click to look with the mouse, Esc to release it, Esc again to quit\n"
            + "PLAY  W A S D move, Q/E down/up, hold Shift to boost\n"
            + "PLAY  F1 toggle HUD, F2 cycle weather, F3 toggle shadows, F4 toggle the sun\n"
            + "PLAY  P save a screenshot to artifacts/human"
        )
    )


func _process(delta: float) -> void:
    _move(delta)
    _frames += 1
    if _hud.visible and _frames % HUD_REFRESH_FRAMES == 0:
        _hud.text = _hud_text()


func _move(delta: float) -> void:
    var direction: Vector3 = Vector3(
        Input.get_axis(&"ui_left", &"ui_right"), 0.0, Input.get_axis(&"ui_up", &"ui_down")
    )
    if Input.is_key_pressed(KEY_D):
        direction.x += 1.0
    if Input.is_key_pressed(KEY_A):
        direction.x -= 1.0
    if Input.is_key_pressed(KEY_S):
        direction.z += 1.0
    if Input.is_key_pressed(KEY_W):
        direction.z -= 1.0
    if Input.is_key_pressed(KEY_E):
        direction.y += 1.0
    if Input.is_key_pressed(KEY_Q):
        direction.y -= 1.0
    if direction == Vector3.ZERO:
        return
    var speed: float = MOVE_SPEED
    if Input.is_key_pressed(KEY_SHIFT):
        speed *= BOOST_MULTIPLIER
    _camera.translate(direction.normalized() * speed * delta)


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var button: InputEventMouseButton = event as InputEventMouseButton
        if not button.pressed:
            return
        # Click anywhere to take the mouse and look freely; Esc gives it back. Holding
        # the right button still works for a quick glance without committing.
        if button.button_index == MOUSE_BUTTON_LEFT:
            _set_looking(true)
        elif button.button_index == MOUSE_BUTTON_RIGHT:
            _set_looking(not _looking)
    elif event is InputEventMouseMotion and _looking:
        var motion: InputEventMouseMotion = event as InputEventMouseMotion
        _yaw -= motion.relative.x * MOUSE_SENSITIVITY
        _pitch = clampf(_pitch - motion.relative.y * MOUSE_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
        _camera.rotation = Vector3(_pitch, _yaw, 0.0)
    elif event is InputEventKey and (event as InputEventKey).pressed:
        _on_key((event as InputEventKey).keycode)


func _on_key(keycode: Key) -> void:
    match keycode:
        KEY_F1:
            _hud.visible = not _hud.visible
        KEY_F2:
            _cycle_weather()
        KEY_F3:
            var sun: DirectionalLight3D = _world.get_node_or_null(^"Sun") as DirectionalLight3D
            if sun != null:
                sun.shadow_enabled = not sun.shadow_enabled
                print("PLAY  shadows %s" % ("on" if sun.shadow_enabled else "off"))
        KEY_F4:
            var light: DirectionalLight3D = _world.get_node_or_null(^"Sun") as DirectionalLight3D
            if light != null:
                light.visible = not light.visible
                print("PLAY  sun %s" % ("on" if light.visible else "off"))
        KEY_P:
            _screenshot()
        KEY_ESCAPE:
            # First Esc releases the mouse, so the window can be left without quitting.
            # A second one quits.
            if _looking:
                _set_looking(false)
            else:
                get_tree().quit(0)


func _set_looking(looking: bool) -> void:
    _looking = looking
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE


func _cycle_weather() -> void:
    _weather_index = (_weather_index + 1) % _weather_names.size()
    var name: String = _weather_names[_weather_index]
    var preset: Dictionary = WeatherCfg.get_preset(name)
    var sun: DirectionalLight3D = _world.get_node_or_null(^"Sun") as DirectionalLight3D
    var env: WorldEnvironment = _world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    if sun != null:
        var toward_sun: Vector3 = (preset.get("sun_from", Vector3.UP) as Vector3).normalized()
        sun.look_at_from_position(sun.position, sun.position - toward_sun, Vector3.UP)
        sun.light_energy = float(preset["sun_energy"])
        sun.light_color = preset["sun_color"] as Color
    if env != null:
        env.environment.background_color = preset["bg_color"] as Color
        env.environment.ambient_light_color = preset["bg_color"] as Color
        env.environment.ambient_light_energy = float(preset["ambient_energy"])
    print("PLAY  weather %s" % name)


func _screenshot() -> void:
    var path: String = HarnessCapture.resolve_dir("human").path_join(
        "play-%d.png" % _shots
    )
    var error: String = HarnessCapture.capture_png(get_viewport(), path)
    if error != "":
        printerr("PLAY  screenshot failed: " + error)
        return
    _shots += 1
    print("PLAY  wrote " + path)


func _hud_text() -> String:
    var viewport_rid: RID = get_viewport().get_viewport_rid()
    return (
        "%s | %s | %s\n%.1f fps  %.2f ms\ndraw calls %d  primitives %d\nvideo %.0f MB  texture %.0f MB\n%s"
        % [
            RenderingServer.get_video_adapter_name(),
            RenderingServer.get_current_rendering_driver_name(),
            _weather_names[_weather_index],
            Performance.get_monitor(Performance.TIME_FPS),
            Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
            RenderingServer.viewport_get_render_info(
                viewport_rid,
                RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
                RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
            ),
            RenderingServer.viewport_get_render_info(
                viewport_rid,
                RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
                RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME
            ),
            Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
            Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
            "click to look  WASD move  Q/E down/up  Shift boost  F1 hud  F2 weather"
            + "  F3 shadows  F4 sun  P shot  Esc release/quit",
        ]
    )
