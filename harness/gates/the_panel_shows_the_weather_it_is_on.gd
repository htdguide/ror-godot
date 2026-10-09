extends GateBase
## The settings panel has a row for every number a weather states, and shows the weather that is on.
##
## A session picked `dawn_mist` and asked what it was made of, and the panel could not say: the
## preset changed the world and left every slider where it had been, and most of what the preset
## states — the sun's lux, the sky's two colours, the exposure's three numbers, the fill, the
## grade — had no slider at all. `PlayWeatherRows` is one table that answers both, and this holds
## the table to the renderer and the controls to the weather.
##
## Two checks. **Coverage**: every key the renderer reads from a weather dictionary — found by
## reading the renderer's own source for `weather.get("…"`, not by asking the table — is a row or
## is listed as not a knob, and every row is a key the renderer reads. **Refresh**: the rows are
## built under one preset and refreshed to another, and every control then says exactly what the
## second preset states, to the bit for a float and to a hundredth of a degree for the sun; and a
## control moved by hand reports its own key once.

const BUILT_UNDER: String = "golden_dusk"
const REFRESHED_TO: String = "dawn_mist"
## Where a weather dictionary is read: the renderer, and the session that applies one to it.
const SOURCE_DIRS: PackedStringArray = ["game/gfx", "game/config", "game/world", "game/terrain", "harness"]
const DEGREE_TOLERANCE: float = 0.01


