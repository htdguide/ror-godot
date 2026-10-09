class_name PlayHud
extends RefCounted
## The line of numbers across the top of a session window: what is rendering it, how fast, and how
## much it is drawing.
##
## Split out of `PlayRig` when that file went over the source cap. It is a real seam — nothing
## here knows anything about driving, and everything it reports it reads from the engine — and it
## is where the measurements quoted in PLAN 0.13 came from: a session on La Paz reporting 18.79 ms
## at 135 draw calls is this text.
##
## **What the keys are lives here too**, for the same reason: the footer under the readout and the
## help printed at startup are the same list, and they had drifted apart once already.


## Where the readout sits and how big it is.
const MARGIN_PX: int = 12
const FONT_PX: int = 16


static func build(into: Node) -> Label:
    var layer: CanvasLayer = CanvasLayer.new()
    layer.name = "HUD"
    var label: Label = Label.new()
    label.name = "HudText"
    label.position = Vector2(MARGIN_PX, MARGIN_PX)
    label.add_theme_font_size_override("font_size", FONT_PX)
    label.add_theme_color_override("font_shadow_color", Color.BLACK)
    label.add_theme_constant_override("shadow_offset_x", 1)
    label.add_theme_constant_override("shadow_offset_y", 1)
    layer.add_child(label)
    into.add_child(layer)
    return label


static func text(viewport: Viewport, weather: String, footer: String) -> String:
    var viewport_rid: RID = viewport.get_viewport_rid()
    return (
        "%s | %s | %s | %s\n%.1f fps  %.2f ms\ndraw calls %d  primitives %d\nvideo %.0f MB  texture %.0f MB\n%s"
        % [
            BuildProfile.label(),
            RenderingServer.get_video_adapter_name(),
            RenderingServer.get_current_rendering_driver_name(),
            weather,
            Performance.get_monitor(Performance.TIME_FPS),
            Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
            RenderingServer.viewport_get_render_info(
                viewport_rid,
                RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
                RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
            ),
            RenderingServer.viewport_get_render_info(
                viewport_rid,
                RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
                RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME
            ),
            Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
            Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
            footer,
        ]
    )


## The controls, under the readout.
static func footer(drive: PlayDrive) -> String:
    var keys: String = (
        "click to look  WASD move  Q/E down/up  Shift boost  F1 hud  F2 weather"
        + "  F3 shadows  F4 sun  F8 collision  P shot  Esc settings"
    )
    if drive == null:
        return keys
    return drive.hud_line() + "\n" + keys + "  F5/F6 chase/free"


## The same controls, spelled out once at startup where a terminal will keep them.
static func print_help(drive: PlayDrive) -> void:
    print(
        "PLAY  click to look with the mouse, Esc releases it, Esc again opens the settings\n"
        + "PLAY  W A S D move, Q/E down/up, hold Shift to boost\n"
        + "PLAY  F1 toggle HUD, F2 cycle weather, F3 toggle shadows, F4 toggle the sun\n"
        + "PLAY  F8 show what the terrain is solid as: a box with nothing in it is geometry"
        + " that is missing, and drawn geometry with no box is something you drive through\n"
        + "PLAY  Esc or M open the settings: weather, gravity, sun, sky, fog, distance\n"
        + "PLAY  P save a screenshot and a .json beside it saying where it was taken from"
    )
    if drive != null:
        print(DriveCfg.HELP)
