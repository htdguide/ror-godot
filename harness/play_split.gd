class_name PlaySplit
extends Node
## Two drivers in one window: the left half on WASD, the right half on the arrow keys.
##
## PLAN §0.12 names splitscreen as the cheapest honest test of everything multi-actor that does not
## need a network: two actors, two frames, two solvers, and a person able to drive one into the
## other. Here that is a second vehicle with its own solver, its own half of the keyboard
## (`DriveKeys`), its own chase camera and its own readout.
##
## **The two vehicles collide**: both are stepped by one `RorWorld`, which puts them in one island
## when the causality bound says they could touch this frame and resolves upstream's inter-actor
## contact between them, and otherwise steps each on its own worker — two cores while apart.
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

## Steps both vehicles together, and puts them in contact when they are near: see `RorWorld`.
var _world: RorWorld = RorWorld.new()
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
    _join_world()
    place_second()
    _build_halves(camera)
    print(DriveKeys.help(DriveKeys.SPLIT_LEFT, "LEFT "))
    print(DriveKeys.help(DriveKeys.SPLIT_RIGHT, "RIGHT"))
    return ""


## Stands the second vehicle beside the first, facing the same way, and makes that its spawn.
func place_second() -> void:
    if first == null or second == null:
        return
    _spawn_beside_first()
    second.respawn()


## The map handed the first vehicle its terrain: the second takes the same ground, gravity and
## solid scenery, and is put down beside the first.
func hand_terrain(wanted: RorTerrain, data: Object) -> void:
    if second == null:
        return
    _spawn_beside_first()
    second.solver.set_gravity(Vector3(0.0, wanted.gravity(), 0.0))
    # Taking the terrain puts the rig down at its spawn, which is why the spawn is set first.
    var error: String = second.use_terrain(data)
    if error != "":
        printerr("PLAY  the second solver could not take the terrain: " + error)
        return
    RorObjectCollision.apply(wanted, second.solver)


## The second vehicle's spawn: beside the first along the first's own sideways axis, read off its
## pose. The spawn heading alone was not enough: a map's start states a position, the heading
## stays zero, and on La Paz "to the right of heading zero" put the second truck behind the first.
func _spawn_beside_first() -> void:
    var side: Vector3 = Vector3(first.frame.basis.x.x, 0.0, first.frame.basis.x.z)
    if side.length() < 0.1:
        side = Basis(Vector3.UP, first.spawn_heading) * Vector3.RIGHT
    second.spawn = first.spawn + side.normalized() * SIDE_BY_SIDE_M
    second.spawn_heading = first.spawn_heading


## The first vehicle changed (the menu swapped it): the new one drives the left half.
func replace_first(driver: PlayDrive) -> void:
    first = driver
    first.keys = DriveKeys.SPLIT_LEFT
    _join_world()


## The second driver's controls, then both vehicles stepped together. The session has already
## called the first driver's `begin`, which worked out this frame's substeps and stepped nothing.
func begin(delta: float) -> void:
    if second == null:
        return
    second.begin(delta)
    _world.step(1.0 / DriveCfg.SUBSTEP_HZ, first.substeps_wanted)


## After both drivers have finished their frame: the second's pose, both cameras, both readouts.
func finish(delta: float, refresh_hud: bool) -> void:
    if second != null:
        second.finish()
    var drivers: Array[PlayDrive] = [first, second]
    var half_width: float = get_viewport().get_visible_rect().size.x * 0.5
    for half: int in _views.size():
        _views[half].follow(drivers[half], delta)
        # At the foot of each half: the session's own readout owns the top-left corner.
        _labels[half].position = Vector2(
            HUD_MARGIN_PX + half_width * half,
            get_viewport().get_visible_rect().size.y - _labels[half].size.y - HUD_MARGIN_PX
        )
        if refresh_hud and drivers[half] != null:
            _labels[half].text = drivers[half].hud_line()


## The left half's viewport, for a readout of draw calls: the root viewport draws no 3D in a split.
func left_view() -> Viewport:
    return _ports[0] if not _ports.is_empty() else get_viewport()


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
    # **And the root viewport stops drawing 3D at all.** Switching its camera off was supposed to
    # be enough and was not: it went on rendering the world a third time under the two halves.
    # Measured on La Paz at 1118 rows, split went from 26.1 ms a frame to 15.6, against 13.1 for
    # one view. The world itself lives on — the halves hold it — and the root keeps the 2D on top.
    camera.get_viewport().disable_3d = true
    copy_graphics(camera.get_viewport())


## Both vehicles in one world, stepped by it rather than by themselves.
func _join_world() -> void:
    if first == null or second == null:
        return
    _world.clear()
    for driver: PlayDrive in [first, second]:
        driver.world_stepped = true
        driver.world = _world
        _world.add_solver(driver.solver as RorSolver)
