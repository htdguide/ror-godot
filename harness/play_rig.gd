class_name PlayRig
extends Node
## Interactive controls for a human session.
##
## Automated gates catch regressions; they do not say whether something looks right. This is what
## a person is handed: a free camera, a live readout, and one key per effect, so that "this effect
## is wrong" can be told apart from "this scene is wrong" without a rebuild.

## The map a session opens when it names none: the one Rigs of Rods itself ships, which is in
## the tree under GPL and therefore present on any clone.

const HUD_REFRESH_FRAMES: int = 10

var _camera: Camera3D
var _world: Node3D
var _hud: Label
## What is loaded now, so the menu can mark it and a map change knows what to rebuild.
var _vehicle_name: String = ""
var _weather: PlayWeather
var _looking: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _frames: int = 0
var _shots: int = 0
var _drive: PlayDrive = null
var _view: PlayCamera = PlayCamera.new()
var _menu: PlayMenu
## The map: its terrain, its scenery, the screen that covers a change. See `PlayMap`.
var _map: PlayMap = PlayMap.new()
## The graphics options, applied at start and whenever moved, and the menu the game opens to
## when nothing on the command line said what to drive or where.
var _graphics: GraphicsSettings = GraphicsSettings.new()
var _main_menu: MainMenu = null
## What the terrain is solid as: the F8 overlay, and where a vehicle may stand.
var _solid: PlaySolid = PlaySolid.new()


## `vehicle` is a VehicleBuilder result, or empty when no vehicle was loaded. With one, the
## solver runs and the window is a driving session rather than a camera fly-through.
func setup(camera: Camera3D, world: Node3D, weather: String, vehicle: Dictionary = {}) -> void:
    _camera = camera
    _view.setup(camera)
    _world = world
    _yaw = camera.rotation.y
    _pitch = camera.rotation.x
    _weather = PlayWeather.new(
        weather, camera, CameraCfg.get_preset(Harness.args.get_string("shot", "diag_origin"))
    )
    _map.name = Harness.args.get_string("terrain-dir", BuildProfile.default_map())
    DisplayServer.window_set_title("ror-godot [%s]" % BuildProfile.label())
    _hud = PlayHud.build(self)
    if not vehicle.is_empty():
        # `--vehicle <dir>:<file>` is how a session names one; the library keys on the basename.
        _vehicle_name = Harness.args.get_string("vehicle", "").get_slice(":", 1).get_basename()
        var drive: PlayDrive = PlayDrive.new()
        var error: String = drive.setup(vehicle)
        if error != "":
            printerr("PLAY  the vehicle cannot be driven: " + error)
        else:
            _drive = drive
            _view.set_mode(PlayCamera.Mode.CHASE)
    _menu = _build_menu(weather)
    # And the weather moves in a window, where nothing is comparing two frames.
    var holder: WorldEnvironment = _world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    if holder != null:
        SkyClouds.set_parameter(
            holder.environment, "wind_speed", RenderCfg.CLOUD_WIND_SPEED_PLAYING
        )
    var screen: PlayLoading = PlayLoading.new()
    add_child(screen)
    _map.setup(self, _world, _menu, _solid, _weather, weather, screen)
    _map.drive = _drive
    _graphics.load_from()
    _graphics.apply(get_viewport(), _world)
    _weather.after_put = func() -> void: _graphics.apply(get_viewport(), _world, _map.vegetation)
    # Nothing named on the command line: the game opens on its menu rather than on a world.
    if not Harness.args.values.has("vehicle") and not Harness.args.values.has("terrain-dir"):
        _map.name = ""
        _main_menu = MainMenu.new()
        add_child(_main_menu)
        _main_menu.setup(_graphics, _start_game, func() -> void: get_tree().quit(0),
            func() -> void: _graphics.apply(get_viewport(), _world, _map.vegetation))
        _main_menu.open()
    _map.build()
    PlayHud.print_help(_drive)


## The main menu's three choices, made: the vehicle, then the map under the chosen weather.
func _start_game(choice: Dictionary) -> void:
    _change_vehicle(choice["vehicle"] as String)
    _map.set_opening_weather(choice["weather"] as String)
    _change_map(choice["map"] as String)
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
    if _map.pending and _frames > 1:
        _map.populate()
    # Step posted first, vehicle posed last, same frame. See `PlayDrive.begin`.
    if _drive != null:
        _drive.begin(delta)
    if _map.vegetation != null:
        _map.vegetation.focus_on(_camera.global_position)
    if _view.mode == PlayCamera.Mode.FREE:
        _view.fly(delta)
    if _drive != null:
        _drive.finish()
        _view.follow(_drive, delta)
    _frames += 1
    if _hud.visible and _frames % HUD_REFRESH_FRAMES == 0:
        _hud.text = PlayHud.text(
            get_viewport(), _weather.current(), PlayHud.footer(_drive)
        )


func _unhandled_input(event: InputEvent) -> void:
    # The main menu owns the window while it is up: no look, no keys, no in-game panel.
    if _main_menu != null and _main_menu.is_open():
        return
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
                print("PLAY  settings %s" % ("open" if _menu.is_open() else "closed"))
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
            _weather.cycle(_world)
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
        KEY_F8:
            print("PLAY  " + _solid.show_boxes(_world, not _solid.shown()))
        KEY_P:
            _screenshot()
        KEY_ESCAPE:
            # First Esc gives the mouse back, because a panel nobody can click is no panel.
            # After that it opens and closes the settings, and quitting is a button in there:
            # a session that ends because somebody pressed Escape twice is a session lost.
            if _looking:
                _set_looking(false)
            elif _menu != null:
                _menu.toggle()
                print("PLAY  settings %s" % ("open" if _menu.is_open() else "closed"))
            else:
                get_tree().quit(0)


