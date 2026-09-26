class_name PlayMenu
extends CanvasLayer
## The environment panel: the settings a person wants to change while driving, without leaving the
## window or restarting a session.
##
## Weather, gravity, the sun, fog, shadows and the solver's own rate. Everything here changes the
## world the vehicle is in rather than the vehicle, which is the line: a panel that could also
## retune the rig would be a panel that makes a session's findings unreproducible, and the rig's
## own numbers belong in its file.
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
const FOG_MAX: float = 0.05
const PANEL_WIDTH: int = 330
const PANEL_MARGIN: int = 18

var _panel: PanelContainer
var _rows: VBoxContainer
var _environment: Environment
var _sun: DirectionalLight3D
var _drive: PlayDrive
var _weather_names: PackedStringArray = PackedStringArray()
var _weather_index: int = 0
var _on_weather: Callable


## Builds the panel, hidden. `on_weather` is called with a preset name when the weather changes,
## because rebuilding the sky is the session's business and not this panel's.
func setup(
    environment: Environment, sun: DirectionalLight3D, drive: PlayDrive, weather: String,
    on_weather: Callable
) -> void:
    _environment = environment
    _sun = sun
    _drive = drive
    _on_weather = on_weather
    for name: String in WeatherCfg.PRESETS.keys():
        _weather_names.append(name)
    _weather_index = maxi(0, _weather_names.find(weather))
    layer = 2
    _build()
    _panel.visible = false


func toggle() -> void:
    _panel.visible = not _panel.visible
    # The mouse has to come back before anything can be clicked: a captured cursor is how a
    # driver looks around, and a panel nobody can click is a panel nobody can use.
    if _panel.visible:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_open() -> bool:
    return _panel != null and _panel.visible


## --------------------------------------------------------------------------------


func _build() -> void:
    _panel = PanelContainer.new()
    _panel.name = "EnvironmentPanel"
    _panel.position = Vector2(PANEL_MARGIN, PANEL_MARGIN * 5)
    _panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
    add_child(_panel)

    _rows = VBoxContainer.new()
    _rows.add_theme_constant_override("separation", 6)
    _panel.add_child(_rows)

    _heading("Environment  —  M to close")
    _weather_row()
    _gravity_row()
    _slider("Sun elevation", SUN_ELEVATION_RANGE.x, SUN_ELEVATION_RANGE.y, _sun_elevation(),
        func(value: float) -> void: _aim_sun(value, _sun_azimuth()))
    _slider("Sun azimuth", SUN_AZIMUTH_RANGE.x, SUN_AZIMUTH_RANGE.y, _sun_azimuth(),
        func(value: float) -> void: _aim_sun(_sun_elevation(), value))
    _slider("Sun brightness", 0.0, 4.0, _sun.light_energy if _sun != null else 1.0,
        func(value: float) -> void:
            if _sun != null:
                _sun.light_energy = value)
    _slider("Sky brightness", 0.0, 4.0, _environment.ambient_light_energy,
        func(value: float) -> void: _environment.ambient_light_energy = value)
    _slider("Exposure", 0.1, 3.0, _environment.tonemap_exposure,
        func(value: float) -> void: _environment.tonemap_exposure = value)
    _slider("Fog", 0.0, FOG_MAX, _environment.volumetric_fog_density,
        func(value: float) -> void:
            _environment.volumetric_fog_enabled = value > 0.0001
            _environment.volumetric_fog_density = value)
    _check("Shadows", _sun != null and _sun.shadow_enabled,
        func(on: bool) -> void:
            if _sun != null:
                _sun.shadow_enabled = on)


func _heading(text: String) -> void:
    var label: Label = Label.new()
    label.text = text
    _rows.add_child(label)


## Weather is a preset rather than a set of sliders: the presets are what the gates render under,
## so a session and a gate can be talking about the same light.
func _weather_row() -> void:
    var row: HBoxContainer = HBoxContainer.new()
    var label: Label = Label.new()
    label.text = "Weather"
    label.custom_minimum_size = Vector2(120, 0)
    row.add_child(label)
    var options: OptionButton = OptionButton.new()
    for index: int in _weather_names.size():
        options.add_item(_weather_names[index], index)
    options.selected = _weather_index
    options.item_selected.connect(func(index: int) -> void:
        _weather_index = index
        if _on_weather.is_valid():
            _on_weather.call(_weather_names[index])
    )
    row.add_child(options)
    _rows.add_child(row)


## Gravity goes to the solver, which is the only setting here that touches the simulation. It is
## the one a person actually wants: a truck on the Moon is the fastest way to see what the
## suspension is doing.
func _gravity_row() -> void:
    var row: HBoxContainer = HBoxContainer.new()
    var label: Label = Label.new()
    label.text = "Gravity"
    label.custom_minimum_size = Vector2(120, 0)
    row.add_child(label)
    var options: OptionButton = OptionButton.new()
    var names: Array = GRAVITY_PRESETS.keys()
    for index: int in names.size():
        options.add_item(names[index] as String, index)
    options.selected = 0
    options.item_selected.connect(func(index: int) -> void:
        _set_gravity(float(GRAVITY_PRESETS[names[index]]))
    )
    row.add_child(options)
    _rows.add_child(row)
    _slider("  m/s²", GRAVITY_MIN, GRAVITY_MAX, EARTH_GRAVITY,
        func(value: float) -> void: _set_gravity(value))


func _set_gravity(value: float) -> void:
    if _drive == null or _drive.solver == null:
        return
    _drive.solver.set_gravity(Vector3(0.0, value, 0.0))


func _slider(text: String, low: float, high: float, value: float, on_change: Callable) -> void:
    var row: HBoxContainer = HBoxContainer.new()
    var label: Label = Label.new()
    label.text = text
    label.custom_minimum_size = Vector2(120, 0)
    row.add_child(label)
    var slider: HSlider = HSlider.new()
    slider.min_value = low
    slider.max_value = high
    slider.step = (high - low) / 200.0
    slider.value = clampf(value, low, high)
    slider.custom_minimum_size = Vector2(150, 0)
    var readout: Label = Label.new()
    readout.text = "%.2f" % slider.value
    readout.custom_minimum_size = Vector2(46, 0)
    slider.value_changed.connect(func(changed: float) -> void:
        readout.text = "%.2f" % changed
        on_change.call(changed)
    )
    row.add_child(slider)
    row.add_child(readout)
    _rows.add_child(row)


func _check(text: String, value: bool, on_change: Callable) -> void:
    var box: CheckBox = CheckBox.new()
    box.text = text
    box.button_pressed = value
    box.toggled.connect(func(pressed: bool) -> void: on_change.call(pressed))
    _rows.add_child(box)


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
