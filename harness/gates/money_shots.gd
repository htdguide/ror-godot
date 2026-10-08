extends GateBase
## The eight money shots: the frames every visual milestone re-renders, so progress is one sheet.
##
## PLAN §0.5 named eight and half of them named features of a generated valley that is gone. This
## is the replacement set, and the rule that makes it not the same mistake again is in
## `MoneyShotFrames`: every frame is placed from something the terrain declares — its spawn, its
## road points, its water line, its objects — or from a search over its own heightmap, never from a
## coordinate written beside it. Point the same gate at a different terrain and it photographs that
## terrain's own vista, road, shore and object.
##
## The claims here are the weak ones a photoset makes — the frame is lit, the camera is looking at
## the world and not the inside of a hill, a frame that asks for lamps has lamps lit — because the
## strong claim about these frames is a person's: `tools/money_shots.sh` lays them out as one sheet
## and the sheet is what a milestone is judged on. Every frame reports what it is of and which
## feature of the terrain put the camera there, so a reader can argue with the placement.

## The terrain the sheet is of unless `--terrain-dir <name>` says otherwise: La Paz is the project's
## showcase map — relief, imagery, a hundred objects — and the frames a milestone is compared on
## are its. It declares no road points and no water line, so two frames fall back to the spawn's
## painted road and the lowest ground and say so; `--terrain-dir starling-port` has both.
const TERRAIN: String = "lapaz"
const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const CONVERGE: int = 6
## A frame this dark is a camera inside the terrain or a scene that failed to light. The night
## frame has its own floor: a moonlit scene with lamps on is dark and is meant to be.
const MIN_LUMA: float = 0.02
const MIN_LUMA_NIGHT: float = 0.004
## And this much of the frame has to be something other than sky.
const MIN_GROUND_FRACTION: float = 0.12
const SKY_LUMA: float = 0.35
## Phases every capture is taken at: a frame must not depend on when it was taken.
const FROZEN_PHASE: float = 0.0


