class_name PlaySplit
extends Node
## Two drivers in one window: the left half on WASD, the right half on the arrow keys.
##
## PLAN §0.12 names splitscreen as the cheapest honest test of everything multi-actor that does not
## need a network: two actors, two frames, two solvers, and a person able to drive one into the
## other. This is its first step and it is only the window: a second vehicle with its own solver,
## its own half of the keyboard (`DriveKeys`), its own chase camera and its own readout.
##
## **What it does not do yet: the two vehicles pass through each other.** Actor-to-actor contact
## does not exist in the solver — `contacters` is unparsed and each `RorSolver` knows only its own
## nodes — and is the next step, with islands after it.
##
## Each solver already steps on a worker of its own (`step_async`), so two vehicles are already two
## cores: SMP across actors, which PLAN §0.12 schedules with islands, costs nothing to start with.
##
## The 3D picture moves out of the root viewport into two `SubViewport`s that share its world, one
## per half, each with a copy of the session camera. The copy shares the camera's attributes
## resource, so exposure follows the weather in both halves; the session camera stops being
## current, so the root viewport no longer draws the scene a third time underneath.

## How far to the right of the first vehicle the second one starts, in metres.
const SIDE_BY_SIDE_M: float = 4.5
const HUD_MARGIN_PX: int = 12
const HUD_FONT_PX: int = 14

var first: PlayDrive = null
var second: PlayDrive = null

var _views: Array[PlayCamera] = []
var _cameras: Array[Camera3D] = []
var _ports: Array[SubViewport] = []
var _labels: Array[Label] = []


## Builds the second vehicle from `vehicle_spec` (`<mod dir>:<truck file>`, as `--vehicle` takes
## it), hands each driver their half of the keyboard and splits the picture. Returns "" on success.
func setup(world: Node3D, camera: Camera3D, driver: PlayDrive, vehicle_spec: String) -> String:
    var parts: PackedStringArray = vehicle_spec.split(":")
    if parts.size() != 2:
        return "splitscreen needs --vehicle <mod dir>:<truck file>, got '%s'" % vehicle_spec
    var mod_dir: String = parts[0]
    if not mod_dir.is_absolute_path():
        mod_dir = SourceScan.repo_root().path_join(mod_dir)
    var built: Dictionary = VehicleBuilder.build(mod_dir, parts[1])
    if (built.get("error", "") as String) != "":
        return "the second vehicle cannot be built: %s" % built["error"]
    world.add_child(built["root"] as Node3D)
    var other: PlayDrive = PlayDrive.new()
    var error: String = other.setup(built)
    if error != "":
        return "the second vehicle cannot be driven: %s" % error
    first = driver
    second = other
    first.keys = DriveKeys.SPLIT_LEFT
    second.keys = DriveKeys.SPLIT_RIGHT
    place_second()
    _build_halves(camera)
    print(DriveKeys.help(DriveKeys.SPLIT_LEFT, "LEFT "))
    print(DriveKeys.help(DriveKeys.SPLIT_RIGHT, "RIGHT"))
    return ""


## Stands the second vehicle beside the first, facing the same way, and makes that its spawn.
func place_second() -> void:
    if first == null or second == null:
        return
    var right: Vector3 = Basis(Vector3.UP, first.spawn_heading) * Vector3.RIGHT
    second.spawn = first.spawn + right * SIDE_BY_SIDE_M
    second.spawn_heading = first.spawn_heading
    second.respawn()


## The map handed the first vehicle its terrain: the second takes the same ground, gravity and
## solid scenery, and is put down beside the first.
func hand_terrain(wanted: RorTerrain, data: Object) -> void:
    if second == null:
        return
    var right: Vector3 = Basis(Vector3.UP, first.spawn_heading) * Vector3.RIGHT
    second.spawn = first.spawn + right * SIDE_BY_SIDE_M
    second.spawn_heading = first.spawn_heading
    second.solver.set_gravity(Vector3(0.0, wanted.gravity(), 0.0))
    # Taking the terrain puts the rig down at its spawn, which is why the spawn is set first.
    var error: String = second.use_terrain(data)
    if error != "":
        printerr("PLAY  the second solver could not take the terrain: " + error)
        return
    RorObjectCollision.apply(wanted, second.solver)


## The first vehicle changed (the menu swapped it): the new one drives the left half.
func replace_first(driver: PlayDrive) -> void:
    first = driver
    first.keys = DriveKeys.SPLIT_LEFT


func begin(delta: float) -> void:
    if second != null:
        second.begin(delta)


## After both drivers have finished their frame: the second's pose, both cameras, both readouts.
func finish(delta: float, refresh_hud: bool) -> void:
    if second != null:
        second.finish()
    var drivers: Array[PlayDrive] = [first, second]
    var half_width: float = get_viewport().get_visible_rect().size.x * 0.5
    for half: int in _views.size():
        _views[half].follow(drivers[half], delta)
        _labels[half].position.x = HUD_MARGIN_PX + half_width * half
        if refresh_hud and drivers[half] != null:
            _labels[half].text = drivers[half].hud_line()


## A key goes to whichever driver owns it. Returns whether one did.
func on_key(keycode: Key) -> bool:
    if first != null and first.on_key(keycode):
        return true
    return second != null and second.on_key(keycode)


## The graphics options the session applied to the root viewport, carried to both halves: render
## scale, upscaler and anti-aliasing are per viewport in Godot, and the halves are the viewports
## that now draw.
func copy_graphics(from: Viewport) -> void:
    for port: SubViewport in _ports:
        port.scaling_3d_mode = from.scaling_3d_mode
        port.scaling_3d_scale = from.scaling_3d_scale
        port.msaa_3d = from.msaa_3d
        port.screen_space_aa = from.screen_space_aa
        port.use_taa = from.use_taa


func _build_halves(camera: Camera3D) -> void:
    var layer: CanvasLayer = CanvasLayer.new()
    layer.name = "Split"
    # Under the session's own HUD and panels, which are on the default layer.
    layer.layer = -1
    var row: HBoxContainer = HBoxContainer.new()
    row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    row.add_theme_constant_override("separation", 2)
    layer.add_child(row)
    add_child(layer)
    # The readouts sit over the picture on a layer of their own, placed by half-width rather than
    # inside the containers, which lay out what they hold.
    var overlay: CanvasLayer = CanvasLayer.new()
    overlay.name = "SplitHud"
    add_child(overlay)
    var world: World3D = camera.get_viewport().find_world_3d()
    for half: int in 2:
        var holder: SubViewportContainer = SubViewportContainer.new()
        holder.stretch = true
        holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
        row.add_child(holder)
        var port: SubViewport = SubViewport.new()
        port.world_3d = world
        port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
        holder.add_child(port)
        var eye: Camera3D = camera.duplicate() as Camera3D
        port.add_child(eye)
        eye.current = true
        var view: PlayCamera = PlayCamera.new()
        view.setup(eye)
        view.set_mode(PlayCamera.Mode.CHASE)
        var label: Label = Label.new()
        label.position = Vector2(HUD_MARGIN_PX, HUD_MARGIN_PX)
        label.add_theme_font_size_override("font_size", HUD_FONT_PX)
        label.add_theme_color_override("font_shadow_color", Color.BLACK)
        label.add_theme_constant_override("shadow_offset_x", 1)
        label.add_theme_constant_override("shadow_offset_y", 1)
        overlay.add_child(label)
        _ports.append(port)
        _cameras.append(eye)
        _views.append(view)
        _labels.append(label)
    camera.current = false
    copy_graphics(camera.get_viewport())
