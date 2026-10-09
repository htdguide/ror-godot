extends GateBase
## What each feature of the full scene costs a frame, at the pixel count of a fullscreen retina
## window. A measurement for deciding what to spend; it reports and does not judge.
##
## "The fps on full screen is horrible" is a true sentence about a number this project had never
## taken: every frame-time gate ran at 1920x1080, and the dev Mac's screen is 3456x2234, 3.7 times
## the pixels. So the full scene — La Paz, its objects, roads, sea and grass, the hero, golden dusk
## under marched clouds — is drawn at a render scale that makes up the difference, and then each
## feature is switched off in turn and the frame timed again. The difference is the feature's
## cost, and the table is what the defaults are set from. Then the hero is driven for five
## seconds at full throttle with the chase camera on it and the grass following, the way a person
## sees the frame rate, once with everything on and once under the defaults, and the median and
## the worst frame of each are the last two rows.

const MAP: String = "lapaz"
const PRESET: String = "hero_3q"
const WEATHER: String = "golden_dusk"
const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const WARM_FRAMES: int = 30
const MEASURED_FRAMES: int = 40
## 1920x1080 times this is the dev Mac's fullscreen pixel count (3456x2234).
const RETINA_SCALE: float = 1.9
const DRIVE_SECONDS: float = 5.0
const FRAME_S: float = 1.0 / 60.0


static func meta() -> Dictionary:
    return {
        "name": "the_frame_costs_what_each_feature_costs",
        "proves": "the full scene's frame time at fullscreen-retina pixel count, and what each feature of it costs, as a table",
        "builds_on": ["a_full_scene_renders_inside_its_budget"],
        "oracle": GateBase.ORACLE_NONE,
        "threshold": "none: a report. Fails only if the scene does not render",
        "why": (
            "a frame budget is set from what things cost, and until this table existed every"
            + " cost in the renderer was a guess made at a third of the pixels a person sees."
        ),
        "budget_s": 240.0,
        "needs_gpu": true,
        "measured_is_wall_clock": true,
        "milestone": "M2",
    }


