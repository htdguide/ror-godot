extends GateBase
## The brightest place in a captured sky is where the scene's own sun is.
##
## An HDRI is a photograph of a real sky, and the sun in it is wherever it was when the picture was
## taken. The scene's sun is a `DirectionalLight3D` placed by the weather preset. Nothing connects
## the two but a number written down, and if that number is wrong the result is a scene with two
## suns in it: the shadows fall one way and the bright spot in the sky is somewhere else. It
## survives every other check in this project, because every one of them photographs one or the
## other.
##
## **The convention is the trap and this is what caught it.** The equirectangular panorama's
## longitude runs the opposite way to the obvious reading of it — Godot's own `atan(x, z)` divided
## by *minus* two pi — so a sun direction worked out from the image by hand lands mirrored in x.
## Measured both ways against the same map: the mirrored direction put the solar disc 2 pixels from
## the centre of the frame at 65,408 units, and the unmirrored one put a sky of 0.3 there.

## Every weather preset that names a captured sky is held to this, and every hour of the day
## cycle whose sun is high enough for its captured sky to be most of what is drawn.
const PRESET: String = "diag_origin"
const HOURS: Array[float] = [9.0, 10.0, 12.0, 14.0, 15.0]
## How much of an hour has to be its captured sky before this is asked of it. Nine tenths, which
## is the band `SkyMaps.captured_share` holds to about eleven degrees of elevation: past that the
## gradient is most of the sky and there is no photographed sun left to disagree with.
const MOSTLY_CAPTURED: float = 0.9
const SETTLE_FRAMES: int = 3
## How far the brightest direction in the sky may sit from the sun, in degrees. The disc itself is
## about half a degree across and a dusk map's brightest region is a glow rather than a disc, so
## this is wide enough for a sky whose sun is in the haze and far tighter than a wrong convention,
## which mirrors the direction and lands tens of degrees out.
const MOST_IT_MAY_MISS_DEG: float = 12.0


static func meta() -> Dictionary:
    return {
        "name": "a_captured_sky_and_its_sun_agree",
        "proves": "the brightest direction in every captured sky is the direction the scene's own sun light comes from, so the shadows fall away from the bright spot in the sky",
        "builds_on": ["the_sky_does_not_follow_the_camera"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "every captured sky's brightest direction within %.0f degrees of its sun" % MOST_IT_MAY_MISS_DEG,
        "why": (
            "the sun in a photographed sky and the sun casting the shadows are two separate"
            + " numbers, and a scene with them disagreeing has two suns in it. The panorama's own"
            + " longitude convention runs the opposite way to the obvious reading, so the mistake"
            + " this catches is one a careful person makes."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var captured: PackedStringArray = PackedStringArray()
    for name: String in WeatherCfg.PRESETS.keys():
        if not SkyMaps.present(WeatherCfg.get_preset(name)):
            continue
        captured.append(name)
    if captured.is_empty():
        return ok("skipped: no captured skies in this checkout", 0)
    # And the hours of the day cycle, which turn the same map as the sun crosses the sky: the
    # yaw is worked out per hour, so one hour agreeing says nothing about the next.
    for hour: float in HOURS:
        # Only the hours a captured sky is actually most of. A map is faded out where its own sun
        # has drifted from the hour's — see `SkyMaps.captured_share` — and an hour drawn as the
        # stated gradient has no photographed sun to agree or disagree with.
        if float(DayCycle.at(hour).get("hdri_mix", 0.0)) >= MOSTLY_CAPTURED:
            captured.append("%04.1f h" % hour)

    var reported: PackedStringArray = PackedStringArray()
    var worst: float = 0.0
    for name: String in captured:
        var err: String = harness.setup_for(PRESET, _weather_for(name))
        if err != "":
            return fail(err)
        if name.ends_with(" h"):
            BlockoutWorld.apply_weather(harness.world, DayCycle.at(name.to_float()), false)
        clear_fog(harness)
        for child: Node in harness.world.get_children():
            if child is MeshInstance3D:
                (child as MeshInstance3D).visible = false
        var sun: DirectionalLight3D = harness.world.get_node_or_null(^"Sun") as DirectionalLight3D
        if sun == null:
            return fail("%s has no sun to agree with" % name)
        # A directional light travels along its own -Z, so the sun itself is the other way.
        var toward_sun: Vector3 = sun.global_transform.basis.z
        # Pointed at the sun, so that a map whose brightest place is somewhere else shows it as an
        # angle off the middle of the frame rather than as nothing at all.
        harness.camera.look_at_from_position(
            Vector3.ZERO, toward_sun * 100.0, Vector3.UP
        )
        var shot: Dictionary = await harness.capture_hdr(
            "captured_sky/%s" % name, "static", SETTLE_FRAMES
        )
        if (shot["error"] as String) != "":
            return fail(shot["error"] as String)
        var image: Image = shot["image"] as Image
        if image == null:
            return fail("the capture of %s could not be read" % name)
        var brightest: Vector3 = _brightest_direction(harness.camera, image)
        if brightest == Vector3.ZERO:
            return fail("%s has nothing bright enough in it to find" % name)
        var missed: float = rad_to_deg(brightest.angle_to(toward_sun))
        worst = maxf(worst, missed)
        reported.append("%s %.1f deg" % [name, missed])
        if missed > MOST_IT_MAY_MISS_DEG:
            return fail(
                "%s has its brightest sky %.1f degrees from its sun, over the %.0f allowed:"
                % [name, missed, MOST_IT_MAY_MISS_DEG]
                + " the shadows and the sky disagree about where the sun is",
                missed
            )
    return ok(
        "%d captured skies, each with its sun where its light is: %s"
        % [captured.size(), ", ".join(reported)],
        worst
    )


## Which way the brightest pixel in the frame lies, in the world.
## A named hour is applied over whatever weather the harness built; anything else is a preset.
func _weather_for(name: String) -> String:
    return "noon_clear" if name.ends_with(" h") else name


func _brightest_direction(camera: Camera3D, image: Image) -> Vector3:
    var size: Vector2i = image.get_size()
    var peak: float = 0.0
    var at: Vector2i = Vector2i(-1, -1)
    for y: int in size.y:
        for x: int in size.x:
            var colour: Color = image.get_pixel(x, y)
            var luma: float = colour.r * 0.2126 + colour.g * 0.7152 + colour.b * 0.0722
            if luma > peak:
                peak = luma
                at = Vector2i(x, y)
    if at.x < 0:
        return Vector3.ZERO
    return camera.project_ray_normal(Vector2(at))
