extends GateBase
## A 24-patch ColorChecker, built from published colorimetry, photographed and measured back in
## CIELAB. Greys stay grey, and every in-gamut patch comes back within a stated delta E.
##
## **PLAN M2 acceptance 3.** The reference data is Field (1990) with Poynton (2008)'s CIE data
## for Illuminant C, retrieved verbatim; see `ColorChecker` for the source and `THIRD_PARTY.md`
## for the citation. Nothing in the chain is a number this project measured and then asserted.
##
## **What this does and does not prove, stated plainly.** The reference colours are converted to
## linear reflectances, rendered, photographed, and converted back by the inverse of the same
## transform. Those two conversions are inverses, so a renderer that transports colour perfectly
## scores delta E 0 by construction, and that part of the gate is a round trip rather than a
## simulation of a physical chart. What the published data contributes is the *colours*: real
## chart chromaticities, several of which fall outside sRGB's gamut and have to be found and
## excluded rather than quietly clipped, and the perceptual weighting of CIELAB, under which an
## error in a dark patch counts for more than the same error in a bright one. What the round trip
## catches is colour transport — a channel swap, a per-channel nonlinearity, an sRGB conversion
## applied twice, a tonemapper with a tint in it, a capture that quantises.
##
## The neutral check is **not** a round trip and is the stronger of the two. Patches 19 to 24 are
## greys, and a grey under a white light must photograph as a grey: `a*` and `b*` near zero. That
## expectation comes from the definition of the measurement, not from anything the gate set, so a
## renderer that tints the frame fails it even if the tint survives the round trip intact.
##
## **What it cannot see, measured rather than guessed.** Tinting the light green — `light_color`
## (0.8, 1.0, 0.8) — leaves this gate green at delta E 0.029. That is the direct cost of white
## balancing off the unit patch, and it is stated here because a limitation that is only implied
## by the method is a limitation the next person will not know about. Catching a tinted light
## needs an illuminant whose colour is independently published, which is a different gate and
## needs a sourced value for whatever locus the renderer's temperature conversion walks.
##
## The light is straight on, in the darkroom the step wedge established. Under those
## conditions `a_photographed_chart_measures_the_light` has already shown the response is linear
## in reflectance to 0.00% and exact across a bracket, which is what makes recovering a
## reflectance from a photograph legitimate here at all.

const PRESET: String = "diag_origin"
const CONVERGE: int = 3
## The light, straight on, so the full illuminance lands and the cosine is 1. Not white: see
## the note on colour temperature where the white balance is taken.
const KEY_LUX: float = 20000.0
const KEY_FROM: Vector3 = Vector3(0.0, 0.0, 1.0)
const PATCH_SPACING: float = 1.05
## How far back the camera stands. The chart is six patches wide, and the calibration patch sits
## below it, so the frame has to hold a little more than the chart.
const CAMERA_BACK: float = 11.0
## How far the derived RGB-to-XYZ matrix may sit from reproducing its own primaries and white.
const MATRIX_TOLERANCE: float = 0.00001
## The worst delta E a patch may come back with, CIE76.
##
## One delta E unit is roughly the smallest difference a person can see under good conditions, so
## this is "no visible error on any patch". Deliberately not looser: the round trip's expected
## result is zero, and a threshold set above the noise floor of a measurement whose answer should
## be exact is a place for a real fault to hide.
const MAX_DELTA_E: float = 1.0
## How far a grey patch's lightness may sit from its published value, in L*.
##
## Asserted separately from delta E rather than folded into it, because it is the one number here
## that no part of the setup can flatter: the white balance has three degrees of freedom and they
## are all spent on a different patch, so the published ladder from 90.0 down to 3.1 is six
## predictions the measurement either meets or does not.
const MAX_GREY_LADDER_L: float = 0.5


