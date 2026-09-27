class_name PlayRig
extends Node
## Interactive controls for a human session.
##
## Automated gates catch regressions; they do not say whether something looks right.
## This is what a person is handed: a free camera, a live readout, and one key per
## effect so that "this effect is wrong" can be told apart from "this scene is wrong"
## without a rebuild.

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
var _drive: PlayDrive = null
var _view: PlayCamera = PlayCamera.new()
var _menu: PlayMenu
var _terrain: Node3D = null
var _terrain_pending: bool = false


## `vehicle` is a VehicleBuilder result, or empty when no vehicle was loaded. With one, the
## solver runs and the window is a driving session rather than a camera fly-through.
func setup(camera: Camera3D, world: Node3D, weather: String, vehicle: Dictionary = {}) -> void:
    _camera = camera
    _view.setup(camera)
    _world = world
    _yaw = camera.rotation.y
    _pitch = camera.rotation.x
    for key: String in WeatherCfg.PRESETS.keys():
        _weather_names.append(key)
    _weather_index = maxi(0, _weather_names.find(weather))
    _hud = _build_hud()
    if not vehicle.is_empty():
        var drive: PlayDrive = PlayDrive.new()
        var error: String = drive.setup(vehicle)
        if error != "":
            printerr("PLAY  the vehicle cannot be driven: " + error)
        else:
            _drive = drive
            _view.set_mode(PlayCamera.Mode.CHASE)
    _menu = _build_menu(weather)
    _build_terrain()
    _print_help()


## Adds the world, when this session asked for one and Terrain3D is installed. It cannot be
## populated yet: a Terrain3D has no data until it has been inside a World3D for a frame.
##
## Which world: the flat test park by default, Valley One under `--valley`, and a shipped Rigs of
## Rods terrain under `--terrain-dir`. The park is where a person goes to try something — ramps,
## rocks, surfaces and walls within a few seconds of each other — the valley is the showcase the
## plan is measured in, and a loaded terrain is a place someone else built and drove.
func _build_terrain() -> void:
    if not Harness.args.has_flag("terrain"):
        return
    _terrain = ValleyTerrain.create()
    if _terrain == null:
        printerr("PLAY  --terrain asked for, but Terrain3D is not installed."
            + " Run tools/build_terrain3d.sh")
        return
    _world.add_child(_terrain)
    _terrain_pending = true


func _populate_terrain() -> void:
    _terrain_pending = false
    var loaded: RorTerrain = _load_terrain()
    var valley: bool = Harness.args.has_flag("valley")
    var shape: Object = loaded if loaded != null else (ValleyShape if valley else ParkShape)
    var error: String = ValleyTerrain.populate(_terrain, shape)
    if error != "":
        printerr("PLAY  the terrain could not be built: " + error)
        return
    # The flat plane would otherwise sit inside the generated ground and the rig would rest on
    # whichever happened to be higher.
    var ground: MeshInstance3D = _world.get_node_or_null(^"Ground") as MeshInstance3D
    if ground != null:
        ground.visible = false
    # A loaded terrain brings its own furniture in its object files, which is separate work; the
    # generated worlds' furniture is built here.
    if loaded == null:
        if valley:
            _build_valley()
        else:
            _world.add_child(ParkProps.build())
            _world.add_child(ParkGrid.build())
    if _drive == null:
        return
    # Where a vehicle starts, and under what gravity, before the terrain is handed over: taking
    # the terrain puts the rig down, and it has to be put down where the terrain says.
    if loaded != null:
        _drive.spawn = loaded.start_position()
        _drive.solver.set_gravity(Vector3(0.0, loaded.gravity(), 0.0))
    error = _drive.use_terrain(_terrain.get("data"))
    if error != "":
        printerr("PLAY  the solver could not take the terrain: " + error)
        return
    if loaded != null:
        print("PLAY  driving on %s, spawned at %v under %.2f m/s^2" % [
            loaded.name, loaded.start_position(), loaded.gravity()])
        return
    if not valley:
        var props: int = ParkProps.apply_to_solver(_drive.solver)
        print("PLAY  driving in the test park: %d props are solid" % props)
        return
    print("PLAY  driving on the valley")


