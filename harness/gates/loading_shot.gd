extends GateBase
## The loading screen's picture: the hero on a road at dusk, wheels turned, lamps on, through a
## long lens, taken from the map rather than posed by hand.
##
## A loading screen with a photograph of the game on it is a small thing a person asked for and
## a measurement of the project all the same: the frame is the vehicle on a terrain's own road
## under this project's own dusk, so it moves with everything under it. The road point and its
## direction come from the terrain's road network; the sun is the preset's; the camera stands at
## the front quarter the wheels turn toward, at 85 mm, focused on the vehicle so the lens's own
## depth of field falls off behind it. `tools/loading_shot.sh` runs this and copies the capture
## to `assets/ui/loading.png`, which `PlayLoading` draws and which is not committed: it is a
## render of community content.
##
## What is held: the frame is lit, the vehicle fills a sensible share of it, and the lamps are
## on. The look is the person's.

const TERRAIN: String = "lapaz"
const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const WEATHER: String = "golden_dusk"
const FOCAL_MM: float = 85.0
const F_STOP: float = 2.8
## Where the camera stands, in the vehicle's own frame: ahead, to the side, up.
const STAND_AHEAD_M: float = 9.0
const STAND_ASIDE_M: float = 6.0
const STAND_UP_M: float = 1.0
const LOOK_UP_M: float = 0.55
## How far the sun sits round from the vehicle's nose, so the light falls across the front.
const SUN_ROUND_DEG: float = 50.0
const STEER: float = -0.75
const SETTLE_FRAMES: int = 90
const CONVERGE: int = 8
const MIN_LUMA: float = 0.02
const MIN_VEHICLE_SHARE: float = 0.10
const FRAME_S: float = 1.0 / 60.0


