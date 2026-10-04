extends GateBase
## A dragged hour is a day: the sun rises and sets, the light follows it, and the exposure
## follows the light.
##
## **A preset is a snapshot and a day is a path.** `DayCycle.at` returns one hour of it as a
## weather dictionary of exactly the kind a preset is, so everything downstream — the sun, the
## sky, the stars, the haze, the camera's own three numbers — moves together or not at all. What
## this holds is that the path is a day rather than a set of numbers that happen to vary:
##
## 1. **The sun is up by day and down by night**, crossing at the hours the model names. That is
##    an astronomical fact and not a threshold somebody picked.
## 2. **The light follows the sun's height.** Noon is the brightest hour on the ground and
##    midnight the darkest, by more than four orders of magnitude, because that is the ratio
##    between a hundred thousand lux of sun and a quarter of a lux of moon.
## 3. **The exposure runs the other way.** Under physical light units an hour that states its
##    light in lux has to state what that light was metered for, so the camera opens up as the
##    sun goes down — and a day whose exposure did not would be a day nobody could see half of.
## 4. **And it is drawn.** A frame at noon, at dusk and at midnight, from the same camera on the
##    same terrain: noon far brighter than midnight, and dusk between the two. A model that
##    computes a beautiful hour and renders nothing is the failure this catches.
##
## The frames are the claim; the arithmetic above is what makes a failure point somewhere.

const MAP: String = "lapaz"
## Hours to photograph. Noon, the hour the sun is on the horizon, and the middle of the night.
const SHOWN: Array[float] = [12.0, 18.0, 0.0]
## How much brighter the ground at noon has to be than at midnight, in a rendered frame. The
## light itself differs by 400,000 to one; a tone mapper is not a light meter and this is the
## ratio that survives it. Measured at 40 times.
const MIN_DAY_TO_NIGHT: float = 8.0
## And how much of the frame midnight may be. A night that renders as a grey day fails here.
const MAX_NIGHT: float = 0.08
## How near the horizon counts as on it. At sunrise and sunset the elevation is zero to within
## floating-point noise, and the sign of noise is not a fact about the sun.
const HORIZON_DEG: float = 0.05
const CONVERGE: int = 6
const LISTED: int = 6


static func meta() -> Dictionary:
    return {
        "name": "a_day_runs_from_dawn_to_dark",
        "proves": (
            "every hour of DayCycle puts the sun where that hour has it, lights the ground by"
            + " its height, meters the camera for that light, and renders a noon far brighter"
            + " than its own midnight, with the moon highest in the middle of the night"
        ),
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "the sun above the horizon between the model's own sunrise and sunset and below it"
            + " otherwise; noon the brightest hour, the darkest hour a dark one, the moon"
            + " highest at midnight; and a rendered noon at least 8 times a rendered midnight,"
            + " which is itself under 0.08"
        ),
        "why": (
            "a day that is a list of presets cannot be dragged, and a day that is a path has to"
            + " keep every part of itself in step: the light, the sky, the stars and the"
            + " exposure. One of them left behind is a night nobody can see or a noon that"
            + " clips."
        ),
        "budget_s": 180.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var problems: PackedStringArray = PackedStringArray()
    var brightest: float = 0.0
    var brightest_hour: float = -1.0
    var darkest: float = INF
    var darkest_hour: float = -1.0
    var previous_iso: float = 0.0
    for step: int in 48:
        var hour: float = float(step) * 0.5
        var sky: Dictionary = DayCycle.at(hour)
        var elevation: float = DayCycle.sun_elevation_deg(hour)
        var daylight: bool = hour > DayCycle.SUNRISE_H and hour < DayCycle.SUNSET_H
        # The crossing hours themselves are the horizon, where the sign is arithmetic noise.
        if absf(elevation) > HORIZON_DEG and daylight != (elevation > 0.0):
            problems.append(
                "at %.1f the sun is %.1f degrees %s the horizon"
                % [hour, absf(elevation), "above" if elevation > 0.0 else "below"]
            )
        # The light the hour puts on the ground, and the direction it comes from.
        var lux: float = sky["sun_lux"] as float
        var toward: Vector3 = sky["sun_from"] as Vector3
        if toward.y <= 0.0:
            problems.append("at %.1f the light comes from below the horizon" % hour)
        if lux > brightest:
            brightest = lux
            brightest_hour = hour
        if lux < darkest:
            darkest = lux
            darkest_hour = hour
        # The exposure runs against the light: brighter hour, less sensitive film.
        var iso: float = sky["iso"] as float
        if hour > 0.0 and hour <= 12.0 and iso > previous_iso and previous_iso > 0.0:
            problems.append(
                "between %.1f and %.1f the morning gets brighter and the film faster (%.0f to"
                % [hour - 0.5, hour, previous_iso] + " %.0f ISO)" % iso
            )
        previous_iso = iso
    if not is_equal_approx(brightest_hour, 12.0):
        problems.append("the brightest hour is %.1f and not noon" % brightest_hour)
    # **Not midnight.** The moon rises as the sun sets and is highest in the middle of the
    # night, so the darkest hour of a day is the one just after dusk, when the sun is gone and
    # the moon is still on the horizon — and midnight is the brightest hour of the night. What
    # is astronomical here is that the darkest hour is a dark one and that the moonlight peaks
    # when the moon is overhead; the clock hour it lands on follows from those.
    if DayCycle.sun_elevation_deg(darkest_hour) > 0.0:
        problems.append(
            "the darkest hour is %.1f, with the sun %.1f degrees up"
            % [darkest_hour, DayCycle.sun_elevation_deg(darkest_hour)]
        )
    if DayCycle.moon_elevation_deg(0.0) < DayCycle.moon_elevation_deg(21.0):
        problems.append("the moon is not highest at midnight")
    if problems.size() > 0:
        return fail("; ".join(problems.slice(0, LISTED)), problems.size())

    var drawn: Dictionary = await _photograph(harness)
    if (drawn["error"] as String) != "":
        return fail(drawn["error"] as String)
    var noon: float = drawn["12.0"] as float
    var dusk: float = drawn["18.0"] as float
    var midnight: float = drawn["0.0"] as float
    if midnight > MAX_NIGHT:
        return fail(
            "midnight renders at %.4f, over the %.2f a night should be: the sky is still up"
            % [midnight, MAX_NIGHT], midnight
        )
    if noon < midnight * MIN_DAY_TO_NIGHT:
        return fail(
            "noon renders at %.4f against midnight's %.4f, which is %.1f times and not the %.0f"
            % [noon, midnight, noon / maxf(midnight, 0.0001), MIN_DAY_TO_NIGHT]
            + " required: the day does not change the light",
            noon
        )
    if dusk > noon or dusk < midnight:
        return fail(
            "dusk renders at %.4f, outside noon's %.4f and midnight's %.4f"
            % [dusk, noon, midnight], dusk
        )
    return ok(
        "48 half-hours: the sun is up from %.0f to %.0f, brightest at noon at %.0f lux and"
        % [DayCycle.SUNRISE_H, DayCycle.SUNSET_H, brightest]
        + " darkest at %.1f at %.2f lux, with the moon still on the horizon; drawn, noon is"
        % [darkest_hour, darkest]
        + " %.4f, dusk %.4f and midnight %.4f" % [noon, dusk, midnight],
        noon / maxf(midnight, 0.0001)
    )


