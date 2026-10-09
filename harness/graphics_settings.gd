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

## The defaults: what a fresh install draws with.
const DEFAULTS: Dictionary = {
    "window_mode": 0, "vsync": true, "max_fps": 0, "render_scale": 1.0, "upscaler": 0,
    "anti_aliasing": 3, "shadow_quality": 2, "shadows": true, "view_distance_m": 14000.0,
    "grass_distance_m": 400.0,
}

var values: Dictionary = DEFAULTS.duplicate()


## Reads the saved settings over the defaults. Unknown keys are dropped, missing ones defaulted,
## so a settings file from an older build still loads.
func load_from(path: String = FILE) -> void:
    values = DEFAULTS.duplicate()
    var config: ConfigFile = ConfigFile.new()
    if config.load(path) != OK:
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
    if vegetation != null:
        vegetation.set_range(float(values["grass_distance_m"]))


## The viewport's share, on its own so a gate can hold it on a viewport of its own.
func apply_to_viewport(viewport: Viewport) -> void:
    viewport.scaling_3d_scale = clampf(float(values["render_scale"]), 0.25, 2.0)
    viewport.scaling_3d_mode = (
        Viewport.SCALING_3D_MODE_FSR2 if int(values["upscaler"]) == 1
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
    MenuWidgets.slider(rows, "Render scale", 0.5, 2.0, float(values["render_scale"]),
        func(value: float) -> void: _moved("render_scale", value, on_change), "%.2f")
    MenuWidgets.options(rows, "Upscaler", UPSCALERS, int(values["upscaler"]),
        func(index: int) -> void: _moved("upscaler", index, on_change))
    MenuWidgets.options(rows, "Anti-aliasing", ANTI_ALIASING, int(values["anti_aliasing"]),
        func(index: int) -> void: _moved("anti_aliasing", index, on_change))
    MenuWidgets.options(rows, "Shadow quality", SHADOW_QUALITY, int(values["shadow_quality"]),
        func(index: int) -> void: _moved("shadow_quality", index, on_change))
    MenuWidgets.check(rows, "Shadows", bool(values["shadows"]),
        func(on: bool) -> void: _moved("shadows", on, on_change))
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
