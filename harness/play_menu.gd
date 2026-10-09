class_name PlayMenu
extends CanvasLayer
## The pause panel: what to drive, where to drive it, and everything about the world, in one
## place, opened with Esc.
##
## Three tabs, because they are three different questions. **Drive** is the vehicle list, **World**
## is the map list, and **Settings** is everything about the scene a session can retune. The
## content tabs are built by `ContentBrowser` from what is actually on the disk; this file owns
## the panel they sit in and nothing about what is in them.
##
## Weather, gravity, the sun, the sky, how far you can see, the fog that closes it, the grass, the
## vehicle's lamps. Everything here changes the world the vehicle is in rather than the vehicle
## itself, which is the line: a panel that could also retune the rig would make a session's
## findings unreproducible, and a rig's numbers belong in its own file. The lamp switch is the one
## exception, and it is a switch a driver has anyway.
##
## It writes to the live scene, not to the config files. A setting changed here lasts as long as
## the window does, and the next session starts from what the project says again — so an
## experiment can be wild without anybody having to remember to put it back.

## Gravity, in m/s². The Moon, Mars and Earth are there because they are the three a person
## actually reaches for, and the slider goes further either way.
const EARTH_GRAVITY: float = -9.81
const GRAVITY_MIN: float = -30.0
const GRAVITY_MAX: float = 0.0
const GRAVITY_PRESETS: Dictionary = {
    "Earth": -9.81,
    "Mars": -3.72,
    "Moon": -1.62,
    "Heavy": -20.0,
}
## How far a session may push the view, and how thick the haze may get.
const PANEL_WIDTH: int = 380
const PANEL_MAX_HEIGHT: int = 720


var _panel: PanelContainer
var _rows: VBoxContainer
var _vehicle_rows: VBoxContainer = null
var _map_rows: VBoxContainer = null
var _environment: Environment
var _sun: DirectionalLight3D
var _drive: PlayDrive
var _camera: Camera3D
var _vegetation: RorVegetation = null
var _weather_names: PackedStringArray = PackedStringArray()
var _weather_index: int = 0
var _on_weather: Callable
## Called with a clock hour when the day is dragged. The sky, the sun, the stars and the
## exposure are the session's business; this panel only says which hour.
var _on_hour: Callable
## Called with a weather key and a value when one of the sky's own knobs is moved. The panel does
## not touch the sky itself: a session's weather is one state — the hour, with whatever has been
## moved by hand over it — and `PlayWeather` is what holds it. See `PlayWeather.set_override`.
var _on_sky: Callable
var _hour: float = 12.0
## The weather chooser, kept so that moving any of the sky's knobs can put it on `Custom`. A
## preset is a set of values here rather than a mode, so the moment one of them moves, what is on
## is no longer that preset.
var _weather_control: OptionButton = null
const CUSTOM: String = "Custom"
var _on_quit: Callable
var _on_map: Callable
var _on_vehicle: Callable
## Returns the weather that is on, as the dictionary the renderer reads. The rows are refreshed
## from it whenever a preset or the hour is chosen, and whenever the panel opens.
var _state_of: Callable
var _weather_rows: PlayWeatherRows = null
## What is loaded now, so the lists can mark it. Set by the session, which is the only thing that
## knows: the panel is told rather than guessing from the scene.
var _current_map: String = ""
var _current_vehicle: String = ""
var _tabs: TabContainer = null


## Builds the panel, hidden. `on_weather` is called with a preset name when the weather changes,
## because rebuilding the sky is the session's business and not this panel's; `on_quit` ends the
## session.
func setup(
    environment: Environment,
    sun: DirectionalLight3D,
    drive: PlayDrive,
    camera: Camera3D,
    weather: String,
    on_weather: Callable,
    on_hour: Callable,
    on_sky: Callable,
    on_quit: Callable,
    on_map: Callable = Callable(),
    on_vehicle: Callable = Callable(),
    state_of: Callable = Callable()
) -> void:
    _state_of = state_of
    _environment = environment
    _sun = sun
    _drive = drive
    _camera = camera
    _on_weather = on_weather
    _on_hour = on_hour
    _on_sky = on_sky
    _on_quit = on_quit
    _on_map = on_map
    _on_vehicle = on_vehicle
    for name: String in WeatherCfg.PRESETS.keys():
        # The same filter the F2 cycle uses: a measurement preset is an instrument and not an
        # hour of the day. See `PlayWeather._init`.
        if bool((WeatherCfg.get_preset(name)).get("measurement", false)):
            continue
        _weather_names.append(name)
    _weather_names.append(CUSTOM)
    _weather_index = maxi(0, _weather_names.find(weather))
    layer = 2
    _build()
    _panel.visible = false