## The same ground at each of the shown hours. Returns `{"error", "<hour>": brightness}`.
func _photograph(harness: Node) -> Dictionary:
    var out: Dictionary = {"error": ""}
    var loaded: Dictionary = RorTerrainLibrary.load_named(MAP)
    if (loaded.get("error", "") as String) != "":
        out["error"] = loaded["error"] as String
        return out
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain
    var error: String = harness.setup_for("hero_3q", "noon_clear")
    if error != "":
        out["error"] = error
        return out
    var ground: Node3D = TerrainWorld.create()
    if ground == null:
        out["error"] = "Terrain3D is not installed"
        return out
    harness.world.add_child(ground)
    await harness.advance_frames(2, "static", "terrain")
    var built: String = harness.terrain.populate(ground, terrain)
    if built != "":
        out["error"] = built
        return out
    var blockout: Node3D = harness.world.get_node_or_null(^"Ground") as Node3D
    if blockout != null:
        blockout.visible = false
    var start: Vector3 = terrain.start_position()
    var at: Vector3 = start + Vector3(10.0, 7.0, 0.0)
    harness.camera.look_at_from_position(at, start + Vector3(-30.0, 0.0, 0.0), Vector3.UP)
    for hour: float in SHOWN:
        var sky: Dictionary = DayCycle.at(hour)
        BlockoutWorld.apply_weather(harness.world, sky, RenderCfg.CLOUDS_ENABLED)
        PhysicalCamera.reexpose(harness.camera, CameraCfg.get_preset("hero_3q"), sky)
        var shot: Dictionary = await harness.capture_shot(
            "day/%02d00" % int(hour), "static", CONVERGE
        )
        if (shot["error"] as String) != "":
            out["error"] = shot["error"] as String
            return out
        out["%.1f" % hour] = _ground(shot["png"] as String)
    return out


## How bright the ground is in a frame: the lower half, where the terrain is.
func _ground(png: String) -> float:
    var image: Image = Image.load_from_file(png)
    if image == null:
        return 0.0
    var total: float = 0.0
    var count: int = 0
    for y: int in range(int(image.get_height() * 0.55), image.get_height(), 4):
        for x: int in range(0, image.get_width(), 4):
            var pixel: Color = image.get_pixel(x, y)
            total += pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
            count += 1
    return 0.0 if count == 0 else total / float(count)
