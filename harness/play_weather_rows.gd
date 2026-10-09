class_name PlayWeatherRows
extends RefCounted
## Every number a weather states, as a row in the settings panel, and the panel kept in step with
## the weather that is on.
##
## A session asked for two things that one table answers. **What is this preset made of?** Picking
## `dawn_mist` used to change the world and leave every slider where it was, so the mist could be
## seen and not read. **And can I move all of it?** The panel exposed the sun, the fog and the
## clouds; the sky's colours, the sun's lux, the exposure's three numbers, the fill, the grade and
## a dozen more were in the preset file and nowhere else. So the rows are built from this table —
## one entry per key the renderer reads from a weather dictionary — and `refresh` puts the weather
## that is on onto every control. A key the renderer reads that is not here is held by
## `the_panel_shows_the_weather_it_is_on`.
##
## Every row goes through `PlayWeather.set_override`: the value lands in the session's weather
## state and the whole weather is re-applied, so a slider and a preset take the same path.

## Kinds of row: a float slider, a colour, a tick, a direction (two sliders), a named map.
enum Kind { FLOAT, COLOUR, BOOL, DIRECTION, SKY_MAP }

## The table. `fallback` is what the renderer uses when a weather does not state the key, which is
## what the control shows then — these mirror the `weather.get(key, default)` calls in the
## renderer, and the gate checks the key set rather than the defaults.
const ROWS: Array[Dictionary] = [
    {"section": "Sun"},
    {"key": "sun_from", "label": "Sun elevation / azimuth", "kind": Kind.DIRECTION,
     "fallback": Vector3.UP},
    {"key": "sun_lux", "label": "Sun lux", "kind": Kind.FLOAT, "low": 0.0, "high": 120000.0,
     "fallback": 100000.0, "format": "%.0f"},
    {"key": "sun_energy", "label": "Sun trim", "kind": Kind.FLOAT, "low": 0.0, "high": 4.0,
     "fallback": 1.0},
    {"key": "sun_color", "label": "Sun colour", "kind": Kind.COLOUR, "fallback": Color.WHITE},
    {"key": "sun_angular_deg", "label": "Sun size", "kind": Kind.FLOAT, "low": 0.0, "high": 10.0,
     "fallback": 1.8, "format": "%.1f°"},
    {"key": "shadow_opacity", "label": "Shadow opacity", "kind": Kind.FLOAT, "low": 0.0,
     "high": 1.0, "fallback": 0.72},
    {"section": "Fill"},
    {"key": "fill_lux", "label": "Fill lux", "kind": Kind.FLOAT, "low": 0.0, "high": 20000.0,
     "fallback": 12000.0, "format": "%.0f"},
    {"key": "fill_energy", "label": "Fill trim", "kind": Kind.FLOAT, "low": 0.0, "high": 4.0,
     "fallback": 1.0},
    {"key": "fill_colour", "label": "Fill colour", "kind": Kind.COLOUR,
     "fallback": Color(0.72, 0.80, 0.95)},
    {"section": "Sky"},
    {"key": "physical_sky", "label": "Physical sky", "kind": Kind.BOOL, "fallback": false},
    {"key": "sky_shader", "label": "Sky shader", "kind": Kind.BOOL, "fallback": false},
    {"key": "turbidity", "label": "Turbidity", "kind": Kind.FLOAT, "low": 1.0, "high": 12.0,
     "fallback": 2.0, "format": "%.1f"},
    {"key": "sky_energy", "label": "Sky energy", "kind": Kind.FLOAT, "low": 0.0, "high": 4.0,
     "fallback": 1.0},
    {"key": "sky_top", "label": "Sky top", "kind": Kind.COLOUR, "fallback": Color(0.16, 0.33, 0.66)},
    {"key": "sky_horizon", "label": "Sky horizon", "kind": Kind.COLOUR,
     "fallback": Color(0.62, 0.72, 0.84)},
    {"key": "bg_color", "label": "Background", "kind": Kind.COLOUR, "fallback": Color.BLACK},
    {"key": "disc_energy", "label": "Sun disc", "kind": Kind.FLOAT, "low": 0.0, "high": 4.0,
     "fallback": 1.0},
    {"key": "stars", "label": "Stars", "kind": Kind.FLOAT, "low": 0.0, "high": 2.0, "fallback": 0.0},
    {"key": "hdri", "label": "Captured sky", "kind": Kind.SKY_MAP, "fallback": ""},
    {"key": "hdri_gain", "label": "Capture gain", "kind": Kind.FLOAT, "low": 0.0, "high": 2.0,
     "fallback": 1.0, "format": "%.3f"},
    {"key": "hdri_mix", "label": "Capture mix", "kind": Kind.FLOAT, "low": 0.0, "high": 1.0,
     "fallback": 0.0},
    {"key": "hdri_yaw", "label": "Capture yaw", "kind": Kind.FLOAT, "low": -180.0, "high": 180.0,
     "fallback": 0.0, "format": "%.0f°"},
    {"key": "radiance_scale", "label": "Radiance scale", "kind": Kind.FLOAT, "low": 0.0,
     "high": 4.0, "fallback": 1.0},
    {"section": "Clouds"},
    {"key": "cloud_coverage", "label": "Cloud cover", "kind": Kind.FLOAT, "low": 0.0, "high": 1.0,
     "fallback": 0.5},
    {"key": "cloud_density", "label": "Cloud density", "kind": Kind.FLOAT, "low": 0.0, "high": 3.0,
     "fallback": 1.1},
    {"key": "cloud_wind_speed", "label": "Wind", "kind": Kind.FLOAT, "low": 0.0, "high": 0.05,
     "fallback": 0.0, "format": "%.3f"},
    {"key": "cloud_light", "label": "Cloud light", "kind": Kind.FLOAT, "low": 0.0, "high": 2.0,
     "fallback": 1.0},
    {"section": "Light"},
    {"key": "ambient_energy", "label": "Ambient energy", "kind": Kind.FLOAT, "low": 0.0,
     "high": 2.0, "fallback": 0.0},
    {"key": "ambient_from_sky", "label": "Ambient from sky", "kind": Kind.FLOAT, "low": 0.0,
     "high": 1.0, "fallback": 1.0},
    {"key": "ambient_colour", "label": "Ambient colour", "kind": Kind.COLOUR,
     "fallback": Color.WHITE},
    {"key": "occlusion", "label": "Ambient occlusion", "kind": Kind.BOOL, "fallback": true},
    {"key": "unlit_dim", "label": "Unlit dim", "kind": Kind.FLOAT, "low": 0.0, "high": 1.0,
     "fallback": 1.0},
    {"key": "probe_intensity", "label": "Probe intensity", "kind": Kind.FLOAT, "low": 0.0,
     "high": 4.0, "fallback": 1.0},
    {"section": "Air"},
    {"key": "fog_density", "label": "Fog thickness", "kind": Kind.FLOAT, "low": 0.0, "high": 0.02,
     "fallback": 0.00006, "format": "%.5f"},
    {"key": "fog_colour", "label": "Fog colour", "kind": Kind.COLOUR,
     "fallback": Color(0.62, 0.72, 0.84)},
    {"key": "volumetric", "label": "Volumetric", "kind": Kind.BOOL, "fallback": false},
    {"section": "Camera"},
    {"key": "iso", "label": "ISO", "kind": Kind.FLOAT, "low": 10.0, "high": 3200.0,
     "fallback": 45.0, "format": "%.0f"},
    {"key": "f_stop", "label": "f-stop", "kind": Kind.FLOAT, "low": 1.0, "high": 22.0,
     "fallback": 8.0, "format": "f/%.1f"},
    {"key": "shutter_s", "label": "Shutter", "kind": Kind.FLOAT, "low": 0.0005, "high": 0.1,
     "fallback": 0.008, "format": "%.4f s"},
    {"section": "Grade"},
    {"key": "grade", "label": "Grade", "kind": Kind.BOOL, "fallback": true},
    {"key": "grade_brightness", "label": "Brightness", "kind": Kind.FLOAT, "low": 0.0, "high": 2.0,
     "fallback": 1.0},
    {"key": "grade_contrast", "label": "Contrast", "kind": Kind.FLOAT, "low": 0.0, "high": 2.0,
     "fallback": 1.0},
    {"key": "grade_saturation", "label": "Saturation", "kind": Kind.FLOAT, "low": 0.0, "high": 2.0,
     "fallback": 1.0},
]

