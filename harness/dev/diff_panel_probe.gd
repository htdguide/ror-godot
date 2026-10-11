extends SceneTree
## Renders the differential panel over a flat backdrop with the hero driving a turn, and saves it:
## the panel's look checked without a person at the keyboard. Run with a window (not --headless).

var _solver: RefCounted
var _frames: int = 0
var _out: String = ""


func _init() -> void:
    _out = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "/tmp/diff_panel.png"
    var rig: Dictionary = RigBuilder.from_file(ProjectSettings.globalize_path("res://assets/mods/ChevyS1023"), "S10offroad.truck", 0.02)
    _solver = rig["solver"] as RefCounted
    _solver.set_ground(0.0, true)
    var back: ColorRect = ColorRect.new()
    back.color = Color(0.42, 0.55, 0.62)
    back.size = Vector2(1280, 720)
    var layer: CanvasLayer = CanvasLayer.new()
    var hud: Label = Label.new()
    layer.add_child(hud)
    root.add_child(back)
    root.add_child(layer)
    DiffPanel.attach(hud, func() -> RefCounted: return _solver)
    _solver.start_engine()
    _solver.set_gear_selector(1)
    _solver.set_throttle(0.4)
    _solver.set_steer_command(DriveCfg.steer_command(1.0))


func _process(_delta: float) -> bool:
    _solver.step(1.0 / 2000.0, 33)
    _frames += 1
    if _frames == 100:
        _solver.toggle_wheel_differentials()
    if _frames == 160:
        root.get_texture().get_image().save_png(_out)
        return true
    return false
