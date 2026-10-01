extends GateBase
## The sky lights the chart the way a lamp does: proportional to reflectance, proportional to its
## own brightness, and scaled by the camera's exposure by the same factor as a directional light.
##
## **Why this gate exists.** The sun-to-sky balance has been measured in this project four times
## and been wrong four times. The last round proved the fault was not where everybody looked:
## with the darkroom actually dark, `a_photographed_chart_measures_the_light` showed the direct
## lighting path is exact — linear in reflectance to 0.00%, a stop is a factor of two to 0.00%,
## and a two-light ratio measures 6.80:1 against 6.80:1 derived. Nothing is wrong with the
## renderer's lights, and nothing is wrong with the HDR capture.
##
## That leaves exactly one suspect, and this gate interrogates it: the **sky ambient path**. The
## symptom to explain is that a measured sun-to-sky ratio moved when the exposure moved — 6.4:1
## at ISO 32, 2.7:1 at ISO 64, 19.2:1 at ISO 16. A ratio of two lights cannot depend on the
## camera, any more than a photograph of two lamps tells you a different ratio when you stop
## down. So either the sky is not exposed like a light, or the earlier instrument was lying. The
## instrument has since been proven, so this measures the sky.
##
## **The sky here is a uniform panorama, not the atmosphere model.** Three reasons, all of them
## about being able to believe the answer:
##
## - A `PhysicalSkyMaterial` takes its sun direction from the first `DirectionalLight3D` in the
##   world, so the sky and the key light could not be varied independently — which is the exact
##   coupling that made the sun-to-sky question unanswerable. A panorama ignores lights.
## - A uniform sky has one number in it. Whatever the ambient path does to a constant is visible;
##   whatever it does to a Rayleigh gradient is a convolution nobody can check by eye.
## - The question is about the *path*, not about the atmosphere. Both sky materials reach the
##   scene through the same radiance map and the same ambient term.
##
## **What it found, for whoever reads this next.** Exposure parity holds exactly: one stop gains
## the key light and the sky by the same 2.0000x. So the sky *is* exposed like a light, and the
## exposure-dependent ratio that prompted this gate was the old uncalibrated instrument — fog and
## leaked sky ambient, both since removed — rather than anything in the sky path.
##
## The real fault is units. A `DirectionalLight3D` takes `light_intensity_lux` literally; a sky's
## energy does not go through that conversion at all. Measured here, **one unit of sky radiance
## delivers about 98,300 lx to a facing surface** — so a sky left at `energy_multiplier = 1.0`
## is worth roughly as much illuminance as the noon sun, which is why no amount of turning the
## sun up or the turbidity down ever brought the balance near clear daylight's figure.
##
## The constant is reproducible to ten significant digits and invariant to things that would
## betray a measurement artefact: it does not move with the sky's radiance over a 16x range, with
## the panorama's resolution (16x8 and 256x128 agree exactly), or with the radiance map's size.
## It sits 1.70% under 1e5 and that gap is **unexplained** — recorded as measured rather than
## rounded to the number it is near, because this project has been burned by the other choice.
##
## The conversion is reported, not asserted: an oracle for it wants the renderer's own documented
## convention, and a gate that asserted a constant it had itself measured would be writing its
## own expectation.

const PRESET: String = "diag_origin"
const CONVERGE: int = 3
## The key light, for the comparison. Straight on, so all of it lands and the cosine is 1.
const KEY_LUX: float = 20000.0
const KEY_FROM: Vector3 = Vector3(0.0, 0.0, 1.0)
const CHART_NORMAL: Vector3 = Vector3(0.0, 0.0, 1.0)
## The uniform sky's radiance, in whatever units the renderer's sky carries. Mid-scale on
## purpose: far enough above zero that a float capture has resolution, far enough below the
## key light that neither reading is near a clipping point that does not exist but might.
const SKY_RADIANCE: float = 2000.0
## A one-stop exposure change, applied as the photographer's own control: sensitivity.
const ISO_FACTOR: float = 2.0
## How far a measurement may sit from what was configured, as a share of it.
const LINEARITY_TOLERANCE: float = 0.02
const GAIN_TOLERANCE: float = 0.02
## Exposure parity: how far the sky's response to a stop may differ from the key light's.
##
## Tight, and deliberately so. This is the quantity the whole sun-to-sky confusion reduces to,
## and the drift that prompted the gate was not small — a measured ratio halving and tripling
## across two stops. A tolerance loose enough to absorb that would absorb the bug with it, which
## this project has done once already and does not intend to repeat.
const PARITY_TOLERANCE: float = 0.01