## Keys the renderer reads that are not a person's to move: derived from another key, a gate's
## instrument, a file path, or the cloud clock. Listed so the gate can tell "not a knob" from
## "forgotten".
const NOT_A_KNOB: PackedStringArray = [
    "cloud_phase", "hdri_cloudy", "hdri_cloudy_gain", "hdri_cloudy_mix", "grade_lut",
    "measurement",
]

## The captured skies a session can put up, by file, with "" for none.
const SKY_MAP_NAMES: PackedStringArray = ["none", "clear", "overcast", "dusk"]


## The controls, keyed by weather key. A direction holds two sliders under "<key>/elevation" and
## "<key>/azimuth".
var controls: Dictionary = {}
var _on_sky: Callable
## True while `refresh` is writing, so the controls' own signals do not write back.
var _refreshing: bool = false


## Builds every row into `rows`. `state` is the weather that is on; `on_sky` is called with a key
## and a value when a row moves.
func build(rows: VBoxContainer, state: Dictionary, on_sky: Callable) -> void:
    _on_sky = on_sky
    for row: Dictionary in ROWS:
        if row.has("section"):
            MenuWidgets.heading(rows, row["section"] as String)
            continue
        var key: String = row["key"] as String
        var value: Variant = state.get(key, row["fallback"])
        match row["kind"] as Kind:
            Kind.FLOAT:
                controls[key] = MenuWidgets.slider(
                    rows, row["label"] as String, row["low"] as float, row["high"] as float,
                    float(value), func(moved: float) -> void: _moved(key, moved),
                    row.get("format", "%.2f") as String
                )
            Kind.COLOUR:
                controls[key] = MenuWidgets.colour(
                    rows, row["label"] as String, value as Color,
                    func(picked: Color) -> void: _moved(key, picked)
                )
            Kind.BOOL:
                controls[key] = MenuWidgets.check(
                    rows, row["label"] as String, bool(value),
                    func(on: bool) -> void: _moved(key, on)
                )
            Kind.DIRECTION:
                _direction_rows(rows, key, value as Vector3)
            Kind.SKY_MAP:
                controls[key] = MenuWidgets.options(
                    rows, row["label"] as String, SKY_MAP_NAMES, _sky_map_index(value as String),
                    func(index: int) -> void: _moved(key, _sky_map_file(index))
                )