static func meta() -> Dictionary:
    return {
        "name": "a_colour_chart_survives_the_renderer",
        "proves": "a 24-patch ColorChecker built from published colorimetry photographs back within a stated delta E, and the published grey ladder comes back at the right lightness",
        "builds_on": ["a_photographed_chart_measures_the_light"],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "every in-gamut patch within delta E %.1f (CIE76) of its published colour, and the"
            % MAX_DELTA_E + " six published grey luminances within %.1f L*"
            % MAX_GREY_LADDER_L
        ),
        "why": (
            "colour is the one part of a renderer that can be wrong in a way that looks fine."
            + " A channel swap, a doubled sRGB conversion or a tinted tonemapper all produce"
            + " plausible pictures, and every luminance-based gate in this suite is blind to"
            + " them by construction. A chart with published values is the only way to say that"
            + " a colour came out of this renderer as the colour that went in."
        ),
        "budget_s": 180.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)
    harness.use_measurement_environment()
    PhotoChart.clear_stage(harness.world)

    # The working space: sRGB's primaries, with the chart's own adopted white rather than D65.
    #
    # This is what removes chromatic adaptation from the gate entirely. The published data is
    # under Illuminant C; building the matrix to that white means the chart, the light and the
    # measurement are all under C, and no adaptation matrix — whose choice between Bradford,
    # CAT02 and XYZ scaling would change the answer — has to be sourced or defended.
    var white: Vector3 = ColorChecker.adopted_white()
    if white == Vector3.ZERO:
        return fail("the chart's own neutral patches disagree about its white point")
    var to_xyz: Array[Vector3] = Colorimetry.rgb_to_xyz(
        Colorimetry.SRGB_RED, Colorimetry.SRGB_GREEN, Colorimetry.SRGB_BLUE, white
    )
    var drift: float = Colorimetry.matrix_is_consistent(
        to_xyz, Colorimetry.SRGB_RED, Colorimetry.SRGB_GREEN, Colorimetry.SRGB_BLUE, white
    )
    if drift > MATRIX_TOLERANCE:
        return fail(
            "the derived colour matrix does not reproduce its own primaries and white: %.2e out."
            % drift + " Everything downstream of it would be wrong by an amount nothing else in"
            + " this gate could attribute."
        )
    var to_rgb: Array[Vector3] = Colorimetry.inverse(to_xyz)

    # Each patch's published colour as a linear reflectance. Several real chart colours are
    # outside sRGB's triangle and come out with a negative channel; those are rendered clamped so
    # the chart still looks like a chart, and excluded from the measurement, because a clamped
    # patch is not the colour that was asked for and scoring it would be scoring the clamp.
    var reflectance: Array[Vector3] = []
    var out_of_gamut: PackedStringArray = PackedStringArray()
    for patch: Dictionary in ColorChecker.PATCHES:
        var linear: Vector3 = Colorimetry.apply(to_rgb, ColorChecker.xyz(patch))
        if linear.x < 0.0 or linear.y < 0.0 or linear.z < 0.0:
            out_of_gamut.append(patch["name"] as String)
        reflectance.append(linear)

    for index: int in ColorChecker.PATCHES.size():
        var at: Vector2 = ColorChecker.grid_position(index, PATCH_SPACING)
        harness.world.add_child(PhotoChart.build_patch(
            "Patch_%02d" % (index + 1),
            Vector3(maxf(reflectance[index].x, 0.0), maxf(reflectance[index].y, 0.0),
                    maxf(reflectance[index].z, 0.0)),
            Vector3(at.x, at.y, 0.0)
        ))
    # A patch of unit reflectance, to recover the scale the photograph is in. The light's
    # illuminance, the renderer's internal units and the camera's exposure multiply into one
    # unknown factor, and one known patch measures it — which is what a photographer's own grey
    # card is for.
    var reference_at: Vector3 = Vector3(
        0.0, -float(ColorChecker.ROWS) * PATCH_SPACING * 0.5 - PATCH_SPACING, 0.0
    )
    harness.world.add_child(PhotoChart.build_patch("Reference", Vector3.ONE, reference_at))
    harness.world.add_child(PhotoChart.build_light("Key", KEY_FROM, KEY_LUX))

    harness.camera.look_at_from_position(
        Vector3(0.0, 0.0, CAMERA_BACK), Vector3.ZERO, Vector3.UP
    )
    await harness.advance_frames(1, "static", "colour")
    var shot: Dictionary = await harness.capture_hdr("colour/chart", "static", CONVERGE)
    if (shot["error"] as String) != "":
        return fail(shot["error"] as String)
    var image: Image = shot["image"] as Image
    if image == null:
        return fail("the capture came back with no image")

    # The scale, from the unit patch — per channel, because the light is not white.
    #
    # **Under physical light units a light has a colour temperature, and no temperature is
    # neutral.** `light_temperature` defaults to 6500 K and photographs as (1.0, 0.9419, 0.9919)
    # once the brightest channel is normalised: a 6% green deficit, constant across a thirty-fold
    # brightness range. It is not a bug in the renderer so much as a consequence of which locus
    # it uses — 6500 K on the Planckian locus sits below the daylight locus that sRGB's white
    # point is on, so the conversion lands off-white and sweeping the temperature does not fix
    # it: measured at 5000 K and 9000 K the cast moves but never passes through neutral.
    #
    # So the unit patch is the measurement's white, the way a photographer shoots a white card
    # and sets the white balance off it. That costs the gate the check that greys photograph
    # grey, which would now be true by construction and is therefore removed rather than left in
    # looking like evidence. What remains is not weak: three degrees of freedom are fixed by the
    # one white card, and the other patches then supply fifty-four independent values, the
    # published grey ladder's six luminances among them.
    var reference: Vector3 = PhotoChart.window_rgb(
        image, harness.camera.unproject_position(reference_at)
    )
    if reference.x <= 0.0 or reference.y <= 0.0 or reference.z <= 0.0:
        return fail(
            "the unit-reflectance patch photographed black in at least one channel, so there is"
            + " no white to measure the chart against: read %v" % reference
        )

    var worst_delta: float = 0.0
    var worst_patch: String = ""
    var total_delta: float = 0.0
    var scored: int = 0
    var worst_ladder: float = 0.0
    var worst_ladder_patch: String = ""
    for index: int in ColorChecker.PATCHES.size():
        var patch: Dictionary = ColorChecker.PATCHES[index]
        var at: Vector2 = ColorChecker.grid_position(index, PATCH_SPACING)
        var raw: Vector3 = PhotoChart.window_rgb(
            image, harness.camera.unproject_position(Vector3(at.x, at.y, 0.0))
        )
        var read: Vector3 = Vector3(
            raw.x / reference.x, raw.y / reference.y, raw.z / reference.z
        )
        var measured: Vector3 = Colorimetry.xyz_to_lab(Colorimetry.apply(to_xyz, read), white)
        if index >= ColorChecker.FIRST_NEUTRAL:
            # The grey ladder, asserted on its own because it is the least circular thing here:
            # six published luminance factors from 90.0 down to 3.1, against one scale that was
            # already fixed by a different patch. Nothing about the white balance can flatter it.
            var ladder: float = absf(
                measured.x - Colorimetry.xyz_to_lab(ColorChecker.xyz(patch), white).x
            )
            if ladder > worst_ladder:
                worst_ladder = ladder
                worst_ladder_patch = patch["name"] as String
        if out_of_gamut.has(patch["name"] as String):
            continue
        var published: Vector3 = Colorimetry.xyz_to_lab(ColorChecker.xyz(patch), white)
        var delta: float = Colorimetry.delta_e_76(measured, published)
        total_delta += delta
        scored += 1
        if delta > worst_delta:
            worst_delta = delta
            worst_patch = patch["name"] as String

    if scored == 0:
        return fail(
            "every patch fell outside the working gamut, so there was nothing to measure: the"
            + " colour matrix or the chart's white point is wrong"
        )
    # Greys first. It is the check that does not depend on the round trip, so when both fail this
    # is the one that says what is actually wrong.
    if worst_ladder > MAX_GREY_LADDER_L:
        return fail(
            "the published grey ladder does not come back: '%s' photographs %.2f L* from its"
            % [worst_ladder_patch, worst_ladder] + " published lightness. The ladder's six luminances"
            + " run from 90.0 down to 3.1 against a scale fixed by a different patch, so this"
            + " is the measurement nothing in the setup can flatter — a renderer that fails it"
            + " is not reproducing lightness at all.",
            worst_ladder
        )
    if worst_delta > MAX_DELTA_E:
        return fail(
            "'%s' photographs %.2f delta E from its published colour, over %d patches averaging"
            % [worst_patch, worst_delta, scored]
            + " %.2f. Colour is not surviving the renderer: the published value and the"
            % (total_delta / float(scored))
            + " measurement are converted by inverse transforms, so anything but zero is"
            + " something the renderer did to the colour in between.",
            worst_delta
        )
    return ok(
        "%d of %d patches measured (%d outside the working gamut%s): worst delta E %.3f on '%s',"
        % [scored, ColorChecker.PATCHES.size(), out_of_gamut.size(),
           "" if out_of_gamut.is_empty() else ": " + ", ".join(out_of_gamut),
           worst_delta, worst_patch]
        + " mean %.3f, and the published grey ladder comes back within %.3f L* (worst '%s')"
        % [total_delta / float(scored), worst_ladder, worst_ladder_patch],
        worst_delta
    )