static func meta() -> Dictionary:
    return {
        "name": "the_sky_is_a_light_like_any_other",
        "proves": "sky ambient is linear in reflectance, proportional to the sky's own radiance, and takes the same exposure gain as a directional light — and reports the illuminance a unit of sky radiance delivers",
        "builds_on": ["a_photographed_chart_measures_the_light"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "a sky-lit wedge linear within %.0f%%, doubling the sky's radiance doubling every"
            % (LINEARITY_TOLERANCE * 100.0)
            + " patch within %.0f%%, and a one-stop exposure change gaining the sky-lit chart"
            % (GAIN_TOLERANCE * 100.0)
            + " and the key-lit chart by the same factor within %.0f%%"
            % (PARITY_TOLERANCE * 100.0)
        ),
        "why": (
            "a measured sun-to-sky ratio moved with the exposure — 6.4:1 at ISO 32, 2.7:1 at 64,"
            + " 19.2:1 at 16 — which is impossible for a ratio of two lights. The direct lighting"
            + " path and the HDR capture have since been proven exact against a step wedge, so"
            + " the sky ambient path is the only remaining place that drift can live. Until this"
            + " is nailed down no sun-to-sky number this project reports means anything."
        ),
        "budget_s": 300.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)
    harness.use_measurement_environment()
    PhotoChart.clear_stage(harness.world)
    var environment: Environment = _environment(harness)
    if environment == null:
        return fail("the world has no environment to configure")
    var lens: CameraAttributesPhysical = harness.camera.attributes as CameraAttributesPhysical
    if lens == null:
        return fail("the camera has no physical attributes, so there is no exposure to bracket")

    for patch: MeshInstance3D in PhotoChart.build_wedge():
        harness.world.add_child(patch)
    var key: DirectionalLight3D = PhotoChart.build_light("Key", KEY_FROM, KEY_LUX)
    harness.world.add_child(key)
    harness.camera.look_at_from_position(
        Vector3(0.0, 0.0, PhotoChart.camera_distance()), Vector3.ZERO, Vector3.UP
    )
    await harness.advance_frames(1, "static", "sky")
    var at: PackedVector2Array = PhotoChart.patch_pixels(harness.camera)
    var base_iso: float = lens.exposure_sensitivity

    # The key light alone, at two exposures. This is the reference the sky is held against, and
    # it is measured here rather than taken from the other gate on purpose: the same process,
    # the same frame, the same instrument. A reference read in a different run is a second
    # instrument nobody calibrated.
    var key_base: PackedFloat32Array = await _photograph(harness, at, "sky/key")
    lens.exposure_sensitivity = base_iso * ISO_FACTOR
    var key_pushed: PackedFloat32Array = await _photograph(harness, at, "sky/key_pushed")
    lens.exposure_sensitivity = base_iso

    # Now the sky alone: the key light off, and the uniform panorama is the only light there is.
    key.visible = false
    var material: PanoramaSkyMaterial = _install_uniform_sky(environment)
    var sky_base: PackedFloat32Array = await _photograph(harness, at, "sky/sky")
    lens.exposure_sensitivity = base_iso * ISO_FACTOR
    var sky_pushed: PackedFloat32Array = await _photograph(harness, at, "sky/sky_pushed")
    lens.exposure_sensitivity = base_iso
    # And the sky's own brightness doubled, which is its gain rather than the camera's.
    material.energy_multiplier = 2.0
    var sky_brighter: PackedFloat32Array = await _photograph(harness, at, "sky/sky_brighter")
    material.energy_multiplier = 1.0

    for shot: PackedFloat32Array in [key_base, key_pushed, sky_base, sky_pushed, sky_brighter]:
        if shot.is_empty():
            return fail("a photograph could not be taken; see the capture error above")
    if PhotoChart.mean(sky_base) <= 0.0:
        return fail(
            "the sky lit nothing: a uniform panorama of %.0f radiance with ambient taken from"
            % SKY_RADIANCE + " the sky photographed as black, so the ambient path is not"
            + " reaching the surface at all and the rest of this gate cannot be measured"
        )

    # 1. Linear in reflectance under the sky, the same check the key light passes. Ambient is a
    #    different term in the shader from direct light, so passing it there says nothing here.
    var worst_linear: float = PhotoChart.spread(PhotoChart.per_reflectance(sky_base))
    if worst_linear > LINEARITY_TOLERANCE:
        return fail(
            "the sky-lit wedge is not linear in reflectance: patch-over-reflectance spreads"
            + " %.1f%% (%s). Ambient that is not proportional to albedo is not light."
            % [worst_linear * 100.0, PhotoChart.row(sky_base)],
            worst_linear
        )

    # 2. The sky's own brightness is a gain: double its radiance, double every patch.
    var sky_gain: float = _worst_factor(sky_base, sky_brighter, 2.0)
    if sky_gain > GAIN_TOLERANCE:
        return fail(
            "doubling the sky's radiance moved a patch %.1f%% away from a factor of two, so the"
            % (sky_gain * 100.0) + " sky's brightness is not a gain and no sky can be metered"
            + " against a lamp",
            sky_gain
        )

    # 3. Exposure parity — the question the gate was written for. Exposure is a property of the
    #    camera, so one stop must be the same factor on every light in the frame. If the sky and
    #    the key light disagree here, a sun-to-sky ratio measured at one exposure is a different
    #    number at another, which is exactly the drift that has been chased for four rounds.
    var key_factor: float = _factor(key_base, key_pushed)
    var sky_factor: float = _factor(sky_base, sky_pushed)
    var parity: float = absf(sky_factor - key_factor) / maxf(key_factor, 0.000001)
    if parity > PARITY_TOLERANCE:
        return fail(
            "a one stop exposure change gains the key light by %.4fx and the sky by %.4fx —"
            % [key_factor, sky_factor]
            + " %.1f%% apart. The sky is not exposed like a light, so any sun-to-sky ratio this"
            % (parity * 100.0)
            + " renderer reports is a function of the camera as well as of the sky, and the"
            + " ratio has to be taken at a stated exposure or normalised out before it means"
            + " anything.",
            parity
        )

    # The conversion, reported rather than asserted: what illuminance a sky of unit radiance
    # delivers to a surface, in the same lux the key light is stated in.
    var incident: float = PhotoChart.incident_lux(KEY_LUX, KEY_FROM, CHART_NORMAL)
    var per_unit: float = (
        incident * PhotoChart.mean(sky_base)
        / maxf(PhotoChart.mean(key_base), 0.000001) / SKY_RADIANCE
    )
    return ok(
        "the sky is a light: sky-lit wedge linear to %.2f%%, doubling its radiance doubles every"
        % (worst_linear * 100.0)
        + " patch to %.2f%%, and one stop gains the key by %.4fx and the sky by %.4fx (%.2f%%"
        % [sky_gain * 100.0, key_factor, sky_factor, parity * 100.0]
        + " apart). A sky of unit radiance delivers %.2f lx to a facing surface — the sky's"
        % per_unit
        + " energy is not the lux a light is stated in, and that conversion is what a"
        + " sun-to-sky ratio has been missing.",
        per_unit
    )


