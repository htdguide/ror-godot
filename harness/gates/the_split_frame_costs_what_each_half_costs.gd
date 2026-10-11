extends GateBase
## What a splitscreen frame costs against a one-view frame of the same scene, and what each
## feature costs once the scene is drawn twice. A measurement for deciding what to change; it
## reports and does not judge.
##
## "Splitscreen is slow" is a sentence from a session (2026-10-11) about a number nobody had taken.
## `PlaySplit` draws the world through two `SubViewport`s, half the width each and the full height,
## sharing one world. Together they cover the pixels one view would, so whatever splitscreen costs
## beyond one view is the work Godot does per viewport rather than per pixel: culling, the
## directional shadow cascades, the sky's radiance, screen-space passes, volumetric fog's grid.
## This finds out which.
##
## The scene is `the_frame_costs_what_each_feature_costs`'s: La Paz with its objects, roads, sea
## and grass and the hero, golden dusk under marched clouds, at the dev Mac's fullscreen pixel
## count. It is timed once through the container's own view, then through two half views with the
## container's own 3D switched off — as `PlaySplit` does to the root viewport — then split again with
## each suspect switched off in turn. Godot's per-viewport GPU timer reads zero on Metal, so the
## figures are wall time with VSync off.
##
## **What it could not see.** The window's split cost twice one view, and the cause was the root
## viewport drawing the world a third time underneath the halves although its camera was switched
## off (26.1 ms to 15.6 with `disable_3d`, measured with `--frame-log`). A gate container's viewport
## does stop drawing when its camera is switched off — the trial was here and read +0.0 — so this
## gate measures the halves and what they cost, and the window's own fault is held by the code that
## fixed it, not by this table.

const MAP: String = "lapaz"
const PRESET: String = "hero_3q"
const WEATHER: String = "golden_dusk"
const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const WARM_FRAMES: int = 30
const MEASURED_FRAMES: int = 40
## 1920x1080 times this is the dev Mac's fullscreen pixel count (3456x2234).
const RETINA_SCALE: float = 1.9
## Where the second half looks from: the second vehicle's chase camera, beside the first.
const SECOND_VIEW_OFFSET: Vector3 = Vector3(-4.5, 0.0, 0.0)

var _harness: Node
var _halves: Array[SubViewport] = []