func _set_looking(looking: bool) -> void:
    _looking = looking
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE


func _screenshot() -> void:
    # Named by the clock, not by a counter that restarts with the session.
    #
    # `play-0.png` was overwritten by every new window, so a screenshot taken to report a bug was
    # destroyed by the next session opened to look at it — which happened: three shots of a
    # reported fault came back as one, and the other two were from hours earlier.
    var stamp: String = Time.get_datetime_string_from_system(false, false).replace(":", "")
    var path: String = HarnessCapture.resolve_dir("human").path_join(
        "play-%s-%d.png" % [stamp.replace("T", "-"), _shots]
    )
    # The HUD stays out of the picture: what it says is in the sidecar, and a picture meant for a
    # loading screen or a bug report is the scene, not the readout over it.
    var shown: bool = _hud.visible
    _hud.visible = false
    await RenderingServer.frame_post_draw
    await RenderingServer.frame_post_draw
    # A picture of a fault is handed over to be acted on, and a picture alone does not say which
    # of a map's hundreds of objects the untextured thing in the middle of it is. `PlayShot`
    # writes that down beside it.
    var error: String = PlayShot.save(path, {
        "viewport": get_viewport(),
        "camera": _camera,
        "world": _world,
        "terrain": _map.loaded,
        "map": _map.name,
        "vehicle": _vehicle_name,
        "weather": _weather.current(),
        "mode": PlayCamera.Mode.keys()[_view.mode],
        "drive": _drive,
    })
    _hud.visible = shown
    if error != "":
        printerr("PLAY  screenshot failed: " + error)
        return
    _shots += 1
    print("PLAY  wrote %s and %s" % [path, path.get_basename() + ".json"])


## The settings panel, built once the vehicle exists so that gravity has a solver to go to.
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
        _camera,
        weather,
        func(name: String) -> void: _weather.apply(_world, name),
        func(hour: float) -> void: _weather.set_hour(_world, hour),
        func(key: String, value: float) -> void: _weather.set_override(_world, key, value),
        func() -> void: get_tree().quit(0),
        func(name: String) -> void: _change_map(name),
        func(name: String) -> void: _change_vehicle(name),
        func() -> Dictionary: return _weather.state()
    )
    menu.set_loaded(_map.name, _vehicle_name)
    return menu


## Puts another vehicle on the map, where this one is standing.
##
## The map stays: a session changing cars is comparing them on the same ground. The new vehicle
## takes over the old one's place and heading, and **that place becomes its spawn**, so the reset
## key puts it back here rather than at the map's start.
func _change_vehicle(name: String) -> void:
    var entry: Dictionary = RorVehicleLibrary.find(name)
    if entry.is_empty():
        printerr("PLAY  no vehicle named " + name)
        return
    var built: Dictionary = VehicleBuilder.build(
        entry["directory"] as String, entry["file"] as String
    )
    if (built.get("error", "") as String) != "":
        printerr("PLAY  %s cannot be built: %s" % [name, built["error"]])
        return

    # Where the old one was, before anything is taken apart. With no vehicle yet, the terrain's
    # own start is the only place there is.
    var at: Vector3 = _drive.spawn if _drive != null else Vector3.ZERO
    var heading: float = _drive.spawn_heading if _drive != null else 0.0
    if _drive != null:
        at = ActorFrame.of(_drive.solver.get_positions(), _drive.truck.camera_nodes).origin
        heading = RigBuilder.heading_of(
            _drive.solver.get_positions(), _drive.truck.camera_nodes
        )
        var old_root: Node3D = _drive.vehicle_root()
        if old_root != null and is_instance_valid(old_root):
            _world.remove_child(old_root)
            old_root.queue_free()

    var drive: PlayDrive = PlayDrive.new()
    _world.add_child(built["root"] as Node3D)
    var error: String = drive.setup(built)
    if error != "":
        printerr("PLAY  %s cannot be driven: %s" % [name, error])
        return
    _drive = drive
    _map.drive = drive
    _drive.spawn = at
    _drive.spawn_heading = heading
    _vehicle_name = name
    _view.set_mode(PlayCamera.Mode.CHASE)
    if _map.terrain != null and _map.terrain.get("data") != null:
        error = _drive.use_terrain(_map.terrain.get("data"))
        if error != "":
            printerr("PLAY  the terrain could not be handed to %s: %s" % [name, error])
        # A new vehicle is a new solver and the objects went to the old one, so every car taken
        # after the first used to drive through every pole, wall and road slab on the map.
        RorObjectCollision.apply(_map.terrain.get("data") as RorTerrain, _drive.solver)
    else:
        _drive.respawn()
    if _menu != null:
        _menu.set_loaded(_map.name, _vehicle_name)
    print("PLAY  driving %s" % name)


## Puts another map up. The map holder does the work; the session only tells the panel.
func _change_map(name: String) -> void:
    _map.change(name)
    if _menu != null:
        _menu.set_loaded(_map.name, _vehicle_name)
