extends GateBase
## Opening the lens a stop, halving the shutter speed, or doubling the film all do the same thing,
## and that thing is exactly a factor of two.
##
## **The oracle is what a stop means.** Exposure is the photographer's three numbers and the
## relations between them are definitions, not measurements: a stop is a doubling of the light
## reaching the sensor, so `f/8` to `f/5.6` is one — the f-number falls by the square root of two
## because it is a ratio of diameters and the light goes as the area — and so is 1/125 s to 1/60,
## and so is ISO 100 to ISO 200. Three different controls, one factor, and a renderer either agrees
## or is applying exposure somewhere it should not.
##
## **This is the gate for the bug this project has already had twice.** Exposure applied a second
## time is invisible in any single frame: the picture is simply darker or brighter than it should
## be, and every judgement made from it is wrong by the same amount. It is also how a sky that
## carried the camera's exposure in its own radiance was caught — see `the_sky_does_not_follow_the_
## camera` — and the measurement there was this one, taken by hand.
##
## **The sky has to be re-metered with the camera, and forgetting it is what this gate caught
## first.** Changing the aperture and photographing again gave 2.1623 instead of 2 — and 1.4673 for
## half a stop, 4.9135 for two, which fits a frame where about eight per cent of the light is
## multiplied by the exposure twice. That was not the renderer: it was this gate. A sky carries the
## camera's exposure in its own radiance so that it does not follow the film, and `WorldSky.reexpose`
## is what puts the new camera into it. Without that call the sky is still metered for the camera
## the world was built with, and its share of the frame is exposed once by the stale number and once
## by the new one. With it, the same three controls read 2.0084.
##
## The scene is this project's own noon rather than a lamp in the dark, because the sky is where
## this goes wrong and a gate that avoided it would be avoiding the claim. For the record, a grey
## patch lit by a single directional light and nothing else reads 2.0000, 2.0000 and 2.0000.
##
## The tonemapper is linear for the measurement, because a stop is a statement about the light
## arriving and a curve is a statement about what is done with it afterwards.
## `tonemap_and_exposure` holds the curve; this holds the lens.

const PRESET: String = "diag_topdown"
const WEATHER: String = "noon_clear"
const CONVERGE: int = 4
## The exposure every reading is taken against. A patch lit by a hundred thousand lux of noon has
## to land in the middle of the film at these, and still be there a stop either side.
const F_STOP: float = 8.0
const SHUTTER_SPEED: float = 250.0
const SENSITIVITY: float = 100.0
## A stop, in each of the three. The aperture moves by the square root of two because the light a
## lens passes goes as the area of its opening and the f-number is a diameter.
const ONE_STOP_APERTURE: float = 1.4142135624
## How far from exactly double a stop may land. 8-bit capture of a rendered frame, read off a
## patch that is a few hundred pixels across.
const TOLERANCE: float = 0.04
const PATCH_M: float = 3.0
const PATCH_AT: Vector3 = Vector3(0.0, 1.0, 0.0)
## The band a reading has to land in for a ratio between two of them to mean anything.
const USABLE: Vector2 = Vector2(0.03, 0.8)


