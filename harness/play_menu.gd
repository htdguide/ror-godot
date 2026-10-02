class_name PlayMenu
extends CanvasLayer
## The settings panel: everything about the world a person wants to change while driving, in one
## place, opened with Esc.
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
const SUN_ELEVATION_RANGE: Vector2 = Vector2(-10.0, 89.0)
const SUN_AZIMUTH_RANGE: Vector2 = Vector2(-180.0, 180.0)
## How far a session may push the view, and how thick the haze may get.
const VIEW_RANGE_M: Vector2 = Vector2(200.0, 12000.0)
const FOG_RANGE: Vector2 = Vector2(0.0, 0.02)
const GRASS_RANGE_M: Vector2 = Vector2(0.0, 400.0)
const PANEL_WIDTH: int = 380
const PANEL_MAX_HEIGHT: int = 720


var _panel: PanelContainer
var _rows: VBoxContainer
var _environment: Environment
var _sun: DirectionalLight3D
var _drive: PlayDrive
var _camera: Camera3D
var _vegetation: RorVegetation = null
var _weather_names: PackedStringArray = PackedStringArray()
var _weather_index: int = 0
var _on_weather: Callable
var _on_quit: Callable


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
    on_quit: Callable
) -> void:
    _environment = environment
    _sun = sun
    _drive = drive
    _camera = camera
    _on_weather = on_weather
    _on_quit = on_quit
    for name: String in WeatherCfg.PRESETS.keys():
        _weather_names.append(name)
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
    # The mouse has to come back before anything can be clicked: a captured cursor is how a
    # driver looks around, and a panel nobody can click is a panel nobody can use.
    if _panel.visible:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
    _panel.visible = false


