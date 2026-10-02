extends GateBase
## Checks that the vehicle's bodywork blocks the sun instead of passing it through.
##
## The physics is the oracle and needs no reference image: an opaque object lit from the
## viewer's side is brighter than the same object, same camera, lit from behind. If the
## two are equally bright the surface is not responding to where the light is, which is
## what a person sees as the sun shining through the body.
##
## This catches a fault that every existing gate is blind to. Coverage, silhouette and
## assembly checks all ask whether the right pixels are there, and they were: the pixels
## were present, correctly placed, correctly textured, and lit from the wrong side.
##
## Two ways a surface stops responding to the light, both of which have happened here:
## vertex normals missing altogether, so there is no orientation to light; and vertex
## normals pointing the opposite way to the triangles they belong to, so the panel is lit
## from its far face.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const BASE_PRESET: String = "hero_3q"
const CONVERGE: int = 6
## A lit panel against an unlit one is a large difference, and the measurement averages
## over the whole visible body, so the bar can be well clear of noise. Measured on the
## fixed hero asset the ratio is far above this; with normals absent it sits at 1.0.
const MIN_LIT_RATIO: float = 1.25
## Below this a pixel is background, not bodywork. The measurement environment paints
## black behind the vehicle and hides the ground, so anything lit at all is the vehicle.
const BODY_LUMA_FLOOR: float = 0.02
## Enough of the frame must be vehicle for the average to mean anything.
const MIN_BODY_PIXELS: int = 20000
## Degrees the sun is lifted above the horizon. Straight-on light flattens the reading;
## a raking angle is both more realistic and more discriminating.
const SUN_ELEVATION_DEG: float = 25.0


