class_name PlayRig
extends Node
## Interactive controls for a human session.
##
## Automated gates catch regressions; they do not say whether something looks right.
## This is what a person is handed: a free camera, a live readout, and one key per
## effect so that "this effect is wrong" can be told apart from "this scene is wrong"
## without a rebuild.

## The map a session opens when it names none: the one Rigs of Rods itself ships, which is in
## the tree under GPL and therefore present on any clone.
const DEFAULT_MAP: String = "simple2"

const HUD_REFRESH_FRAMES: int = 10

var _camera: Camera3D
var _world: Node3D
var _hud: Label
## What is loaded now, so the menu can mark it and a map change knows what to rebuild.
var _map_name: String = ""
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
var _terrain: Node3D = null
var _terrain_pending: bool = false
## The terrain's own files, kept after the scene is built: a screenshot's sidecar reports the
## ground height and surface under the camera, and only the loaded terrain knows them.
var _loaded: RorTerrain = null
var _vegetation: RorVegetation = null


## `vehicle` is a VehicleBuilder result, or empty when no vehicle was loaded. With one, the
## solver runs and the window is a driving session rather than a camera fly-through.
func setup(camera: Camera3D, world: Node3D, weather: String, vehicle: Dictionary = {}) -> void:
    _camera = camera
    _view.setup(camera)
    _world = world
    _yaw = camera.rotation.y
    _pitch = camera.rotation.x
    _weather = PlayWeather.new(weather)
    _map_name = Harness.args.get_string("terrain-dir", DEFAULT_MAP)
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
    # A loaded terrain is 4 km across and its own horizon stands at the edge of it.
    camera.far = RenderCfg.VIEW_DISTANCE_M
    # And the weather moves in a window, where nothing is comparing two frames.
    var holder: WorldEnvironment = _world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    if holder != null:
        SkyClouds.set_parameter(
            holder.environment, "wind_speed", RenderCfg.CLOUD_WIND_SPEED_PLAYING
        )
    _build_terrain()
    PlayHud.print_help(_drive)


## Adds the world, when this session asked for one and Terrain3D is installed. It cannot be
## populated yet: a Terrain3D has no data until it has been inside a World3D for a frame.
##
## Which world is always a Rigs of Rods terrain — `--map <name>`, defaulting to the map the game
## itself ships. This project used to generate two worlds of its own and they are gone: a place
## someone else built and drove is the only world worth checking a reader against.
func _build_terrain() -> void:
    if not Harness.args.has_flag("terrain"):
        return
    _terrain = TerrainWorld.create()
    if _terrain == null:
        printerr("PLAY  --terrain asked for, but Terrain3D is not installed."
            + " Run tools/build_terrain3d.sh")
        return
    _world.add_child(_terrain)
    _terrain_pending = true


func _populate_terrain() -> void:
    _terrain_pending = false
    var loaded: RorTerrain = _load_terrain()
    if loaded == null:
        return
    _loaded = loaded
    var error: String = Harness.terrain.populate(_terrain, loaded)
    if error != "":
        printerr("PLAY  the terrain could not be built: " + error)
        return
    # The blockout plane would otherwise sit inside the terrain and the rig would rest on
    # whichever happened to be higher.
    var ground: MeshInstance3D = _world.get_node_or_null(^"Ground") as MeshInstance3D
    if ground != null:
        ground.visible = false
    _world.add_child(RorObjects.build(loaded))
    # The roads the terrain draws from a line of points rather than from placed objects. Port
    # Starling describes most of its network that way.
    _world.add_child(RorProceduralRoad.build(loaded))
    _grow_vegetation(loaded)
    if _drive == null:
        return
    # Where a vehicle starts, and under what gravity, before the terrain is handed over: taking
    # the terrain puts the rig down, and it has to be put down where the terrain says.
    _drive.spawn = loaded.start_position()
    _drive.solver.set_gravity(Vector3(0.0, loaded.gravity(), 0.0))
    error = _drive.use_terrain(_terrain.get("data"))
    if error != "":
        printerr("PLAY  the solver could not take the terrain: " + error)
        return
    var solid: int = RorObjectCollision.apply(loaded, _drive.solver)
    print("PLAY  driving on %s, spawned at %v under %.2f m/s^2; %d parts of its own"
        % [loaded.name, loaded.start_position(), loaded.gravity(), solid]
        + " scenery are solid")


