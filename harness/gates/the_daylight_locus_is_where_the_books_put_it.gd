extends GateBase
## The daylight locus this project computes lands on the published illuminants.
##
## **A blackbody and daylight are not the same white.** Godot's `light_temperature` walks the
## Planckian locus — what a black body glows at that temperature — while sRGB's white point is
## D65, which sits on the daylight locus, a different curve fitted to measured skylight. The two
## cross nowhere useful, which is why a light set to 6500 K in this project photographs as
## (1.0, 0.9419, 0.9919) with a 6% green deficit, and why no temperature is neutral.
##
## PLAN's M2 acceptance says catching a tinted light "needs an illuminant colour that is
## independently published, which is a separate gate and a sourced locus value". This is that
## value and that gate.
##
## **The oracle is the published chromaticity of each named illuminant**, not the formula. The
## formula is CIE 15's cubic in 1/T; the four D illuminants have tabulated chromaticities, and
## they are what the formula is held to. A transcription error in either shows up as a
## disagreement between them.
##
## **The named illuminants are not at round temperatures.** The D series was defined when the
## second radiation constant was 1.4380e-2 m K and it is 1.4388e-2 now, so D65 is 6503.6 K and
## not 6500. This gate was first written to *require* that correction to matter, on a
## remembered figure of 0.0008 — and failed, because the real difference is 0.00007 in x and the
## correction merely halves an already small residual. It reports the two distances now and turns
## on neither: a threshold chosen to separate them would be a threshold fitted to the answer.

## How far the formula may land from a published chromaticity. The published values are given to
## five decimals and the formula is a fit to them, so this is the fit's own residual.
const TOLERANCE: float = 0.0005


static func meta() -> Dictionary:
    return {
        "name": "the_daylight_locus_is_where_the_books_put_it",
        "proves": "the daylight chromaticity this project computes agrees with the published D50, D55, D65 and D75 values",
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "within %.4f of each published chromaticity" % TOLERANCE,
        "why": (
            "Godot's colour temperature walks the Planckian locus and sRGB's white is on the"
            + " daylight one, so every light here carries a 6% green deficit and no temperature"
            + " is neutral. Correcting that needs a locus whose numbers come from somewhere"
            + " other than this project."
        ),
        "budget_s": 20.0,
        "needs_gpu": false,
        "milestone": "M2",
    }


func run(_harness: Node) -> Dictionary:
    var problems: PackedStringArray = PackedStringArray()
    var worst: float = 0.0
    var worst_name: String = ""
    for name: String in DaylightLocus.PUBLISHED.keys():
        var published: Vector2 = DaylightLocus.PUBLISHED[name] as Vector2
        var computed: Vector2 = DaylightLocus.of_name(name)
        var apart: float = (computed - published).length()
        if apart > worst:
            worst = apart
            worst_name = name
        if apart > TOLERANCE:
            problems.append(
                "%s: computed (%.5f, %.5f), published (%.5f, %.5f), %.5f apart"
                % [name, computed.x, computed.y, published.x, published.y, apart]
            )
    if problems.size() > 0:
        return fail(
            "%d of %d illuminants are not where they are published: %s"
            % [problems.size(), DaylightLocus.PUBLISHED.size(), "; ".join(problems)],
            problems.size()
        )

    # What the correction is worth, reported rather than required: both the corrected and the
    # nominal temperatures land inside the tolerance, and a bound drawn between them would be a
    # bound drawn around the answer.
    var uncorrected: float = 0.0
    for name: String in DaylightLocus.PUBLISHED.keys():
        uncorrected = maxf(
            uncorrected,
            (
                DaylightLocus.chromaticity(DaylightLocus.NOMINAL_K[name] as float)
                - (DaylightLocus.PUBLISHED[name] as Vector2)
            ).length()
        )

    var daylight: Color = DaylightLocus.linear_srgb(
        (DaylightLocus.NOMINAL_K["D65"] as float) * DaylightLocus.PLANCK_CORRECTION
    )
    return ok(
        "D50, D55, D65 and D75 within %.6f of their published chromaticities (worst %s);"
        % [worst, worst_name]
        + " the uncorrected temperatures reach %.6f, so the correction halves it;" % uncorrected
        + " D65 shines (%.4f, %.4f, %.4f)" % [daylight.r, daylight.g, daylight.b],
        worst
    )