static func meta() -> Dictionary:
    return {
        "name": "money_shots",
        "proves": "the eight showcase frames render from features the terrain itself declares, each lit and looking at the world, and are captured for the sheet a milestone is judged on",
        "builds_on": ["ror_terrain_photoset"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "8 frames, each over %.3f luma (%.3f at night) with at least %.0f%% of the frame not"
            % [MIN_LUMA, MIN_LUMA_NIGHT, MIN_GROUND_FRACTION * 100.0]
            + " sky, and lamps lit where a frame asks for them"
        ),
        "why": (
            "the first money shots named features of a deleted valley and nothing rendered the"
            + " sheet for a milestone to be measured against. These are derived from the terrain,"
            + " so the sheet exists for any shipped map; the bound is so a frame of nothing fails"
            + " here rather than in front of a person."
        ),
        "budget_s": 240.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var terrain_name: String = harness.args.get_string("terrain-dir", TERRAIN)
    var loaded: Dictionary = RorTerrainLibrary.load_named(terrain_name)
    if (loaded.get("error", "") as String) != "":
        return ok("skipped: %s" % loaded["error"], 0)
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var err: String = harness.setup_for("hero_3q", "noon_clear")
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
    harness.world.add_child(RorWater.build(terrain, FROZEN_PHASE))
    var vegetation: RorVegetation = RorVegetation.new()
    vegetation.wind_phase = FROZEN_PHASE
    if vegetation.setup(terrain) == "":
        harness.world.add_child(vegetation)
    else:
        vegetation.free()
        vegetation = null

    var built: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    var truck: TruckParser = built["truck"] as TruckParser
    var root: Node3D = built["root"] as Node3D
    harness.world.add_child(root)
    var start: Vector3 = terrain.start_position()
    root.position = Vector3(start.x, terrain.height_at_world(start.x, start.z) + 0.6, start.z)
    var lamps: Array[Node3D] = built["lamps"] as Array[Node3D]
    var bounds: AABB = ActorProbe.local_bounds(root)
    bounds.position += root.position
    var hero: Dictionary = {"bounds": bounds, "wheel": _front_wheel(root, truck, bounds)}

    var reported: PackedStringArray = PackedStringArray()
    var darkest: float = INF
    var frames: Array[Dictionary] = MoneyShotFrames.frames(terrain, hero)
    for index: int in frames.size():
        var frame: Dictionary = frames[index]
        var weather_name: String = frame["weather"] as String
        var weather: Dictionary = WeatherCfg.get_preset(weather_name).duplicate()
        weather["cloud_phase"] = FROZEN_PHASE
        BlockoutWorld.apply_weather(harness.world, weather, RenderCfg.CLOUDS_ENABLED)
        PhysicalCamera.reexpose(harness.camera, CameraCfg.get_preset("hero_3q"), weather)
        (harness.camera.attributes as CameraAttributesPhysical).frustum_focal_length = (
            frame["focal_mm"] as float
        )
        ActorProbe.recapture(harness.world)
        FlareBuilder.apply_state(lamps, truck, {"headlights": bool(frame.get("lamps", false))})
        var at: Vector3 = frame["at"] as Vector3
        if vegetation != null:
            vegetation.focus_on(at)
            vegetation.fill()
        var floor_luma: float = MIN_LUMA_NIGHT if weather_name == "night_moon" else MIN_LUMA
        # A frame may offer several places to stand; the first that sees anything is the one.
        var eyes: Array = frame.get("eyes", [frame["eye"]]) as Array
        var shot: Dictionary = {}
        var measured: Dictionary = {}
        var stood: int = 0
        for candidate: int in eyes.size():
            stood = candidate
            harness.camera.look_at_from_position(eyes[candidate] as Vector3, at, Vector3.UP)
            shot = await harness.capture_shot(
                "money_shots/%d_%s" % [index + 1, frame["name"]], "static", CONVERGE
            )
            if (shot["error"] as String) != "":
                return fail(shot["error"] as String)
            var image: Image = Image.load_from_file(shot["png"] as String)
            if image == null:
                return fail("the capture at %s could not be read" % shot["png"])
            measured = _measure(image)
            if (measured["luma"] as float) >= floor_luma:
                break
        var luma: float = measured["luma"] as float
        darkest = minf(darkest, luma)
        if luma < floor_luma:
            return fail(
                "frame %d (%s, %s) renders at %.4f luma: there is nothing in it. %s. See %s"
                % [index + 1, frame["name"], weather_name, luma, frame["from"], shot["png"]],
                luma
            )
        if (measured["ground"] as float) < MIN_GROUND_FRACTION:
            return fail(
                "frame %d (%s) is %.0f%% sky: the camera is not looking at the world. %s. See %s"
                % [index + 1, frame["name"], (1.0 - (measured["ground"] as float)) * 100.0,
                   frame["from"], shot["png"]],
                measured["ground"]
            )
        if bool(frame.get("lamps", false)) and _lit(lamps) == 0:
            return fail("frame %d (%s) asked for headlights and no lamp is lit" % [index + 1, frame["name"]])
        reported.append("%d %s: %s (%s%s) %.3f luma" % [
            index + 1, frame["name"], frame["subject"], frame["from"],
            "" if stood == 0 else ", eye %d of %d" % [stood + 1, eyes.size()], luma])
    return ok(
        "%s: %d frames, darkest %.3f luma. %s" % [terrain.name, frames.size(), darkest, "; ".join(reported)],
        darkest
    )


## Where the hero's first wheel is, in the world: its first axle node through the vehicle's own
## transform, or the front-left corner of its bounds if the file names none.
func _front_wheel(root: Node3D, truck: TruckParser, bounds: AABB) -> Vector3:
    if truck.wheels.is_empty():
        return bounds.position + Vector3(bounds.size.x * 0.2, bounds.size.y * 0.2, bounds.size.z)
    var wheel: Dictionary = truck.wheels[0]
    var axle: Vector3 = (truck.nodes[wheel["node1"] as int] + truck.nodes[wheel["node2"] as int]) * 0.5
    return root.to_global(axle)


func _lit(lamps: Array[Node3D]) -> int:
    var count: int = 0
    for lamp: Node3D in lamps:
        if lamp.visible:
            count += 1
    return count


## How bright a frame is, and how much of it is not sky.
func _measure(image: Image) -> Dictionary:
    var size: Vector2i = image.get_size()
    var total: float = 0.0
    var ground: int = 0
    var counted: int = 0
    for y: int in range(0, size.y, 4):
        for x: int in range(0, size.x, 4):
            var colour: Color = image.get_pixel(x, y)
            var luma: float = colour.r * 0.2126 + colour.g * 0.7152 + colour.b * 0.0722
            total += luma
            if luma < SKY_LUMA or colour.b <= colour.r:
                ground += 1
            counted += 1
    return {"luma": total / float(maxi(counted, 1)), "ground": float(ground) / float(maxi(counted, 1))}