static func meta() -> Dictionary:
    return {
        "name": "the_split_frame_costs_what_each_half_costs",
        "proves": "the full scene's frame time drawn through one view and through two half views, and what each per-view feature costs in the split, as a table",
        "builds_on": ["the_frame_costs_what_each_feature_costs"],
        "oracle": GateBase.ORACLE_NONE,
        "threshold": "none: a report. Fails only if the scene does not render",
        "why": (
            "splitscreen was reported slow and never measured; two half views cover the pixels of"
            + " one, so its extra cost is per-view work, and which per-view work decides what to"
            + " change."
        ),
        "budget_s": 240.0,
        "needs_gpu": true,
        "measured_is_wall_clock": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    _harness = harness
    var loaded: Dictionary = RorTerrainLibrary.load_named(MAP)
    if (loaded.get("error", "") as String) != "":
        return ok("skipped: %s is not in this checkout" % MAP, 0)
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain
    var err: String = harness.setup_for(PRESET, WEATHER)
    if err != "":
        return fail(err)
    var ground: Node3D = TerrainWorld.create()
    if ground == null:
        return ok("skipped: Terrain3D is not installed", 0)
    harness.world.add_child(ground)
    await harness.advance_frames(2, "static", "terrain")
    var built: String = harness.terrain.populate(ground, terrain)
    if built != "":
        return fail(built)
    var blockout: Node3D = harness.world.get_node_or_null(^"Ground") as Node3D
    if blockout != null:
        blockout.visible = false
    var objects: Node3D = RorObjects.build(terrain)
    harness.world.add_child(objects)
    harness.world.add_child(RorProceduralRoad.build(terrain))
    harness.world.add_child(RorWater.build(terrain, -1.0))
    var vegetation: RorVegetation = RorVegetation.new()
    if vegetation.setup(terrain) == "":
        harness.world.add_child(vegetation)
        vegetation.focus_on(terrain.start_position())
        vegetation.fill()
    else:
        vegetation.free()
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present", 0)
    for i: int in 2:
        var result: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
        if (result.get("error", "") as String) != "":
            return fail(result["error"] as String)
        var vehicle: Node3D = result["root"] as Node3D
        harness.world.add_child(vehicle)
        vehicle.position = terrain.start_position() + Vector3(0.0, 1.0, 0.0) + SECOND_VIEW_OFFSET * i
    var target: Vector3 = terrain.start_position() + Vector3(0.0, 1.0, 0.0)
    harness.camera.look_at_from_position(
        target + Vector3(4.2, 1.9, 4.6), target + Vector3(0.0, 0.9, 0.0), Vector3.UP
    )
    var weather: Dictionary = WeatherCfg.get_preset(WEATHER).duplicate()
    BlockoutWorld.apply_weather(harness.world, weather, true)

    var view: Viewport = harness.render_viewport()
    var env: Environment = (harness.world.get_node(^"WorldEnvironment") as WorldEnvironment).environment
    var sun: DirectionalLight3D = harness.world.get_node(^"Sun") as DirectionalLight3D
    var fill: DirectionalLight3D = harness.world.get_node_or_null(^"Fill") as DirectionalLight3D
    var was_vsync: int = DisplayServer.window_get_vsync_mode()
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    view.scaling_3d_scale = RETINA_SCALE

    var rows: PackedStringArray = PackedStringArray()
    var one: float = await _measure()
    rows.append("one view %.1f ms" % one)

    _build_halves(view, target)
    harness.camera.current = false
    view.disable_3d = true
    var base: float = await _measure()
    rows.append("two half views %.1f ms (%+.1f over one)" % [base, base - one])
    var trials: Array = [
        ["sun shadows off", func() -> void: sun.shadow_enabled = false,
            func() -> void: sun.shadow_enabled = true],
        ["fill shadows off", func() -> void: _set_shadow(fill, false),
            func() -> void: _set_shadow(fill, true)],
        ["clouds off", func() -> void: BlockoutWorld.apply_weather(harness.world, weather, false),
            func() -> void: BlockoutWorld.apply_weather(harness.world, weather, true)],
        ["sky radiance incremental", func() -> void: env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL,
            func() -> void: env.sky.process_mode = Sky.PROCESS_MODE_QUALITY],
        ["ssao off", func() -> void: env.ssao_enabled = false, func() -> void: env.ssao_enabled = true],
        ["glow off", func() -> void: env.glow_enabled = false, func() -> void: env.glow_enabled = true],
        ["volumetric fog off", func() -> void: env.volumetric_fog_enabled = false,
            func() -> void: env.volumetric_fog_enabled = bool(weather.get("volumetric", false))],
        ["grass hidden", func() -> void: _set_visible(vegetation, false),
            func() -> void: _set_visible(vegetation, true)],
        ["objects hidden", func() -> void: objects.visible = false,
            func() -> void: objects.visible = true],
        ["halves at 1440 rows + FSR 2", func() -> void: _scale_halves(0.64 * RETINA_SCALE, true),
            func() -> void: _scale_halves(RETINA_SCALE, false)],
        ["halves at 1080 rows + FSR 2", func() -> void: _scale_halves(0.48 * RETINA_SCALE, true),
            func() -> void: _scale_halves(RETINA_SCALE, false)],
        ["second half off", func() -> void:
            _halves[1].render_target_update_mode = SubViewport.UPDATE_DISABLED,
            func() -> void: _halves[1].render_target_update_mode = SubViewport.UPDATE_ALWAYS],
    ]
    for trial: Array in trials:
        (trial[1] as Callable).call()
        var measured: float = await _measure()
        (trial[2] as Callable).call()
        rows.append("%s %.1f ms (%+.1f)" % [trial[0], measured, measured - base])
    for half: SubViewport in _halves:
        half.queue_free()
    view.disable_3d = false
    harness.camera.current = true
    view.scaling_3d_scale = 1.0
    DisplayServer.window_set_vsync_mode(was_vsync as DisplayServer.VSyncMode)
    for row: String in rows:
        print("HARNESS_COST " + row)
    return ok("; ".join(rows), base)


## Two views of the container's world, each half its width and its full height, the way
## `PlaySplit` draws a window: one looking at the first vehicle, one at the second.
func _build_halves(view: Viewport, target: Vector3) -> void:
    var size: Vector2i = Vector2i(view.get_visible_rect().size)
    for i: int in 2:
        var half: SubViewport = SubViewport.new()
        half.size = Vector2i(size.x / 2, size.y)
        half.world_3d = view.find_world_3d()
        half.render_target_update_mode = SubViewport.UPDATE_ALWAYS
        half.scaling_3d_scale = RETINA_SCALE
        _harness.world.add_child(half)
        var eye: Camera3D = _harness.camera.duplicate() as Camera3D
        half.add_child(eye)
        var aim: Vector3 = target + SECOND_VIEW_OFFSET * i
        eye.look_at_from_position(aim + Vector3(0.0, 2.0, 7.0), aim + Vector3(0.0, 0.8, 0.0), Vector3.UP)
        eye.current = true
        _halves.append(half)


func _scale_halves(scale: float, fsr: bool) -> void:
    for half: SubViewport in _halves:
        half.scaling_3d_scale = scale
        half.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if fsr else Viewport.SCALING_3D_MODE_BILINEAR


func _set_shadow(light: DirectionalLight3D, on: bool) -> void:
    if light != null:
        light.shadow_enabled = on


func _set_visible(node: Node3D, on: bool) -> void:
    if node != null and is_instance_valid(node):
        node.visible = on


## The median wall time of a frame.
func _measure() -> float:
    await _harness.advance_frames(WARM_FRAMES, "static", "warm")
    var wall: PackedFloat32Array = PackedFloat32Array()
    for _frame: int in MEASURED_FRAMES:
        var began: int = Time.get_ticks_usec()
        await _harness.advance_frames(1, "static", "measure")
        wall.append(float(Time.get_ticks_usec() - began) / 1000.0)
    wall.sort()
    return wall[wall.size() / 2]
