extends GateBase
## Every graphics option survives a save and a load, and lands on the viewport it is applied to.
##
## The main menu's graphics page promises that its rows do something, and this is what holds the
## promise short of looking: each setting is written to a file and read back the same, including
## one an older build would not know; and the viewport's share — render scale, upscaler, the
## anti-aliasing mode in its three forms — is read back off a viewport of this gate's own after
## `apply`. The window mode and vsync go to the display server and cannot be held headless; they
## are left to the person at the window.

const SCRATCH: String = "user://settings_gate.cfg"


static func meta() -> Dictionary:
    return {
        "name": "the_graphics_settings_round_trip_and_apply",
        "proves": "every graphics setting survives save and load, unknown keys are dropped and missing ones defaulted, and render scale, upscaler and anti-aliasing land on a viewport after apply",
        "builds_on": ["the_panel_shows_the_weather_it_is_on"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "0 settings lost or changed by a round trip; 5 anti-aliasing modes each read back as set; scale and upscaler read back as set",
        "why": (
            "a settings page whose rows do nothing is worse than none: a person turns a knob,"
            + " sees no change, and stops trusting the ones that work."
        ),
        "budget_s": 10.0,
        "needs_gpu": false,
        "milestone": "M2",
    }


func run(_harness: Node) -> Dictionary:
    var problems: PackedStringArray = PackedStringArray()
    var settings: GraphicsSettings = GraphicsSettings.new()
    settings.set_value("render_scale", 0.75)
    settings.set_value("anti_aliasing", 2)
    settings.set_value("vsync", false)
    settings.set_value("view_distance_m", 3210.0)
    var saved: Error = settings.save_to(SCRATCH)
    if saved != OK:
        return fail("saving to %s returned %d" % [SCRATCH, saved], saved)
    # An unknown key from a future build, and a missing one from an older build.
    var config: ConfigFile = ConfigFile.new()
    config.load(SCRATCH)
    config.set_value(GraphicsSettings.SECTION, "ray_tracing", true)
    config.erase_section_key(GraphicsSettings.SECTION, "grass_distance_m")
    config.save(SCRATCH)
    var loaded: GraphicsSettings = GraphicsSettings.new()
    loaded.load_from(SCRATCH)
    for key: String in settings.values:
        if key == "grass_distance_m":
            continue
        if loaded.values[key] != settings.values[key]:
            problems.append("%s saved as %s, loaded as %s" % [key, settings.values[key], loaded.values[key]])
    if loaded.values.has("ray_tracing"):
        problems.append("an unknown key was kept")
    if loaded.values["grass_distance_m"] != GraphicsSettings.DEFAULTS["grass_distance_m"]:
        problems.append("a missing key was not defaulted")
    # A file written over older defaults is not trusted at all.
    config.set_value(GraphicsSettings.SECTION, "version", 1)
    config.save(SCRATCH)
    var stale: GraphicsSettings = GraphicsSettings.new()
    stale.load_from(SCRATCH)
    DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
    if stale.values["render_scale"] != GraphicsSettings.DEFAULTS["render_scale"]:
        problems.append("a settings file of an older version was taken as current")

    var viewport: SubViewport = SubViewport.new()
    var expected: Array = [
        [Viewport.MSAA_DISABLED, false, Viewport.SCREEN_SPACE_AA_DISABLED],
        [Viewport.MSAA_2X, false, Viewport.SCREEN_SPACE_AA_DISABLED],
        [Viewport.MSAA_4X, false, Viewport.SCREEN_SPACE_AA_DISABLED],
        [Viewport.MSAA_DISABLED, true, Viewport.SCREEN_SPACE_AA_DISABLED],
        [Viewport.MSAA_DISABLED, false, Viewport.SCREEN_SPACE_AA_FXAA],
    ]
    for mode: int in expected.size():
        loaded.set_value("anti_aliasing", mode)
        loaded.apply_to_viewport(viewport)
        var want: Array = expected[mode] as Array
        if viewport.msaa_3d != want[0] or viewport.use_taa != want[1] or viewport.screen_space_aa != want[2]:
            problems.append("anti-aliasing %s read back as msaa %d taa %s ssaa %d" % [
                GraphicsSettings.ANTI_ALIASING[mode], viewport.msaa_3d, viewport.use_taa, viewport.screen_space_aa])
    loaded.set_value("render_scale", 0.6)
    loaded.set_value("upscaler", 1)
    loaded.apply_to_viewport(viewport)
    if not is_equal_approx(viewport.scaling_3d_scale, 0.6) or viewport.scaling_3d_mode != Viewport.SCALING_3D_MODE_FSR2:
        problems.append("scale 0.6 with FSR 2 read back as %.2f mode %d" % [viewport.scaling_3d_scale, viewport.scaling_3d_mode])
    # Automatic scale: a 1080-row window draws at 1:1 and bilinear (FSR 2 at 1:1 is 2 ms for
    # nothing); a 2234-row fullscreen retina window draws at 1440 rows, upscaled.
    if not is_equal_approx(GraphicsSettings.scale_for(1080.0), 1.0):
        problems.append("auto scale for 1080 rows is %.3f" % GraphicsSettings.scale_for(1080.0))
    if absf(GraphicsSettings.scale_for(2234.0) - 1440.0 / 2234.0) > 0.001:
        problems.append("auto scale for 2234 rows is %.3f" % GraphicsSettings.scale_for(2234.0))
    loaded.set_value("render_scale", 0.0)
    viewport.size = Vector2i(1920, 1080)
    loaded.apply_to_viewport(viewport)
    if not is_equal_approx(viewport.scaling_3d_scale, 1.0) or viewport.scaling_3d_mode != Viewport.SCALING_3D_MODE_BILINEAR:
        problems.append("auto scale on a 1080-row viewport read back as %.2f mode %d" % [viewport.scaling_3d_scale, viewport.scaling_3d_mode])
    viewport.free()
    if not problems.is_empty():
        return fail("; ".join(problems), problems.size())
    return ok("%d settings round-trip; 5 anti-aliasing modes, the scale and the upscaler read back off a viewport" % settings.values.size(), settings.values.size())
