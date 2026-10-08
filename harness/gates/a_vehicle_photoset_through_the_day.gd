extends GateBase
## The hero vehicle from four sides at seven hours of the day, on a terrain it is standing on.
##
## **Lighting is judged on a vehicle, not on a road.** The day gates hold the sun's arc, the sky's
## brightness and the ground's — none of which says whether paint looks like paint at six in the
## morning, whether glass picks up a sky that is no longer there, or whether the chrome at
## midnight is reflecting a noon that was captured hours ago. An actor carries a reflection probe
## taken once, and "once" is the whole question when the hour moves.
##
## So: four views around the vehicle at seven hours, with the terrain under it and the sky of that
## hour over it. The gate holds what can be stated — every frame has the vehicle in it, the
## vehicle tracks the hour rather than keeping one brightness all day, and no two hours give the
## same frame — and the look is a person's to judge from the sheet.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const MAP: String = "lapaz"
## The hours worth four frames each: the middle of the night, sunrise, mid-morning, noon,
## mid-afternoon, sunset, and an hour into the dark.
const HOURS: Array[float] = [0.0, 5.5, 6.0, 7.0, 12.0, 17.0, 18.0, 18.5, 21.0]
## Hours whose frames are kept side by side in the sheet. Everything in HOURS is photographed;
## these are the ones a person is most likely to be asked about.
## Around the vehicle rather than over it: the roof and the floor pans say nothing about an hour.
const VIEWS: Array[String] = ["front", "left", "back", "three_quarter"]
## How much of a frame the vehicle has to fill before it counts as being in it.
const MIN_SUBJECT: float = 0.05
## How much the vehicle's own brightness has to move between its darkest hour and its brightest.
## Measured at over a hundred times; this is a long way under it and still catches a vehicle lit
## by something that is not the sky.
const MIN_SWING: float = 6.0
const CONVERGE: int = 6
const LISTED: int = 6
## The cloud phase every frame here is taken at. Any fixed number would do; what matters is that
## it is fixed — the same rule the foliage's wind and the sea's waves already follow.
const FROZEN_CLOUD_PHASE: float = 0.0