static func meta() -> Dictionary:
    return {
        "name": "the_panel_shows_the_weather_it_is_on",
        "proves": "every weather key the renderer reads is a settings row or declared not a knob, every row is read by the renderer, and refreshing the rows to a preset puts that preset's every stated value on its control exactly",
        "builds_on": ["a_weather_switch_is_a_weather"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "0 keys read and not exposed, 0 rows nothing reads, 0 controls disagreeing with the preset after a refresh, and one callback per moved control",
        "why": (
            "a preset the panel cannot show is a preset nobody can learn from or adjust, and a"
            + " key the renderer reads with no row is a knob only the file has. Reading the"
            + " renderer's source for its keys is what keeps the table from grading itself."
        ),
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M2",
    }


func run(_harness: Node) -> Dictionary:
    var read: Dictionary = _keys_the_renderer_reads()
    if read.size() < 20:
        return fail("only %d weather keys found in the renderer's source: the scan is broken" % read.size(), read.size())
    var exposed: Dictionary = {}
    for row: Dictionary in PlayWeatherRows.ROWS:
        if row.has("key"):
            exposed[row["key"]] = true
    var missing: PackedStringArray = PackedStringArray()
    for key: String in read:
        if not exposed.has(key) and not PlayWeatherRows.NOT_A_KNOB.has(key):
            missing.append(key)
    var dead: PackedStringArray = PackedStringArray()
    for key: String in exposed:
        if not read.has(key):
            dead.append(key)
    if not missing.is_empty():
        return fail("%d keys the renderer reads have no row and are not declared as not a knob: %s" % [missing.size(), ", ".join(missing)], missing.size())
    if not dead.is_empty():
        return fail("%d rows are keys nothing in the renderer reads: %s" % [dead.size(), ", ".join(dead)], dead.size())

    var moved: Array = []
    var rows: VBoxContainer = VBoxContainer.new()
    var panel: PlayWeatherRows = PlayWeatherRows.new()
    panel.build(rows, WeatherCfg.get_preset(BUILT_UNDER), func(key: String, value: Variant) -> void:
        moved.append([key, value])
    )
    var preset: Dictionary = WeatherCfg.get_preset(REFRESHED_TO)
    panel.refresh(preset)
    if not moved.is_empty():
        rows.free()
        return fail("a refresh wrote back %d values through the panel's own callback" % moved.size(), moved.size())
    var checked: int = 0
    var wrong: PackedStringArray = PackedStringArray()
    for row: Dictionary in PlayWeatherRows.ROWS:
        if not row.has("key") or not preset.has(row["key"]):
            continue
        var key: String = row["key"] as String
        var stated: Variant = preset[key]
        checked += 1
        match row["kind"] as PlayWeatherRows.Kind:
            PlayWeatherRows.Kind.FLOAT:
                var shown: float = (panel.controls[key] as HSlider).value
                if shown != float(stated):
                    wrong.append("%s shows %s, preset states %s" % [key, shown, stated])
            PlayWeatherRows.Kind.COLOUR:
                if (panel.controls[key] as ColorPickerButton).color != (stated as Color):
                    wrong.append("%s shows a colour the preset does not state" % key)
            PlayWeatherRows.Kind.BOOL:
                if (panel.controls[key] as CheckBox).button_pressed != bool(stated):
                    wrong.append("%s shows %s" % [key, not bool(stated)])
            PlayWeatherRows.Kind.DIRECTION:
                var toward: Vector3 = (stated as Vector3).normalized()
                var elevation: float = (panel.controls[key + "/elevation"] as HSlider).value
                var azimuth: float = (panel.controls[key + "/azimuth"] as HSlider).value
                if absf(elevation - PlayWeatherRows.elevation_of(toward)) > DEGREE_TOLERANCE \
                        or absf(azimuth - PlayWeatherRows.azimuth_of(toward)) > DEGREE_TOLERANCE:
                    wrong.append("%s shows %.2f/%.2f deg, preset states %.2f/%.2f" % [
                        key, elevation, azimuth, PlayWeatherRows.elevation_of(toward),
                        PlayWeatherRows.azimuth_of(toward)])
            PlayWeatherRows.Kind.SKY_MAP:
                var shown: int = (panel.controls[key] as OptionButton).selected
                if PlayWeatherRows._sky_map_file(shown) != (stated as String):
                    wrong.append("%s shows map %d, preset states %s" % [key, shown, stated])
    if not wrong.is_empty():
        rows.free()
        return fail("%d of %d controls disagree with %s after a refresh: %s" % [wrong.size(), checked, REFRESHED_TO, "; ".join(wrong)], wrong.size())

    # A control moved by hand reports its own key, once. Through the handler the slider's own
    # signal is wired to, called as the signal would call it: this engine build does not emit
    # `value_changed` for a value set from a script in a headless tree, and a drag is not
    # something a gate can do.
    var slider: HSlider = panel.controls["sun_lux"] as HSlider
    slider.set_value_no_signal(12345.0)
    for connection: Dictionary in slider.value_changed.get_connections():
        (connection["callable"] as Callable).call(12345.0)
    rows.free()
    if moved.size() != 1 or (moved[0][0] as String) != "sun_lux" or float(moved[0][1]) != 12345.0:
        return fail("moving the sun lux slider reported %s rather than one sun_lux of 12345" % JSON.stringify(moved), moved.size())
    return ok(
        "%d weather keys read by the renderer: %d rows, %d declared not a knob; %d controls agree with %s after a refresh built under %s; a moved slider reports its key once"
        % [read.size(), exposed.size(), PlayWeatherRows.NOT_A_KNOB.size(), checked, REFRESHED_TO, BUILT_UNDER],
        checked
    )


## Every `weather.get("key"` in the renderer's own source.
func _keys_the_renderer_reads() -> Dictionary:
    var keys: Dictionary = {}
    var pattern: RegEx = RegEx.new()
    pattern.compile("weather\\.get\\(\"([a-z_]+)\"")
    for dir: String in SOURCE_DIRS:
        var path: String = SourceScan.repo_root().path_join(dir)
        for file: String in DirAccess.get_files_at(path):
            if not file.ends_with(".gd"):
                continue
            var text: String = FileAccess.get_file_as_string(path.path_join(file))
            for found: RegExMatch in pattern.search_all(text):
                keys[found.get_string(1)] = true
    return keys
