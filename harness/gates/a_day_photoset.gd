extends GateBase
## The hero vehicle on a shipped terrain, photographed once an hour for a whole day.
##
## **A day is judged by eye and nothing else can judge it.** `a_day_runs_from_dawn_to_dark` holds
## the arithmetic — the sun up when it should be, noon brighter than midnight, the exposure
## running against the light — and every one of those can hold while an hour looks wrong. Two did:
## seven in the morning came out a pale blue-white noon, because how bright an hour is and what
## colour it is were answered with the same number and the colour had saturated by the time the
## sun was 16 degrees up. Reported from a window as "a few moments when it looks weirdly white
## when it is supposed to be sunset or sunrise".
##
## So this takes the set a person needs: one frame an hour from a chase camera with the horizon
## in it, lights on after dark, with the sky, the ground and the brightest pixel of each printed
## beside it. What the gate itself holds is only that every hour drew something — an hour that
## renders black or blows out is a fault anybody can state — and the judging is a person's.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const MAP: String = "lapaz"
## What an hour's ground and sky may be. Wide on purpose: this catches a black hour and a blown
## one, and leaves everything between them to a person looking at the sheet.
const MIN_GROUND: float = 0.01
const MAX_GROUND: float = 0.9
const MAX_SKY: float = 0.95
const LISTED: int = 6


static func meta() -> Dictionary:
    return {
        "name": "a_day_photoset",
        "proves": (
            "every hour of the day draws a frame with both ground and sky in it, from midnight"
            + " to midnight on a shipped terrain with a vehicle in shot"
        ),
        "builds_on": ["a_day_runs_from_dawn_to_dark"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "every hour's ground between 0.01 and 0.9, its sky under 0.95, and no hour the same"
            + " frame as the hour before it"
        ),
        "why": (
            "the arithmetic of a day can be right in every part while an hour looks wrong, and"
            + " an hour that looks wrong is the only thing a person actually reports. Seven in"
            + " the morning rendered as a pale noon for exactly this reason."
        ),
        "budget_s": 600.0, "needs_gpu": true, "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var loaded: Dictionary = RorTerrainLibrary.load_named(MAP)
    if (loaded.get("error", "") as String) != "":
        return fail(loaded["error"] as String)
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain
    var err: String = harness.setup_for("hero_3q", "noon_clear")
    if err != "":
        return fail(err)
    var ground: Node3D = TerrainWorld.create()
    if ground == null:
        return fail("Terrain3D is not installed")
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
    var built: Dictionary = VehicleBuilder.build(
        SourceScan.repo_root().path_join(MOD_DIR), TRUCK
    )
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    var truck: TruckParser = built["truck"] as TruckParser
    var root: Node3D = built["root"] as Node3D
    harness.world.add_child(root)
    var start: Vector3 = terrain.start_position()
    root.position = start + Vector3(0.0, 0.6, 0.0)
    var lamps: Array[Node3D] = built["lamps"] as Array[Node3D]
    # Behind the vehicle and a little to one side, with the horizon in frame: a sunrise is a
    # thing that happens at the horizon and a chase camera that sees none cannot show it.
    var at: Vector3 = start + Vector3(8.5, 2.6, 4.5)
    harness.camera.look_at_from_position(at, start + Vector3(-40.0, 3.0, 0.0), Vector3.UP)
    var rows: PackedStringArray = PackedStringArray()
    var problems: PackedStringArray = PackedStringArray()
    var previous: Dictionary = {}
    for step: int in 24:
        var hour: float = float(step)
        var sky: Dictionary = DayCycle.at(hour)
        BlockoutWorld.apply_weather(harness.world, sky, RenderCfg.CLOUDS_ENABLED)
        PhysicalCamera.reexpose(harness.camera, CameraCfg.get_preset("hero_3q"), sky)
        # Lights on after dark, which is what a driver would do.
        FlareBuilder.apply_state(lamps, truck, {
            "headlights": DayCycle.sun_elevation_deg(hour) < 2.0,
        })
        var shot: Dictionary = await harness.capture_shot("day/h%02d" % step, "static", 6)
        if (shot["error"] as String) != "":
            return fail(shot["error"] as String)
        var read: Dictionary = _read(shot["png"] as String)
        rows.append("%02d:00 sky %.3f ground %.3f max %.3f lux %.2f" % [
            step, read["sky"], read["ground"], read["max"], sky["sun_lux"]
        ])
        var ground_luma: float = read["ground"] as float
        if ground_luma < MIN_GROUND or ground_luma > MAX_GROUND:
            problems.append("%02d:00 draws a ground of %.3f" % [step, ground_luma])
        elif (read["sky"] as float) > MAX_SKY:
            problems.append("%02d:00 draws a sky of %.3f" % [step, read["sky"]])
        elif not previous.is_empty() and is_equal_approx(
            previous["sky"] as float, read["sky"] as float
        ) and is_equal_approx(previous["ground"] as float, ground_luma):
            problems.append("%02d:00 is the same frame as the hour before it" % step)
        previous = read
    for row: String in rows:
        print("DAYSHEET " + row)
    if problems.size() > 0:
        return fail("; ".join(problems.slice(0, LISTED)), problems.size())
    return ok(
        "24 hours on %s, each drawn: %s" % [MAP, " ".join(rows.slice(5, 9))], 24
    )


## The sky, the ground, and the brightest pixel in the frame.
func _read(png: String) -> Dictionary:
    var image: Image = Image.load_from_file(png)
    if image == null:
        return {"sky": 0.0, "ground": 0.0, "max": 0.0}
    var sky: float = 0.0
    var sky_count: int = 0
    var ground: float = 0.0
    var ground_count: int = 0
    var peak: float = 0.0
    for y: int in range(0, image.get_height(), 4):
        for x: int in range(0, image.get_width(), 4):
            var pixel: Color = image.get_pixel(x, y)
            var luma: float = pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
            peak = maxf(peak, luma)
            if y < int(image.get_height() * 0.33):
                sky += luma
                sky_count += 1
            elif y > int(image.get_height() * 0.6):
                ground += luma
                ground_count += 1
    return {
        "sky": 0.0 if sky_count == 0 else sky / float(sky_count),
        "ground": 0.0 if ground_count == 0 else ground / float(ground_count),
        "max": peak,
    }