static func meta() -> Dictionary:
    return {
        "name": "a_vehicle_photoset_through_the_day",
        "proves": (
            "the hero vehicle is drawn from four sides at seven hours of the day, is in every"
            + " frame, and takes its light and its reflections from the hour it is standing in"
        ),
        "builds_on": ["a_day_photoset", "vehicle_photoset"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "every one of the frames at least 5%% vehicle, the vehicle's brightest hour at"
            + " least 6 times its darkest, and no hour the same as the one before it"
        ),
        "why": (
            "a reflection probe is taken once and an hour moves. A vehicle that keeps one"
            + " brightness all day is lit by something that is not the sky, and a vehicle"
            + " reflecting a noon at midnight is the same fault seen in its paint — which is"
            + " how it was reported: 'in the dark we are supposed to barely see the car'."
        ),
        "budget_s": 600.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var loaded: Dictionary = RorTerrainLibrary.load_named(MAP)
    if (loaded.get("error", "") as String) != "":
        return ok("skipped: %s" % loaded["error"], 0)
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain
    var error: String = harness.setup_for("hero_3q", "noon_clear")
    if error != "":
        return fail(error)
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
    var built: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    var truck: TruckParser = built["truck"] as TruckParser
    var root: Node3D = built["root"] as Node3D
    harness.world.add_child(root)
    var start: Vector3 = terrain.start_position()
    root.position = start + Vector3(0.0, 0.6, 0.0)
    var lamps: Array[Node3D] = built["lamps"] as Array[Node3D]
    var bounds: AABB = ActorProbe.local_bounds(root)
    bounds.position += root.position

    var problems: PackedStringArray = PackedStringArray()
    var brightest: float = 0.0
    var darkest: float = INF
    var seen: PackedFloat32Array = PackedFloat32Array()
    for hour: float in HOURS:
        var sky: Dictionary = DayCycle.at(hour)
        sky["cloud_phase"] = FROZEN_CLOUD_PHASE
        BlockoutWorld.apply_weather(harness.world, sky, RenderCfg.CLOUDS_ENABLED)
        PhysicalCamera.reexpose(harness.camera, CameraCfg.get_preset("hero_3q"), sky)
        # The probe was taken under whatever sky was up when the vehicle was built, and this is
        # the whole question the sheet exists to answer.
        ActorProbe.recapture(harness.world)
        FlareBuilder.apply_state(lamps, truck, {
            "headlights": DayCycle.sun_elevation_deg(hour) < 2.0,
        })
        var at_hour: float = 0.0
        for view: String in VIEWS:
            var placement: Dictionary = Photoset.placement(view, bounds, bounds.get_center())
            harness.camera.look_at_from_position(
                placement["pos"] as Vector3, placement["look_at"] as Vector3, Vector3.UP
            )
            var shot: Dictionary = await harness.capture_shot(
                "dayvehicle/%04d-%s" % [int(hour * 100.0), view], "static", CONVERGE
            )
            if (shot["error"] as String) != "":
                return fail(shot["error"] as String)
            var read: Dictionary = _read(shot["png"] as String)
            if (read["subject"] as float) < MIN_SUBJECT:
                problems.append("%02d:00 %s has %.1f%% vehicle in it"
                    % [int(hour), view, (read["subject"] as float) * 100.0])
            at_hour += read["vehicle"] as float
            print("DAYVEHICLE %05.2f %-14s vehicle %.4f frame %.4f" % [
                int(hour), view, read["vehicle"], read["frame"]
            ])
        at_hour /= float(VIEWS.size())
        # Consecutive hours only. **A day is symmetric about noon**, so seven in the morning and
        # five in the afternoon are the same light by construction and comparing every hour with
        # every other one calls that a fault. What is worth catching is a scene that stopped
        # following the clock at all, and that shows up between neighbours.
        if seen.size() > 0 and is_equal_approx(seen[seen.size() - 1], at_hour):
            problems.append("%05.2f lights the vehicle exactly as the hour before it" % hour)
        seen.append(at_hour)
        brightest = maxf(brightest, at_hour)
        darkest = minf(darkest, at_hour)

    if problems.size() > 0:
        return fail("; ".join(problems.slice(0, LISTED)), problems.size())
    if brightest < darkest * MIN_SWING:
        return fail(
            "the vehicle reads %.4f at its brightest hour and %.4f at its darkest, which is"
            % [brightest, darkest] + " %.1f times and not the %.0f required: it is not lit by"
            % [brightest / maxf(darkest, 0.0001), MIN_SWING] + " the day",
            brightest / maxf(darkest, 0.0001)
        )
    return ok(
        "%d frames over %d hours: the vehicle runs from %.4f at its darkest hour to %.4f at its"
        % [HOURS.size() * VIEWS.size(), HOURS.size(), darkest, brightest]
        + " brightest, %.0f times" % [brightest / maxf(darkest, 0.0001)],
        brightest / maxf(darkest, 0.0001)
    )


## How bright the vehicle is in a frame, how bright the whole frame is, and how much of the
## frame the vehicle fills.
##
## The vehicle is told from the scene by depth of field rather than by colour: the middle of
## every one of these views is the subject, so the middle band is read as the vehicle and the
## whole frame beside it.
func _read(png: String) -> Dictionary:
    var image: Image = Image.load_from_file(png)
    if image == null:
        return {"vehicle": 0.0, "frame": 0.0, "subject": 0.0}
    var middle: float = 0.0
    var middle_count: int = 0
    var whole: float = 0.0
    var whole_count: int = 0
    var subject: int = 0
    var peak: float = 0.0
    var clipped: int = 0
    for y: int in range(0, image.get_height(), 3):
        for x: int in range(0, image.get_width(), 3):
            var pixel: Color = image.get_pixel(x, y)
            var luma: float = pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
            whole += luma
            whole_count += 1
            var centred: bool = (
                x > int(image.get_width() * 0.3) and x < int(image.get_width() * 0.7)
                and y > int(image.get_height() * 0.35) and y < int(image.get_height() * 0.75)
            )
            if centred:
                middle += luma
                middle_count += 1
                subject += 1
                peak = maxf(peak, luma)
                # What a blown highlight is: a pixel with nothing left in it.
                if luma > 0.98:
                    clipped += 1
    return {
        "vehicle": 0.0 if middle_count == 0 else middle / float(middle_count),
        "frame": 0.0 if whole_count == 0 else whole / float(whole_count),
        "subject": 0.0 if whole_count == 0 else float(subject) / float(whole_count),
        "peak": peak,
        "clipped": 0.0 if middle_count == 0 else float(clipped) / float(middle_count),
    }
