extends GateBase
## Two captures of a static scene, taken at different frame indices in one run, must be
## identical pixel for pixel.
##
## This is the gate every image gate depends on. If a still scene does not photograph
## the same way twice, then no golden means anything and every later visual comparison
## is measuring noise. It is checked against an invariant rather than a stored image,
## so it cannot rot.

const PRESET: String = "diag_origin"
const GAP_FRAMES: int = 12
const MAX_MEAN_LUMA_ERROR: float = 0.0


static func meta() -> Dictionary:
    return {
        "name": "capture_stability",
        "proves": "a static scene captured twice in one run is bit-identical",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "mean luma error == %f between the two captures" % MAX_MEAN_LUMA_ERROR,
        "why": (
            "every image gate rests on this. If a still scene does not photograph the"
            + " same way twice then goldens are meaningless and visual comparisons"
            + " measure driver noise instead of the product."
        ),
        "budget_s": 60.0,
        "needs_gpu": true,
        "milestone": "M0",
    }


func run(harness: Node) -> Dictionary:
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)
    var first: Dictionary = await harness.capture_shot(
        "capture_stability/first", "static", HarnessCfg.CONVERGE_FRAMES
    )
    if first["error"] != "":
        return fail(first["error"] as String)
    var second: Dictionary = await harness.capture_shot(
        "capture_stability/second", "static", GAP_FRAMES
    )
    if second["error"] != "":
        return fail(second["error"] as String)

    var diff: Dictionary = ImgDiff.compare(
        first["png"] as String, second["png"] as String, MAX_MEAN_LUMA_ERROR
    )
    if diff.has("error"):
        return fail(diff["error"] as String)
    if not diff["pass"]:
        return fail(
            (
                "captures differ: mean luma error %s, worst pixel %s, worst region %s;"
                + " artifacts: %s and %s"
            )
            % [
                diff["mean_luma_error"],
                diff["worst_pixel"],
                diff["worst_region"],
                first["png"],
                second["png"],
            ],
            diff["mean_luma_error"]
        )
    return ok(
        "two captures %d frames apart are identical" % GAP_FRAMES, diff["mean_luma_error"]
    )