func is_open() -> bool:
    return _panel != null and _panel.visible


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

    var scroll: ScrollContainer = ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_MAX_HEIGHT)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    margin.add_child(scroll)

    _rows = VBoxContainer.new()
    _rows.add_theme_constant_override("separation", 6)
    _rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(_rows)

    _title()
    _world_section()
    _sky_section()
    _distance_section()
    _vehicle_section()
    MenuWidgets.buttons(_rows, PackedStringArray(["Resume", "Quit"]), func(index: int) -> void:
        if index == 0:
            close()
        elif _on_quit.is_valid():
            _on_quit.call()
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
    MenuWidgets.options(
        _rows, "Weather", _weather_names, _weather_index,
        func(index: int) -> void:
            _weather_index = index
            if _on_weather.is_valid():
                _on_weather.call(_weather_names[index])
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
    MenuWidgets.slider(
        _rows, "Sun elevation", SUN_ELEVATION_RANGE.x, SUN_ELEVATION_RANGE.y, _sun_elevation(),
        func(value: float) -> void: _aim_sun(value, _sun_azimuth()), "%.0f°"
    )
    MenuWidgets.slider(
        _rows, "Sun azimuth", SUN_AZIMUTH_RANGE.x, SUN_AZIMUTH_RANGE.y, _sun_azimuth(),
        func(value: float) -> void: _aim_sun(_sun_elevation(), value), "%.0f°"
    )
    MenuWidgets.slider(
        _rows, "Sun brightness", 0.0, 4.0, _sun.light_energy if _sun != null else 1.0,
        func(value: float) -> void:
            if _sun != null:
                _sun.light_energy = value
    )
    MenuWidgets.check(
        _rows, "Shadows", _sun != null and _sun.shadow_enabled,
        func(on: bool) -> void:
            if _sun != null:
                _sun.shadow_enabled = on
    )
    # The fill, which until now could not be touched from here at all.
    #
    # It is a second directional light, it is a cool blue against a warm sun, and unlike most
    # fills it casts a shadow of its own with half the sun's range. That makes it the first thing
    # to try when something on the ground looks like a region rather than a shape — a reported
    # rectangle under the vehicle is what showed there was no way to test it.
    var fill: DirectionalLight3D = _fill()
    MenuWidgets.slider(
        _rows, "Fill brightness", 0.0, 4.0, fill.light_energy if fill != null else 0.0,
        func(value: float) -> void:
            var light: DirectionalLight3D = _fill()
            if light != null:
                light.light_energy = value
    )
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


## The sky: how bright it is, how it is graded, and what is in it.
func _sky_section() -> void:
    MenuWidgets.heading(_rows, "Sky")
    MenuWidgets.slider(
        _rows, "Sky brightness", 0.0, 4.0, _environment.ambient_light_energy,
        func(value: float) -> void: _environment.ambient_light_energy = value
    )
    MenuWidgets.slider(
        _rows, "Exposure", 0.1, 3.0, _environment.tonemap_exposure,
        func(value: float) -> void: _environment.tonemap_exposure = value
    )
    var clouds: Dictionary = SkyClouds.settings(_environment)
    if clouds.is_empty():
        MenuWidgets.note(_rows, "This sky has no clouds to move.")
        return
    MenuWidgets.slider(
        _rows, "Cloud cover", 0.0, 1.0, clouds["coverage"] as float,
        func(value: float) -> void: SkyClouds.set_parameter(_environment, "coverage", value)
    )
    MenuWidgets.slider(
        _rows, "Cloud density", 0.0, 3.0, clouds["density"] as float,
        func(value: float) -> void: SkyClouds.set_parameter(_environment, "density", value)
    )
    MenuWidgets.slider(
        _rows, "Wind", 0.0, 0.05, clouds["wind_speed"] as float,
        func(value: float) -> void: SkyClouds.set_parameter(_environment, "wind_speed", value),
        "%.3f"
    )


## How far a person can see, and what closes the distance.
func _distance_section() -> void:
    MenuWidgets.heading(_rows, "Distance")
    MenuWidgets.slider(
        _rows, "View distance", VIEW_RANGE_M.x, VIEW_RANGE_M.y,
        _camera.far if _camera != null else RenderCfg.VIEW_DISTANCE_M,
        func(value: float) -> void:
            if _camera != null:
                _camera.far = value,
        "%.0f m"
    )
    MenuWidgets.check(
        _rows, "Fog", _environment.fog_enabled,
        func(on: bool) -> void: _environment.fog_enabled = on
    )
    MenuWidgets.slider(
        _rows, "Fog thickness", FOG_RANGE.x, FOG_RANGE.y, _environment.fog_density,
        func(value: float) -> void:
            _environment.fog_density = value
            _environment.fog_enabled = value > 0.0,
        "%.4f"
    )
    MenuWidgets.slider(
        _rows, "Fog in the sky", 0.0, 1.0, _environment.fog_sky_affect,
        func(value: float) -> void: _environment.fog_sky_affect = value
    )
    MenuWidgets.slider(
        _rows, "Grass distance", GRASS_RANGE_M.x, GRASS_RANGE_M.y,
        _vegetation.range_m() if _vegetation != null else RorVegetation.MAX_RANGE_M,
        func(value: float) -> void:
            if _vegetation != null:
                _vegetation.set_range(value),
        "%.0f m"
    )


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


## Where the sun is now, as elevation and azimuth in degrees, read back from the light so the
## sliders start where the weather preset put it.
func _sun_elevation() -> float:
    if _sun == null:
        return 45.0
    var toward: Vector3 = -_sun.global_transform.basis.z
    return rad_to_deg(asin(clampf(-toward.y, -1.0, 1.0)))


func _sun_azimuth() -> float:
    if _sun == null:
        return 0.0
    var toward: Vector3 = -_sun.global_transform.basis.z
    return rad_to_deg(atan2(-toward.x, -toward.z))


## Points the sun, from where it is in the sky rather than from Euler angles: "up and over that
## shoulder" is something a person can reason about and a pitch and a yaw are not.
func _aim_sun(elevation_deg: float, azimuth_deg: float) -> void:
    if _sun == null:
        return
    var elevation: float = deg_to_rad(elevation_deg)
    var azimuth: float = deg_to_rad(azimuth_deg)
    var toward_sun: Vector3 = Vector3(
        cos(elevation) * sin(azimuth), sin(elevation), cos(elevation) * cos(azimuth)
    ).normalized()
    _sun.look_at_from_position(_sun.position, _sun.position - toward_sun, Vector3.UP)
