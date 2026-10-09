class_name GraphicsSettings
extends RefCounted
## The graphics options a person can set, saved between runs and applied to the window and the
## viewport. Every row here is wired to something the renderer does; nothing decorative.
##
## Kept in `user://settings.cfg` so a production build remembers them, and applied once at start
## and again whenever a row moves. The weather panel owns what the scene looks like; this owns
## what the machine spends on drawing it.

const FILE: String = "user://settings.cfg"
const SECTION: String = "graphics"

const WINDOW_MODES: PackedStringArray = ["Windowed", "Fullscreen"]
const UPSCALERS: PackedStringArray = ["Bilinear", "FSR 2"]
const ANTI_ALIASING: PackedStringArray = ["Off", "MSAA 2x", "MSAA 4x", "TAA", "FXAA"]
const SHADOW_QUALITY: PackedStringArray = ["Low", "Medium", "High", "Ultra"]
const SHADOW_ATLAS: PackedInt32Array = [2048, 4096, 8192, 16384]
## The fill light's shadow is a second shadow pass; it comes with High and above.
const FILL_SHADOWS_FROM: int = 2
## How finely the clouds are marched: steps along the ray and toward the sun. Measured at the
## dev Mac's fullscreen pixel count, High costs 8.8 ms of a 37 ms frame and Medium 2.5 and 3.9 ms
## less than that (`the_frame_costs_what_each_feature_costs`).
const CLOUD_QUALITY: PackedStringArray = ["Low", "Medium", "High"]
const CLOUD_STEPS: PackedInt32Array = [12, 20, 28]
const CLOUD_LIGHT_STEPS: PackedInt32Array = [2, 2, 4]
## A render scale of 0 is automatic: the 3D image is drawn with at most this many rows and
## upscaled to the window. A fullscreen retina window is 2234 rows and 3.7 times the pixels of
## 1080p; drawn at 1440 rows with FSR 2 the full scene went from 37 ms to 21 ms.
const AUTO_ROWS: float = 1440.0

## The defaults: what a fresh install draws with. Measured, not guessed: the first defaults
## put the shadow atlas at 8192 and TAA on, which were 5.6 and 2.5 ms a frame for nothing a
## person had asked for.
const DEFAULTS: Dictionary = {
    "version": 2,
    "window_mode": 0, "vsync": true, "max_fps": 0, "render_scale": 0.0, "upscaler": 1,
    "anti_aliasing": 0, "shadow_quality": 1, "shadows": true, "cloud_quality": 1,
    "view_distance_m": 14000.0, "grass_distance_m": 220.0,
}

var values: Dictionary = DEFAULTS.duplicate()


## Reads the saved settings over the defaults. Unknown keys are dropped, missing ones defaulted,
## so a settings file from an older build still loads.
func load_from(path: String = FILE) -> void:
    values = DEFAULTS.duplicate()
    var config: ConfigFile = ConfigFile.new()
    if config.load(path) != OK:
        return
    # A file from before the defaults were measured keeps its 8192 atlas and its TAA; the
    # version says which defaults it was written over, and an older one starts again.
    if int(config.get_value(SECTION, "version", 0)) != int(DEFAULTS["version"]):
        return
    for key: String in DEFAULTS:
        if config.has_section_key(SECTION, key):
            values[key] = config.get_value(SECTION, key)


func save_to(path: String = FILE) -> Error:
    var config: ConfigFile = ConfigFile.new()
    for key: String in values:
        config.set_value(SECTION, key, values[key])
    return config.save(path)


func set_value(key: String, value: Variant) -> void:
    values[key] = value


## Puts every setting onto the viewport, the window and the engine. `world` may be null; the
## distances are applied to it when it is not.
func apply(viewport: Viewport, world: Node3D = null, vegetation: RorVegetation = null) -> void:
    apply_to_viewport(viewport)
    if DisplayServer.get_name() != "headless":
        DisplayServer.window_set_mode(
            DisplayServer.WINDOW_MODE_FULLSCREEN if int(values["window_mode"]) == 1
            else DisplayServer.WINDOW_MODE_WINDOWED
        )
        DisplayServer.window_set_vsync_mode(
            DisplayServer.VSYNC_ENABLED if bool(values["vsync"]) else DisplayServer.VSYNC_DISABLED
        )
    Engine.max_fps = int(values["max_fps"])
    RenderingServer.directional_shadow_atlas_set_size(
        SHADOW_ATLAS[clampi(int(values["shadow_quality"]), 0, SHADOW_ATLAS.size() - 1)], true
    )
    if world != null:
        SceneryRange.set_draw_distance(world, float(values["view_distance_m"]))
        var sun: DirectionalLight3D = world.get_node_or_null(^"Sun") as DirectionalLight3D
        if sun != null:
            sun.shadow_enabled = bool(values["shadows"])
        var fill: DirectionalLight3D = world.get_node_or_null(^"Fill") as DirectionalLight3D
        if fill != null:
            fill.shadow_enabled = bool(values["shadows"]) and int(values["shadow_quality"]) >= FILL_SHADOWS_FROM
        var holder: WorldEnvironment = world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
        if holder != null and holder.environment != null:
            apply_clouds(holder.environment)
    if vegetation != null:
        vegetation.set_range(float(values["grass_distance_m"]))