## The terrain's own vegetation, in a ring of tiles that follows whoever is driving.
func _grow_vegetation(loaded: RorTerrain) -> void:
    var vegetation: RorVegetation = RorVegetation.new()
    var grown: String = vegetation.setup(loaded)
    if grown != "":
        vegetation.free()
        return
    _world.add_child(vegetation)
    vegetation.focus_on(loaded.start_position())
    _vegetation = vegetation
    if _menu != null:
        _menu.set_vegetation(vegetation)


## The terrain `--map` asks for, or upstream's own shipped default map when this session named
## none. Null when it cannot be loaded.
##
## The name is a library name — a `.terrn2` under `assets/terrains/` or in upstream's own shipped
## content — or a path to a directory holding one. A terrain that will not load is reported and
## the library is listed, rather than opening a window onto nothing.
func _load_terrain() -> RorTerrain:
    # The map the menu last asked for, or the one the command line named.
    var wanted: String = _map_name
    var loaded: Dictionary = RorTerrainLibrary.load_named(wanted)
    if (loaded["error"] as String) != "":
        printerr("PLAY  %s" % loaded["error"])
        for summary: Dictionary in RorTerrainLibrary.summaries():
            printerr("PLAY    %s (%s)" % [summary["name"], summary["title"]])
        return null
    return loaded["terrain"] as RorTerrain


func _process(delta: float) -> void:
    if _terrain_pending and _frames > 1:
        _populate_terrain()
    if _drive != null:
        _drive.step(delta)
        _view.follow(_drive, delta)
    if _vegetation != null:
        _vegetation.focus_on(_camera.global_position)
    if _view.mode == PlayCamera.Mode.FREE:
        _view.fly(delta)
    _frames += 1
    if _hud.visible and _frames % HUD_REFRESH_FRAMES == 0:
        _hud.text = PlayHud.text(
            get_viewport(), _weather.current(), PlayHud.footer(_drive)
        )


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
    # A picture of a fault is handed over to be acted on, and a picture alone does not say which
    # of a map's hundreds of objects the untextured thing in the middle of it is. `PlayShot`
    # writes that down beside it.
    var error: String = PlayShot.save(path, {
        "viewport": get_viewport(),
        "camera": _camera,
        "world": _world,
        "terrain": _loaded,
        "map": _map_name,
        "vehicle": _vehicle_name,
        "weather": _weather.current(),
        "mode": PlayCamera.Mode.keys()[_view.mode],
        "drive": _drive,
    })
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
        func() -> void: get_tree().quit(0),
        func(name: String) -> void: _change_map(name),
        func(name: String) -> void: _change_vehicle(name)
    )
    menu.set_loaded(_map_name, _vehicle_name)
    return menu


## Puts another vehicle on the map, where this one is standing.
##
## The map stays: a session changing cars is comparing them on the same ground, and reloading a
## terrain to do it would cost seconds and lose where the person was standing. The new vehicle
## takes over the old one's place and heading, and **that place becomes its spawn**, so the reset
## key puts it back here rather than at the map's start — which is what a person means when they
## pick a car at the top of a hill.
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
    _drive.spawn = at
    _drive.spawn_heading = heading
    _vehicle_name = name
    _view.set_mode(PlayCamera.Mode.CHASE)
    if _terrain != null and _terrain.get("data") != null:
        error = _drive.use_terrain(_terrain.get("data"))
        if error != "":
            printerr("PLAY  the terrain could not be handed to %s: %s" % [name, error])
    else:
        _drive.respawn()
    if _menu != null:
        _menu.set_loaded(_map_name, _vehicle_name)
    print("PLAY  driving %s" % name)


## Loads another map, keeping the vehicle. The terrain, its scenery and its grass all go.
func _change_map(name: String) -> void:
    if name == _map_name:
        return
    _map_name = name
    for child: Node in _world.get_children():
        if (
            child.name.begins_with("RorObjects")
            or child.name.begins_with("RorProceduralRoads")
            or child == _terrain
        ):
            _world.remove_child(child)
            child.queue_free()
    if _vegetation != null:
        _vegetation.clear()
        _vegetation = null
    _terrain = null
    _loaded = null
    _build_terrain()
    if _menu != null:
        _menu.set_loaded(_map_name, _vehicle_name)
    print("PLAY  loading %s" % name)