static func meta() -> Dictionary:
    return {
        "name": "loading_shot",
        "proves": "the loading screen's picture renders from the hero on a road the terrain declares, lit, lamps on, with the vehicle filling at least %.0f%% of the frame" % (MIN_VEHICLE_SHARE * 100.0),
        "builds_on": ["money_shots"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "frame luma over %.3f, vehicle over %.0f%% of the frame, every lamp lit" % [MIN_LUMA, MIN_VEHICLE_SHARE * 100.0],
        "why": (
            "a loading screen that shows the game is a picture of the project's state, and one"
            + " taken by hand goes stale; placed from the terrain's road it is retaken with"
            + " every change under it."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var loaded: Dictionary = RorTerrainLibrary.load_named(TERRAIN)
    if (loaded.get("error", "") as String) != "":
        return ok("skipped: %s" % loaded["error"], 0)
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var err: String = harness.setup_for("hero_3q", WEATHER)
    if err != "":
        return fail(err)
    var ground: Node3D = TerrainWorld.create()
    if ground == null:
        return ok("skipped: Terrain3D is not installed", 0)
    harness.world.add_child(ground)
    await harness.advance_frames(2, "static", "terrain")
    var built_error: String = harness.terrain.populate(ground, terrain)
    if built_error != "":
        return fail(built_error)
    var blockout: Node3D = harness.world.get_node_or_null(^"Ground") as Node3D
    if blockout != null:
        blockout.visible = false
    harness.world.add_child(RorObjects.build(terrain))
    harness.world.add_child(RorProceduralRoad.build(terrain))
    harness.world.add_child(RorWater.build(terrain, 0.0))

    var built: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    harness.world.add_child(built["root"] as Node3D)
    var drive: PlayDrive = PlayDrive.new()
    var set_up: String = drive.setup(built)
    if set_up != "":
        return fail(set_up)
    var weather: Dictionary = WeatherCfg.get_preset(WEATHER).duplicate()
    weather["cloud_phase"] = 0.0
    var sun: Vector3 = (weather["sun_from"] as Vector3)
    var sun_flat: Vector3 = Vector3(sun.x, 0.0, sun.z).normalized()
    var road: Dictionary = _road_point(terrain, terrain.start_position())
    # The nose points so that the sun sits SUN_ROUND_DEG round from it, on the camera's side.
    var nose: Vector3 = sun_flat.rotated(Vector3.UP, deg_to_rad(SUN_ROUND_DEG))
    var heading: float = atan2(-nose.x, -nose.z)
    drive.spawn = road["at"] as Vector3
    drive.spawn_heading = heading
    drive.solver.set_gravity(Vector3(0.0, terrain.gravity(), 0.0))
    var taken: String = drive.use_terrain(ground.get("data"))
    if taken != "":
        return fail(taken)
    RorObjectCollision.apply(terrain, drive.solver)
    drive.scripted_steer = STEER
    drive.set_lights(true)
    for _i: int in SETTLE_FRAMES:
        drive.step(FRAME_S)
    BlockoutWorld.apply_weather(harness.world, weather, RenderCfg.CLOUDS_ENABLED)
    var preset: Dictionary = CameraCfg.get_preset("hero_3q").duplicate()
    preset["f_stop"] = F_STOP
    PhysicalCamera.reexpose(harness.camera, preset, weather)
    var attributes: CameraAttributesPhysical = harness.camera.attributes as CameraAttributesPhysical
    attributes.frustum_focal_length = FOCAL_MM
    attributes.exposure_aperture = F_STOP
    ActorProbe.recapture(harness.world)
    var frame: Transform3D = drive.frame
    var forward: Vector3 = -frame.basis.z
    forward = Vector3(forward.x, 0.0, forward.z).normalized()
    var right: Vector3 = forward.cross(Vector3.UP).normalized()
    var eye: Vector3 = frame.origin + forward * STAND_AHEAD_M + right * STAND_ASIDE_M + Vector3.UP * STAND_UP_M
    var at: Vector3 = frame.origin + Vector3.UP * LOOK_UP_M
    attributes.frustum_focus_distance = eye.distance_to(at)
    harness.camera.look_at_from_position(eye, at, Vector3.UP)
    var shot: Dictionary = await harness.capture_shot("loading_shot", "static", CONVERGE)
    if (shot["error"] as String) != "":
        return fail(shot["error"] as String)
    var image: Image = Image.load_from_file(shot["png"] as String)
    if image == null:
        return fail("the capture at %s could not be read" % shot["png"])
    var luma: float = _mean_luma(image)
    var share: float = _vehicle_share(built["root"] as Node3D, harness.camera, image.get_size())
    var lamps: Array[Node3D] = built["lamps"] as Array[Node3D]
    var lit: int = 0
    for lamp: Node3D in lamps:
        if lamp.visible:
            lit += 1
    if luma < MIN_LUMA:
        return fail("the frame renders at %.4f luma: there is nothing in it. See %s" % [luma, shot["png"]], luma)
    if share < MIN_VEHICLE_SHARE:
        return fail("the vehicle fills %.0f%% of the frame: the camera is not on it. See %s" % [share * 100.0, shot["png"]], share)
    if lamps.size() > 0 and lit == 0:
        return fail("no lamp is lit at dusk. See %s" % shot["png"], 0)
    return ok(
        "%s: the hero at %s, nose %.0f deg, sun %.0f deg round, %.0f mm f/%.1f; luma %.3f, vehicle %.0f%% of the frame, %d lamps lit. %s"
        % [terrain.name, road["from"], rad_to_deg(heading), SUN_ROUND_DEG, FOCAL_MM, F_STOP, luma, share * 100.0, lit, shot["png"]],
        share
    )


## The road point nearest the spawn, and where it is.
static func _road_point(terrain: RorTerrain, spawn: Vector3) -> Dictionary:
    var best: Vector3 = spawn
    var best_distance: float = INF
    var count: int = 0
    for group: Array in RorProceduralRoad.groups(terrain):
        for point: Dictionary in group:
            var at: Vector3 = point["position"] as Vector3
            count += 1
            var distance: float = Vector2(at.x - spawn.x, at.z - spawn.z).length()
            if distance < best_distance:
                best_distance = distance
                best = at
    if count == 0:
        return {"at": spawn, "from": "the spawn (no road points)"}
    return {"at": best, "from": "the road point %.0f m from the spawn" % best_distance}


static func _mean_luma(image: Image) -> float:
    var size: Vector2i = image.get_size()
    var total: float = 0.0
    var counted: int = 0
    for y: int in range(0, size.y, 4):
        for x: int in range(0, size.x, 4):
            var colour: Color = image.get_pixel(x, y)
            total += colour.r * 0.2126 + colour.g * 0.7152 + colour.b * 0.0722
            counted += 1
    return total / maxf(float(counted), 1.0)


## How much of the frame the vehicle's bounds project onto.
static func _vehicle_share(root: Node3D, camera: Camera3D, size: Vector2i) -> float:
    var bounds: AABB = ActorProbe.local_bounds(root)
    var low: Vector2 = Vector2(INF, INF)
    var high: Vector2 = Vector2(-INF, -INF)
    for i: int in 8:
        var corner: Vector3 = bounds.position + Vector3(
            bounds.size.x if (i & 1) != 0 else 0.0,
            bounds.size.y if (i & 2) != 0 else 0.0,
            bounds.size.z if (i & 4) != 0 else 0.0
        )
        var on_screen: Vector2 = camera.unproject_position(root.to_global(corner))
        low = low.min(on_screen)
        high = high.max(on_screen)
    var frame: Rect2 = Rect2(Vector2.ZERO, Vector2(size)).intersection(Rect2(low, high - low))
    return frame.get_area() / maxf(float(size.x * size.y), 1.0)