var _harness: Node


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
    var roads: Node3D = RorProceduralRoad.build(terrain)
    harness.world.add_child(roads)
    var water: Node3D = RorWater.build(terrain, -1.0)
    harness.world.add_child(water)
    var vegetation: RorVegetation = RorVegetation.new()
    if vegetation.setup(terrain) == "":
        harness.world.add_child(vegetation)
        vegetation.focus_on(terrain.start_position())
        vegetation.fill()
    else:
        vegetation.free()
        vegetation = null
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present", 0)
    var result: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (result.get("error", "") as String) != "":
        return fail(result["error"] as String)
    var vehicle: Node3D = result["root"] as Node3D
    harness.world.add_child(vehicle)
    vehicle.position = terrain.start_position() + Vector3(0.0, 1.0, 0.0)
    harness.camera.look_at_from_position(
        vehicle.position + Vector3(4.2, 1.9, 4.6), vehicle.position + Vector3(0.0, 0.9, 0.0), Vector3.UP
    )
    var weather: Dictionary = WeatherCfg.get_preset(WEATHER).duplicate()
    BlockoutWorld.apply_weather(harness.world, weather, true)

    var viewport: Viewport = harness.render_viewport()
    var env: Environment = (harness.world.get_node(^"WorldEnvironment") as WorldEnvironment).environment
    var sun: DirectionalLight3D = harness.world.get_node(^"Sun") as DirectionalLight3D
    var fill: DirectionalLight3D = harness.world.get_node_or_null(^"Fill") as DirectionalLight3D
    var was_vsync: int = DisplayServer.window_get_vsync_mode()
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    viewport.scaling_3d_scale = RETINA_SCALE
    var size: Vector2 = viewport.get_visible_rect().size * RETINA_SCALE

    var rows: PackedStringArray = PackedStringArray()
    var base: float = await _measure("baseline")
    rows.append("baseline %.1f ms at %dx%d" % [base, int(size.x), int(size.y)])
    var trials: Array = [
        ["render scale 1.0 (1920x1080)", func() -> void: viewport.scaling_3d_scale = 1.0,
            func() -> void: viewport.scaling_3d_scale = RETINA_SCALE],
        ["render scale 1.0 + FSR 2", func() -> void:
            viewport.scaling_3d_scale = 1.0
            viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2,
            func() -> void:
            viewport.scaling_3d_scale = RETINA_SCALE
            viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR],
        ["clouds off", func() -> void: BlockoutWorld.apply_weather(harness.world, weather, false),
            func() -> void: BlockoutWorld.apply_weather(harness.world, weather, true)],
        ["sky radiance incremental", func() -> void: env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL,
            func() -> void: env.sky.process_mode = Sky.PROCESS_MODE_QUALITY],
        ["sky radiance 64", func() -> void: env.sky.radiance_size = Sky.RADIANCE_SIZE_64,
            func() -> void: env.sky.radiance_size = RenderCfg.SKY_RADIANCE_SIZE as Sky.RadianceSize],
        ["ssao off", func() -> void: env.ssao_enabled = false, func() -> void: env.ssao_enabled = true],
        ["glow off", func() -> void: env.glow_enabled = false, func() -> void: env.glow_enabled = true],
        ["sun shadows off", func() -> void: sun.shadow_enabled = false, func() -> void: sun.shadow_enabled = true],
        ["fill shadows off", func() -> void:
            if fill != null:
                fill.shadow_enabled = false,
            func() -> void:
            if fill != null:
                fill.shadow_enabled = true],
        ["shadow atlas 2048", func() -> void: RenderingServer.directional_shadow_atlas_set_size(2048, true),
            func() -> void: RenderingServer.directional_shadow_atlas_set_size(4096, true)],
        ["shadow atlas 8192", func() -> void: RenderingServer.directional_shadow_atlas_set_size(8192, true),
            func() -> void: RenderingServer.directional_shadow_atlas_set_size(4096, true)],
        ["grass hidden", func() -> void:
            if vegetation != null:
                vegetation.visible = false,
            func() -> void:
            if vegetation != null:
                vegetation.visible = true],
        ["objects hidden", func() -> void: objects.visible = false, func() -> void: objects.visible = true],
        ["water hidden", func() -> void: water.visible = false, func() -> void: water.visible = true],
        ["vehicle hidden", func() -> void: vehicle.visible = false, func() -> void: vehicle.visible = true],
        ["terrain hidden", func() -> void: ground.visible = false, func() -> void: ground.visible = true],
        ["cloud steps 20", func() -> void: SkyClouds.set_parameter(env, "steps", 20),
            func() -> void: SkyClouds.set_parameter(env, "steps", RenderCfg.CLOUD_STEPS)],
        ["cloud steps 14", func() -> void: SkyClouds.set_parameter(env, "steps", 14),
            func() -> void: SkyClouds.set_parameter(env, "steps", RenderCfg.CLOUD_STEPS)],
        ["cloud light steps 2", func() -> void: SkyClouds.set_parameter(env, "light_steps", 2),
            func() -> void: SkyClouds.set_parameter(env, "light_steps", RenderCfg.CLOUD_LIGHT_STEPS)],
        ["terrain auto_shader off", func() -> void: (ground.get("material") as Object).set("auto_shader", false),
            func() -> void: (ground.get("material") as Object).set("auto_shader", true)],
        ["terrain dual_scaling off", func() -> void: (ground.get("material") as Object).set("dual_scaling", false),
            func() -> void: (ground.get("material") as Object).set("dual_scaling", true)],
        ["render scale 0.64 + FSR 2 (1440 rows)", func() -> void:
            viewport.scaling_3d_scale = 0.64 * RETINA_SCALE
            viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2,
            func() -> void:
            viewport.scaling_3d_scale = RETINA_SCALE
            viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR],
        ["the defaults", func() -> void:
            var defaults: GraphicsSettings = GraphicsSettings.new()
            viewport.scaling_3d_scale = GraphicsSettings.scale_for(size.y) * RETINA_SCALE
            viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
            defaults.apply_clouds(env)
            RenderingServer.directional_shadow_atlas_set_size(
                GraphicsSettings.SHADOW_ATLAS[int(GraphicsSettings.DEFAULTS["shadow_quality"])], true)
            if fill != null:
                fill.shadow_enabled = false,
            func() -> void:
            viewport.scaling_3d_scale = RETINA_SCALE
            viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
            SkyClouds.set_parameter(env, "steps", RenderCfg.CLOUD_STEPS)
            SkyClouds.set_parameter(env, "light_steps", RenderCfg.CLOUD_LIGHT_STEPS)
            RenderingServer.directional_shadow_atlas_set_size(4096, true)
            if fill != null:
                fill.shadow_enabled = true],
        ["taa on", func() -> void: viewport.use_taa = true, func() -> void: viewport.use_taa = false],
        ["msaa 4x", func() -> void: viewport.msaa_3d = Viewport.MSAA_4X, func() -> void: viewport.msaa_3d = Viewport.MSAA_DISABLED],
    ]
    for trial: Array in trials:
        (trial[1] as Callable).call()
        var ms: float = await _measure(trial[0] as String)
        (trial[2] as Callable).call()
        rows.append("%s %.1f ms (%+.1f)" % [trial[0], ms, ms - base])
    # Driven: the solver, the deform, the chase camera and the grass moving with it.
    var drive: PlayDrive = PlayDrive.new()
    var set_up: String = drive.setup(result)
    if set_up != "":
        return fail(set_up)
    drive.spawn = PlaySolid.clear_spawn(terrain)
    drive.solver.set_gravity(Vector3(0.0, terrain.gravity(), 0.0))
    var taken: String = drive.use_terrain(ground.get("data"))
    if taken != "":
        return fail(taken)
    RorObjectCollision.apply(terrain, drive.solver)
    for _i: int in 60:
        drive.step(FRAME_S)
    drive.scripted_throttle = 1.0
    var driven: Dictionary = await _drive_measure(drive, vegetation)
    rows.append("driving %.0f s, everything on: median %.1f ms, worst %.1f ms, reached %.0f km/h" % [
        DRIVE_SECONDS, driven["median"], driven["worst"], driven["kmh"]])
    var defaults: Array = []
    for trial: Array in trials:
        if (trial[0] as String) == "the defaults":
            defaults = trial
    (defaults[1] as Callable).call()
    drive.respawn()
    for _i: int in 60:
        drive.step(FRAME_S)
    driven = await _drive_measure(drive, vegetation)
    (defaults[2] as Callable).call()
    rows.append("driving %.0f s, the defaults: median %.1f ms, worst %.1f ms, reached %.0f km/h" % [
        DRIVE_SECONDS, driven["median"], driven["worst"], driven["kmh"]])
    viewport.scaling_3d_scale = 1.0
    DisplayServer.window_set_vsync_mode(was_vsync as DisplayServer.VSyncMode)
    for row: String in rows:
        print("HARNESS_COST " + row)
    return ok("; ".join(rows), base)