## The terrain `--terrain-dir` asks for, or null when this session asked for a generated world.
## A terrain that will not load is reported and the session falls back rather than opening a
## window onto nothing.
func _load_terrain() -> RorTerrain:
    var directory: String = Harness.args.get_string("terrain-dir", "")
    if directory.is_empty():
        return null
    var loaded: Dictionary = RorTerrain.load_from(
        SourceScan.repo_root().path_join(directory)
    )
    if (loaded["error"] as String) != "":
        printerr("PLAY  the terrain at %s could not be read: %s" % [
            directory, loaded["error"]])
        return null
    return loaded["terrain"] as RorTerrain


## The valley's own furniture: the tunnel, the water and the forest.
func _build_valley() -> void:
    _world.add_child(Tunnel.build())
    var water: Node3D = ValleyWater.build()
    if water != null:
        _world.add_child(water)
    var vegetation: Node3D = ValleyVegetation.build()
    if vegetation != null:
        _world.add_child(vegetation)


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
            + "PLAY  M open the environment panel: weather, gravity, sun, fog\n"
            + "PLAY  P save a screenshot to artifacts/human"
        )
    )
    if _drive != null:
        print(DriveCfg.HELP)


func _process(delta: float) -> void:
    if _terrain_pending and _frames > 1:
        _populate_terrain()
    if _drive != null:
        _drive.step(delta)
        _view.follow(_drive, delta)
    if _view.mode == PlayCamera.Mode.FREE:
        _view.fly(delta)
    _frames += 1
    if _hud.visible and _frames % HUD_REFRESH_FRAMES == 0:
        _hud.text = _hud_text()


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
        _view.look((event as InputEventMouseMotion).relative)
    elif event is InputEventKey and (event as InputEventKey).pressed:
        _on_key((event as InputEventKey).keycode)


func _on_key(keycode: Key) -> void:
    if _drive != null and _drive.on_key(keycode):
        return
    match keycode:
        KEY_M:
            if _menu != null:
                _menu.toggle()
                print("PLAY  environment panel %s" % ("open" if _menu.is_open() else "closed"))
        KEY_F5:
            _view.set_mode(PlayCamera.Mode.CHASE if _drive != null else PlayCamera.Mode.FREE)
            print("PLAY  chase camera %s" % ("on" if _drive != null else "unavailable"))
        KEY_F7:
            _view.set_mode(PlayCamera.Mode.CAB if _drive != null else PlayCamera.Mode.FREE)
            print("PLAY  driver's seat %s" % ("on" if _drive != null else "unavailable"))
        KEY_F6:
            _view.set_mode(PlayCamera.Mode.FREE)
            print("PLAY  free camera")
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
    _apply_weather(_weather_names[_weather_index])


## Puts one weather preset on the live scene. Shared by F2 and by the environment panel, so the
## two cannot drift into applying a preset differently.
func _apply_weather(name: String) -> void:
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
            _footer(),
        ]
    )


func _footer() -> String:
    var keys: String = (
        "click to look  WASD move  Q/E down/up  Shift boost  F1 hud  F2 weather"
        + "  F3 shadows  F4 sun  P shot  Esc release/quit"
    )
    if _drive == null:
        return keys
    return _drive.hud_line() + "\n" + keys + "  F5/F6 chase/free"


## The environment panel, built once the vehicle exists so that gravity has a solver to go to.
func _build_menu(weather: String) -> PlayMenu:
    var holder: WorldEnvironment = _world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    if holder == null:
        return null
    var menu: PlayMenu = PlayMenu.new()
    menu.name = "EnvironmentMenu"
    add_child(menu)
    menu.setup(
        holder.environment,
        _world.get_node_or_null(^"Sun") as DirectionalLight3D,
        _drive,
        weather,
        func(name: String) -> void: _apply_weather(name)
    )
    return menu