static func meta() -> Dictionary:
    return {
        "name": "one_stop_is_one_stop",
        "proves": "opening the aperture one stop, doubling the shutter time and doubling the ISO each change the light in the frame by a factor of two, and by the same factor as each other",
        "builds_on": ["tonemap_and_exposure"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "each of the three within %.0f%% of a factor of two" % (TOLERANCE * 100.0),
        "why": (
            "an exposure applied twice looks exactly like a scene that is darker than it should"
            + " be, so nothing in a single frame gives it away and every brightness judged from"
            + " that frame inherits the error. This project has had that bug in its sky, where"
            + " the sun-to-sky balance moved with the film: 19.2:1 at ISO 16 and 1.6:1 at 128."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M2b",
    }


func run(harness: Node) -> Dictionary:
    var err: String = harness.setup_for(PRESET, WEATHER)
    if err != "":
        return fail(err)
    clear_fog(harness)
    var holder: WorldEnvironment = (
        harness.world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    )
    if holder == null or holder.environment == null:
        return fail("the world has no environment to meter against")
    # Linear, because a stop is a statement about the light and a curve is what happens after it.
    holder.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    holder.environment.tonemap_exposure = 1.0
    holder.environment.glow_enabled = false
    var ground: Node3D = harness.world.get_node_or_null(^"Ground") as Node3D
    if ground != null:
        ground.visible = false

    var attributes: CameraAttributesPhysical = (
        harness.camera.attributes as CameraAttributesPhysical
    )
    if attributes == null:
        return fail("the harness camera has no physical attributes to meter with")
    harness.world.add_child(_patch())
    var lamp: DirectionalLight3D = DirectionalLight3D.new()
    lamp.light_intensity_lux = 90000.0
    lamp.shadow_enabled = false
    lamp.look_at_from_position(Vector3(0.0, 8.0, 3.0), PATCH_AT, Vector3.UP)
    harness.world.add_child(lamp)

    var readings: Dictionary = {}
    for named: Array in [
        ["reference", F_STOP, SHUTTER_SPEED, SENSITIVITY],
        ["aperture", F_STOP / ONE_STOP_APERTURE, SHUTTER_SPEED, SENSITIVITY],
        ["shutter", F_STOP, SHUTTER_SPEED * 0.5, SENSITIVITY],
        ["film", F_STOP, SHUTTER_SPEED, SENSITIVITY * 2.0],
    ]:
        attributes.exposure_aperture = float(named[1])
        attributes.exposure_shutter_speed = float(named[2])
        attributes.exposure_sensitivity = float(named[3])
        harness.camera.attributes = attributes
        WorldSky.reexpose(harness.world, harness.camera)
        # **In light rather than in display pixels.** An 8-bit frame quantises a flat patch
        # identically in every pixel of it, so averaging buys nothing and one level is 4% of a
        # reading at this level — measured, the three controls agreed with each other to four
        # decimal places and all three sat 7.6% over a factor of two. The float capture has no
        # such floor.
        var shot: Dictionary = await harness.capture_hdr(
            "stops/%s" % (named[0] as String), "static", CONVERGE
        )
        if (shot["error"] as String) != "":
            return fail(shot["error"] as String)
        var image: Image = shot["image"] as Image
        if image == null:
            return fail("the capture at %s could not be read" % shot["exr"])
        var read: float = _at(harness, image, PATCH_AT)
        if read < USABLE.x or read > USABLE.y:
            return fail(
                "the %s frame reads %.4f, outside the %.2f to %.2f a ratio needs: the patch is"
                % [named[0], read, USABLE.x, USABLE.y]
                + " against the floor or the ceiling of the film rather than in it. %s"
                % shot["exr"],
                read
            )
        readings[named[0]] = read

    var reference: float = readings["reference"] as float
    var reported: PackedStringArray = PackedStringArray()
    var worst: float = 0.0
    var worst_said: String = ""
    for control: String in ["aperture", "shutter", "film"]:
        var ratio: float = (readings[control] as float) / reference
        reported.append("%s %.4fx" % [control, ratio])
        var off: float = absf(ratio - 2.0) / 2.0
        if off > absf(worst):
            worst = off
            worst_said = "%s gave %.4f times the light where a stop is 2" % [control, ratio]
    if absf(worst) > TOLERANCE:
        return fail(
            "%s, %.1f%% out against the %.0f%% allowed (%s, from %.4f). A stop is a definition,"
            % [worst_said, worst * 100.0, TOLERANCE * 100.0, ", ".join(reported), reference]
            + " so this is exposure being applied somewhere it should not be",
            worst
        )
    return ok(
        "from f/%.0f at 1/%.0f s and ISO %.0f reading %.4f: %s"
        % [F_STOP, SHUTTER_SPEED, SENSITIVITY, reference, ", ".join(reported)]
        + "; worst %.1f%% from a factor of two" % (absf(worst) * 100.0),
        absf(worst)
    )


## A flat grey patch facing the camera overhead, lit by this gate's own sun and nothing else.
func _patch() -> MeshInstance3D:
    var patch: MeshInstance3D = MeshInstance3D.new()
    var plane: PlaneMesh = PlaneMesh.new()
    plane.size = Vector2(PATCH_M, PATCH_M)
    patch.mesh = plane
    var grey: StandardMaterial3D = StandardMaterial3D.new()
    grey.albedo_color = Color(0.18, 0.18, 0.18)
    grey.roughness = 1.0
    grey.metallic = 0.0
    patch.material_override = grey
    patch.position = PATCH_AT
    return patch


func _at(harness: Node, image: Image, at: Vector3) -> float:
    var where: Vector2 = harness.camera.unproject_position(at)
    var size: Vector2i = image.get_size()
    var viewport: Vector2 = harness.render_viewport().get_visible_rect().size
    var x: int = clampi(int(where.x / viewport.x * float(size.x)), 0, size.x - 1)
    var y: int = clampi(int(where.y / viewport.y * float(size.y)), 0, size.y - 1)
    var total: float = 0.0
    var counted: int = 0
    for dy: int in range(-30, 31, 3):
        for dx: int in range(-30, 31, 3):
            # Already linear: this is the float capture, not an sRGB-encoded frame.
            total += image.get_pixel(
                clampi(x + dx, 0, size.x - 1), clampi(y + dy, 0, size.y - 1)
            ).get_luminance()
            counted += 1
    return total / maxf(float(counted), 1.0)