## Five seconds of driving, the chase camera on the vehicle and the grass refilling around it.
func _drive_measure(drive: PlayDrive, vegetation: RorVegetation) -> Dictionary:
    var wall: PackedFloat32Array = PackedFloat32Array()
    var fastest: float = 0.0
    for _frame: int in int(DRIVE_SECONDS * 60.0):
        var began: int = Time.get_ticks_usec()
        drive.begin(FRAME_S)
        if vegetation != null:
            vegetation.focus_on(_harness.camera.global_position)
        drive.finish()
        var frame: Transform3D = drive.frame
        var back: Vector3 = frame.basis.z
        _harness.camera.look_at_from_position(
            frame.origin + back * 6.5 + Vector3.UP * 2.2, frame.origin + Vector3.UP * 0.8, Vector3.UP
        )
        await _harness.advance_frames(1, "static", "drive")
        wall.append(float(Time.get_ticks_usec() - began) / 1000.0)
        fastest = maxf(fastest, absf(drive.solver.road_speed()) * 3.6)
    wall.sort()
    return {"median": wall[wall.size() / 2], "worst": wall[wall.size() - 1], "kmh": fastest}


func _measure(_label: String) -> float:
    await _harness.advance_frames(WARM_FRAMES, "static", "warm")
    var wall: PackedFloat32Array = PackedFloat32Array()
    for _frame: int in MEASURED_FRAMES:
        var began: int = Time.get_ticks_usec()
        await _harness.advance_frames(1, "static", "measure")
        wall.append(float(Time.get_ticks_usec() - began) / 1000.0)
    wall.sort()
    return wall[wall.size() / 2]