static func meta() -> Dictionary:
    return {
        "name": "body_blocks_sun",
        "proves": "the bodywork occludes and responds to the sun rather than passing it through",
        # measuring how the bodywork takes the sun needs the bodywork built and drawn.
        "builds_on": ["vehicle_renders"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "the vehicle is at least %.2fx brighter lit from the camera's side than lit"
            % MIN_LIT_RATIO
            + " from behind, over at least %d body pixels" % MIN_BODY_PIXELS
        ),
        "why": (
            "an opaque body lit from the front is brighter than the same body lit from"
            + " behind; that is a property of the object, not of this renderer, so no"
            + " golden is involved. The number is far above the noise floor because the"
            + " failure mode it guards is total: with no usable normals the two renders"
            + " are identical and the ratio is exactly 1.0."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var err: String = harness.setup_for(BASE_PRESET)
    if err != "":
        return fail(err)
    clear_fog(harness)
    harness.use_measurement_environment()

    var built: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    var root: Node3D = built["root"] as Node3D
    harness.world.add_child(root)

    var sun: DirectionalLight3D = harness.world.get_node_or_null(^"Sun") as DirectionalLight3D
    if sun == null:
        return fail("the world has no Sun: this gate cannot place the light")
    # Shadows stay on. Half of "the sun comes through the body" is the near panel failing
    # to shadow the far one, and turning shadows off would hide exactly that.
    sun.shadow_enabled = true

    var bounds: AABB = VehicleBuilder.world_bounds(root)
    var subject: Vector3 = bounds.get_center()
    # Square on to the side of the truck, which presents the largest flat panel area and
    # so gives the measurement the most surface to average over.
    var eye: Vector3 = subject + Vector3(0.0, 0.35 * bounds.size.y, 2.2 * bounds.size.length())
    harness.camera.look_at_from_position(eye, subject, Vector3.UP)

    var to_camera: Vector3 = (eye - subject).normalized()
    var front: Dictionary = await _render_lit(harness, sun, subject, to_camera, "front_lit")
    if (front["error"] as String) != "":
        return fail(front["error"] as String)
    var back: Dictionary = await _render_lit(harness, sun, subject, -to_camera, "back_lit")
    if (back["error"] as String) != "":
        return fail(back["error"] as String)

    # Framing is geometry, so it is measured on the lit frame.
    #
    # This used to take the smaller of the two counts, which conflates "is the vehicle in shot"
    # with "is this side of it lit". Body pixels are those above a luminance floor in a darkroom,
    # so the back-lit frame's count is a lighting measurement wearing a framing check's clothes —
    # and it collapsed the moment the vehicle stopped being lit by a reflection probe's stale
    # ambient, which is a bug being fixed rather than light this gate should ever have had.
    var pixels: int = front["pixels"] as int
    if pixels < MIN_BODY_PIXELS:
        return fail(
            "only %d body pixels in frame, under %d: the camera is not framing the"
            % [pixels, MIN_BODY_PIXELS]
            + " vehicle, so brightness here would not be a statement about the bodywork",
            pixels
        )
    # Both frames averaged over the *same* pixels: the ones the lit frame says are bodywork.
    #
    # Each frame used to be averaged over its own above-floor pixels, which is not a comparison of
    # one surface under two lights — it is a comparison of two different surfaces. The darker
    # frame's set is whatever survived the floor, so its mean is taken over only its brightest
    # survivors and the ratio is pulled towards one. Measured, that read 1.18 where a shared mask
    # reads the real figure.
    var compared: Dictionary = _compare(front["png"] as String, back["png"] as String)
    if (compared["error"] as String) != "":
        return fail(compared["error"] as String)
    var lit: float = compared["lit"] as float
    var unlit: float = compared["unlit"] as float
    var ratio: float = lit / maxf(unlit, 0.0001)
    if ratio < MIN_LIT_RATIO:
        return fail(
            "lit from the camera's side the body averages %.4f, lit from behind %.4f:"
            % [lit, unlit]
            + " a ratio of %.2f, under %.2f. The bodywork is not blocking or responding"
            % [ratio, MIN_LIT_RATIO]
            + " to the sun. See %s against %s." % [front["png"], back["png"]],
            ratio
        )
    return ok(
        "body is %.2fx brighter lit from the front than from behind (%.4f against %.4f"
        % [ratio, lit, unlit]
        + " over %d pixels): %s" % [pixels, front["png"]],
        ratio
    )


## Places the sun along `direction` and returns the mean luminance of the vehicle.
func _render_lit(
    harness: Node, sun: DirectionalLight3D, subject: Vector3, direction: Vector3, tag: String
) -> Dictionary:
    var lifted: Vector3 = (
        direction + Vector3.UP * tan(deg_to_rad(SUN_ELEVATION_DEG))
    ).normalized()
    sun.look_at_from_position(subject + lifted * 100.0, subject, Vector3.UP)
    var shot: Dictionary = await harness.capture_shot("body_blocks_sun/" + tag, "static", CONVERGE)
    if (shot["error"] as String) != "":
        return {"error": shot["error"], "luma": 0.0, "pixels": 0, "png": ""}
    var measured: Dictionary = _mean_body_luma(shot["png"] as String)
    measured["error"] = ""
    measured["png"] = shot["png"]
    return measured


## Averages both frames over one mask: the pixels the lit frame shows as bodywork.
##
## Returns {"error", "lit", "unlit"}.
func _compare(lit_png: String, unlit_png: String) -> Dictionary:
    var lit_image: Image = Image.load_from_file(lit_png)
    var unlit_image: Image = Image.load_from_file(unlit_png)
    if lit_image == null or unlit_image == null:
        return {"error": "a capture could not be read back", "lit": 0.0, "unlit": 0.0}
    if lit_image.get_size() != unlit_image.get_size():
        return {"error": "the two captures are different sizes", "lit": 0.0, "unlit": 0.0}
    var lit_total: float = 0.0
    var unlit_total: float = 0.0
    var count: int = 0
    for y: int in lit_image.get_height():
        for x: int in lit_image.get_width():
            var luma: float = lit_image.get_pixel(x, y).get_luminance()
            if luma < BODY_LUMA_FLOOR:
                continue
            lit_total += luma
            unlit_total += unlit_image.get_pixel(x, y).get_luminance()
            count += 1
    if count == 0:
        return {"error": "no bodywork pixels in the lit frame", "lit": 0.0, "unlit": 0.0}
    return {
        "error": "", "lit": lit_total / float(count), "unlit": unlit_total / float(count),
    }


## Returns {"luma": float, "pixels": int} over the pixels that are vehicle, not background.
func _mean_body_luma(png_path: String) -> Dictionary:
    var image: Image = Image.load_from_file(png_path)
    if image == null:
        return {"luma": 0.0, "pixels": 0}
    var total: float = 0.0
    var count: int = 0
    for y: int in image.get_height():
        for x: int in image.get_width():
            var luma: float = image.get_pixel(x, y).get_luminance()
            if luma < BODY_LUMA_FLOOR:
                continue
            total += luma
            count += 1
    return {"luma": total / float(maxi(count, 1)), "pixels": count}