## The vegetation this session is growing, once it exists: a terrain is loaded a frame or two
## after the window opens, so the panel is built before there is any grass to move.
func set_vegetation(vegetation: RorVegetation) -> void:
    _vegetation = vegetation


func toggle() -> void:
    _panel.visible = not _panel.visible
    if _panel.visible:
        _rebuild_content()
        refresh()
    # The mouse has to come back before anything can be clicked: a captured cursor is how a
    # driver looks around, and a panel nobody can click is a panel nobody can use.
    if _panel.visible:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
    _panel.visible = false


func is_open() -> bool:
    return _panel != null and _panel.visible


## Shows a preset as the one that is on — chosen by the session rather than here, as after a map
## change puts the starting weather back — and refreshes the rows to it.
func show_weather(name: String) -> void:
    var at: int = _weather_names.find(name)
    if at >= 0 and _weather_control != null:
        _weather_index = at
        _weather_control.selected = at
    refresh()


## Puts the weather that is on onto every weather row. Called when a preset or an hour is chosen
## and when the panel opens, so what the sliders say is what the world is doing.
func refresh() -> void:
    if _weather_rows != null and _state_of.is_valid():
        _weather_rows.refresh(_state_of.call() as Dictionary)


## --------------------------------------------------------------------------------


func _build() -> void:
    var centre: CenterContainer = CenterContainer.new()
    centre.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(centre)

    _panel = PanelContainer.new()
    _panel.name = "SettingsPanel"
    _panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
    centre.add_child(_panel)

    var margin: MarginContainer = MarginContainer.new()
    for side: String in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_%s" % side, 16)
    _panel.add_child(margin)

    _tabs = TabContainer.new()
    _tabs.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_MAX_HEIGHT)
    margin.add_child(_tabs)

    _vehicle_rows = _tab("Drive")
    _map_rows = _tab("World")
    _rows = _tab("Settings")

    _title()
    _world_section()
    _sky_section()
    _weather_rows = PlayWeatherRows.new()
    _weather_rows.build(
        _rows, _state_of.call() as Dictionary if _state_of.is_valid() else {},
        func(key: String, value: Variant) -> void:
            _mark_custom()
            if _on_sky.is_valid():
                _on_sky.call(key, value)
    )
    # The world as well as the camera: how far a session sees is a limit on what the terrain
    # draws, and the camera's own far plane stays where the terrain's horizon needs it.
    PlayDistanceRows.build(
        _rows, _environment, _camera, _vegetation,
        _sun.get_parent() as Node3D if _sun != null else null
    )
    _vehicle_section()
    MenuWidgets.buttons(_rows, PackedStringArray(["Resume", "Quit"]), func(index: int) -> void:
        if index == 0:
            close()
        elif _on_quit.is_valid():
            _on_quit.call()
    )


## One scrolling tab, and the rows inside it.
func _tab(title: String) -> VBoxContainer:
    var scroll: ScrollContainer = ScrollContainer.new()
    scroll.name = title
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    _tabs.add_child(scroll)
    var rows: VBoxContainer = VBoxContainer.new()
    rows.add_theme_constant_override("separation", 6)
    rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(rows)
    return rows


## Says what is loaded now and rebuilds the two content lists around it.
##
## Rebuilt rather than updated, and rebuilt every time the panel opens: content is the filesystem,
## so a pack unpacked while the window was running should appear without restarting the session.
## Nineteen buttons is not worth the machinery of keeping a list in step with a directory.
func set_loaded(map_name: String, vehicle_name: String) -> void:
    _current_map = map_name
    _current_vehicle = vehicle_name
    _rebuild_content()