## The world's environment, which this gate reconfigures rather than replaces: the preset's own
## environment is what every other gate measures through, and a gate that built a second one
## would be measuring a renderer nobody else uses.
func _environment(harness: Node) -> Environment:
    var holder: WorldEnvironment = (
        harness.world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    )
    return holder.environment if holder != null else null


## A sky of one constant radiance, and the ambient taken from it.
##
## `PanoramaSkyMaterial` and not the atmosphere model, because a panorama does not look at the
## scene's directional lights — see the file header. The image is tiny: a uniform sky needs one
## value, and the radiance map is a convolution of a constant whatever resolution it starts at.
func _install_uniform_sky(environment: Environment) -> PanoramaSkyMaterial:
    # Tiny on purpose, and measured rather than assumed: 16x8 and 256x128 produce the same
    # conversion to ten significant digits, so the resolution is not part of the answer.
    var image: Image = Image.create_empty(16, 8, false, Image.FORMAT_RGBAF)
    image.fill(Color(SKY_RADIANCE, SKY_RADIANCE, SKY_RADIANCE, 1.0))
    var material: PanoramaSkyMaterial = PanoramaSkyMaterial.new()
    material.panorama = ImageTexture.create_from_image(image)
    material.energy_multiplier = 1.0
    var sky: Sky = Sky.new()
    sky.sky_material = material
    # Quality rather than real time: the real-time path is an approximation of the radiance
    # convolution, and an approximation is the one thing a calibration cannot be read through.
    sky.process_mode = Sky.PROCESS_MODE_QUALITY
    sky.radiance_size = Sky.RADIANCE_SIZE_128
    environment.sky = sky
    environment.background_mode = Environment.BG_SKY
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    environment.ambient_light_sky_contribution = 1.0
    environment.ambient_light_energy = 1.0
    return material


## The factor between two photographs, taken over the whole wedge so one patch cannot carry it.
func _factor(before: PackedFloat32Array, after: PackedFloat32Array) -> float:
    return PhotoChart.mean(after) / maxf(PhotoChart.mean(before), 0.000001)


## The worst patch's departure from an expected factor, as a share of that factor. Per patch and
## not on the mean: a mean hides a response that is a gain in the highlights and an offset in the
## shadows, which is the shape both faults found by this wedge actually had.
func _worst_factor(
    before: PackedFloat32Array, after: PackedFloat32Array, expected: float
) -> float:
    var worst: float = 0.0
    for index: int in before.size():
        if before[index] <= 0.0:
            return INF
        worst = maxf(worst, absf(after[index] / before[index] - expected) / expected)
    return worst


## One HDR photograph, read at each patch.
func _photograph(
    harness: Node, at: PackedVector2Array, out_dir: String
) -> PackedFloat32Array:
    var shot: Dictionary = await harness.capture_hdr(out_dir, "static", CONVERGE)
    if (shot["error"] as String) != "":
        push_error(shot["error"])
        return PackedFloat32Array()
    var image: Image = shot["image"] as Image
    if image == null:
        return PackedFloat32Array()
    return PhotoChart.read_patches(image, at)