## Puts the weather that is on onto every control, without any of them writing back.
func refresh(state: Dictionary) -> void:
    _refreshing = true
    for row: Dictionary in ROWS:
        if row.has("section"):
            continue
        var key: String = row["key"] as String
        var value: Variant = state.get(key, row["fallback"])
        match row["kind"] as Kind:
            Kind.FLOAT:
                MenuWidgets.set_slider(controls[key] as HSlider, float(value))
            Kind.COLOUR:
                (controls[key] as ColorPickerButton).color = value as Color
            Kind.BOOL:
                (controls[key] as CheckBox).set_pressed_no_signal(bool(value))
            Kind.DIRECTION:
                var toward: Vector3 = (value as Vector3).normalized()
                MenuWidgets.set_slider(controls[key + "/elevation"] as HSlider, elevation_of(toward))
                MenuWidgets.set_slider(controls[key + "/azimuth"] as HSlider, azimuth_of(toward))
            Kind.SKY_MAP:
                (controls[key] as OptionButton).selected = _sky_map_index(value as String)
    _refreshing = false


func _moved(key: String, value: Variant) -> void:
    if _refreshing:
        return
    if _on_sky.is_valid():
        _on_sky.call(key, value)


## A direction as two sliders: "up and over that shoulder" is something a person can reason
## about and a unit vector is not.
func _direction_rows(rows: VBoxContainer, key: String, toward: Vector3) -> void:
    var unit: Vector3 = toward.normalized()
    controls[key + "/elevation"] = MenuWidgets.slider(
        rows, "Sun elevation", -10.0, 89.0, elevation_of(unit),
        func(_moved_to: float) -> void: _direction_moved(key), "%.0f°"
    )
    controls[key + "/azimuth"] = MenuWidgets.slider(
        rows, "Sun azimuth", -180.0, 180.0, azimuth_of(unit),
        func(_moved_to: float) -> void: _direction_moved(key), "%.0f°"
    )


func _direction_moved(key: String) -> void:
    var elevation: float = deg_to_rad((controls[key + "/elevation"] as HSlider).value)
    var azimuth: float = deg_to_rad((controls[key + "/azimuth"] as HSlider).value)
    _moved(key, Vector3(
        cos(elevation) * sin(azimuth), sin(elevation), cos(elevation) * cos(azimuth)
    ).normalized())


static func elevation_of(toward: Vector3) -> float:
    return rad_to_deg(asin(clampf(toward.y, -1.0, 1.0)))


static func azimuth_of(toward: Vector3) -> float:
    return rad_to_deg(atan2(toward.x, toward.z))


static func _sky_map_index(file: String) -> int:
    var files: Array[String] = _sky_map_files()
    var at: int = files.find(file)
    return maxi(at, 0)


static func _sky_map_file(index: int) -> String:
    var files: Array[String] = _sky_map_files()
    return files[clampi(index, 0, files.size() - 1)]


static func _sky_map_files() -> Array[String]:
    return [
        "", SkyMaps.CLEAR["file"] as String, SkyMaps.OVERCAST["file"] as String,
        SkyMaps.DUSK["file"] as String,
    ]