## The cloud march, onto a sky. On its own because a weather change rebuilds the sky and has to
## put this back.
func apply_clouds(environment: Environment) -> void:
    var quality: int = clampi(int(values["cloud_quality"]), 0, CLOUD_STEPS.size() - 1)
    SkyClouds.set_parameter(environment, "steps", CLOUD_STEPS[quality])
    SkyClouds.set_parameter(environment, "light_steps", CLOUD_LIGHT_STEPS[quality])


## The render scale a viewport gets: the stated one, or for 0 the automatic one for its height.
func effective_scale(viewport: Viewport) -> float:
    var stated: float = float(values["render_scale"])
    if stated > 0.0:
        return clampf(stated, 0.25, 2.0)
    return scale_for(viewport.get_visible_rect().size.y)


static func scale_for(rows: float) -> float:
    return clampf(minf(1.0, AUTO_ROWS / maxf(rows, 1.0)), 0.25, 1.0)


## The viewport's share, on its own so a gate can hold it on a viewport of its own.
func apply_to_viewport(viewport: Viewport) -> void:
    var scale: float = effective_scale(viewport)
    viewport.scaling_3d_scale = scale
    # FSR 2 at 1:1 is 2 ms of work for nothing to upscale; it goes on only when there is.
    viewport.scaling_3d_mode = (
        Viewport.SCALING_3D_MODE_FSR2 if int(values["upscaler"]) == 1 and scale < 1.0
        else Viewport.SCALING_3D_MODE_BILINEAR
    )
    var aa: int = int(values["anti_aliasing"])
    viewport.msaa_3d = (
        Viewport.MSAA_2X if aa == 1 else Viewport.MSAA_4X if aa == 2 else Viewport.MSAA_DISABLED
    )
    viewport.use_taa = aa == 3
    viewport.screen_space_aa = (
        Viewport.SCREEN_SPACE_AA_FXAA if aa == 4 else Viewport.SCREEN_SPACE_AA_DISABLED
    )


## The rows, into a panel. `on_change` is called after any row moves and the settings are saved.
func build_rows(rows: VBoxContainer, on_change: Callable) -> void:
    MenuWidgets.heading(rows, "Display")
    MenuWidgets.options(rows, "Window", WINDOW_MODES, int(values["window_mode"]),
        func(index: int) -> void: _moved("window_mode", index, on_change))
    MenuWidgets.check(rows, "VSync", bool(values["vsync"]),
        func(on: bool) -> void: _moved("vsync", on, on_change))
    MenuWidgets.slider(rows, "Max fps (0 = off)", 0.0, 240.0, float(values["max_fps"]),
        func(value: float) -> void: _moved("max_fps", int(value), on_change), "%.0f")
    MenuWidgets.heading(rows, "Rendering")
    MenuWidgets.slider(rows, "Render scale", 0.0, 2.0, float(values["render_scale"]),
        func(value: float) -> void: _moved("render_scale", value, on_change), "%.2f")
    MenuWidgets.note(rows, "0 is automatic: at most %d rows, upscaled" % int(AUTO_ROWS))
    MenuWidgets.options(rows, "Upscaler", UPSCALERS, int(values["upscaler"]),
        func(index: int) -> void: _moved("upscaler", index, on_change))
    MenuWidgets.options(rows, "Anti-aliasing", ANTI_ALIASING, int(values["anti_aliasing"]),
        func(index: int) -> void: _moved("anti_aliasing", index, on_change))
    MenuWidgets.options(rows, "Shadow quality", SHADOW_QUALITY, int(values["shadow_quality"]),
        func(index: int) -> void: _moved("shadow_quality", index, on_change))
    MenuWidgets.check(rows, "Shadows", bool(values["shadows"]),
        func(on: bool) -> void: _moved("shadows", on, on_change))
    MenuWidgets.options(rows, "Cloud quality", CLOUD_QUALITY, int(values["cloud_quality"]),
        func(index: int) -> void: _moved("cloud_quality", index, on_change))
    MenuWidgets.heading(rows, "Distance")
    MenuWidgets.slider(rows, "Scenery distance", 200.0, 14000.0, float(values["view_distance_m"]),
        func(value: float) -> void: _moved("view_distance_m", value, on_change), "%.0f m")
    MenuWidgets.slider(rows, "Grass distance", 0.0, 400.0, float(values["grass_distance_m"]),
        func(value: float) -> void: _moved("grass_distance_m", value, on_change), "%.0f m")


func _moved(key: String, value: Variant, on_change: Callable) -> void:
    values[key] = value
    save_to()
    if on_change.is_valid():
        on_change.call()