func _rebuild_content() -> void:
    if _vehicle_rows == null or _map_rows == null:
        return
    for rows: VBoxContainer in [_vehicle_rows, _map_rows]:
        for child: Node in rows.get_children():
            rows.remove_child(child)
            child.queue_free()
    ContentBrowser.vehicles(_vehicle_rows, _current_vehicle, func(name: String) -> void:
        if _on_vehicle.is_valid():
            _on_vehicle.call(name)
        close()
    )
    ContentBrowser.maps(_map_rows, _current_map, func(name: String) -> void:
        if _on_map.is_valid():
            _on_map.call(name)
        close()
    )


func _title() -> void:
    var label: Label = Label.new()
    label.text = "Settings"
    label.add_theme_font_size_override("font_size", 20)
    _rows.add_child(label)
    MenuWidgets.note(_rows, "Esc closes this. Everything here is live and lasts for this session.")


## The world the vehicle is in: its weather, its gravity, its sun.
func _world_section() -> void:
    MenuWidgets.heading(_rows, "World")
    _weather_control = MenuWidgets.options(
        _rows, "Weather", _weather_names, _weather_index,
        func(index: int) -> void:
            _weather_index = index
            # `Custom` is what the panel shows when a knob has been moved, not something to put
            # on: there is nothing to apply that is not already applied.
            if _on_weather.is_valid() and _weather_names[index] != CUSTOM:
                _on_weather.call(_weather_names[index])
                refresh()
    )
    var names: Array = GRAVITY_PRESETS.keys()
    var gravity_names: PackedStringArray = PackedStringArray()
    for name: String in names:
        gravity_names.append(name)
    MenuWidgets.options(
        _rows, "Gravity", gravity_names, 0,
        func(index: int) -> void: _set_gravity(float(GRAVITY_PRESETS[names[index]]))
    )
    MenuWidgets.slider(
        _rows, "  m/s²", GRAVITY_MIN, GRAVITY_MAX, EARTH_GRAVITY,
        func(value: float) -> void: _set_gravity(value), "%.2f"
    )
    MenuWidgets.check(
        _rows, "Shadows", _sun != null and _sun.shadow_enabled,
        func(on: bool) -> void:
            if _sun != null:
                _sun.shadow_enabled = on
    )
    # The fill's shadow. The fill is a second directional light, a cool blue against a warm sun,
    # and unlike most fills it casts a shadow of its own with half the sun's range; its lux, trim
    # and colour are weather rows below, and this is the one thing about it that is not.
    var fill: DirectionalLight3D = _fill()
    MenuWidgets.check(
        _rows, "Fill shadows", fill != null and fill.shadow_enabled,
        func(on: bool) -> void:
            var light: DirectionalLight3D = _fill()
            if light != null:
                light.shadow_enabled = on
    )


## The fill light, found through the sun rather than passed in: both are built by
## `BlockoutWorld` into the same world, and a second parameter through four call sites to reach a
## sibling node is worse than asking the sun where it lives.
func _fill() -> DirectionalLight3D:
    if _sun == null or _sun.get_parent() == null:
        return null
    return _sun.get_parent().get_node_or_null(^"Fill") as DirectionalLight3D


## The sky: how bright it is, how it is graded, and what is in it. The rows themselves are
## `PlaySkyRows`, which this file went over the source cap to hold.
func _sky_section() -> void:
    PlaySkyRows.build(
        _rows, _environment, _hour,
        func(value: float) -> void:
            _hour = value
            _mark_custom()
            if _on_hour.is_valid():
                _on_hour.call(value)
            refresh()
    )


## Says that what is on is no longer the preset whose name is showing.
func _mark_custom() -> void:
    if _weather_control == null:
        return
    var at: int = _weather_names.find(CUSTOM)
    if at >= 0:
        _weather_index = at
        _weather_control.selected = at


## The one thing here that is on the vehicle: its lamps.
func _vehicle_section() -> void:
    if _drive == null:
        return
    MenuWidgets.heading(_rows, "Vehicle")
    MenuWidgets.check(
        _rows, "Lights  (N)", _drive.lights_on(),
        func(on: bool) -> void: _drive.set_lights(on)
    )


func _set_gravity(value: float) -> void:
    if _drive == null or _drive.solver == null:
        return
    _drive.solver.set_gravity(Vector3(0.0, value, 0.0))
