extends GateBase
## Proves the harness can render, capture and report. The first gate, and the one that
## every other gate's credibility rests on.

const REQUIRED_PRESET: String = "diag_origin"
const MIN_DISTINCT_COLORS: int = 64
const SAMPLE_STRIDE: int = 7


static func meta() -> Dictionary:
    return {
        "name": "smoke",
        "proves": "the harness renders a window, captures a non-trivial PNG, writes a manifest and reports metrics",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": ">= %d distinct colours in the captured frame" % MIN_DISTINCT_COLORS,
        "why": (
            "a blank or single-colour capture is the exact failure mode of headless"
            + " rendering on macOS, and it would otherwise look like a passing gate."
            + " Counting distinct colours is the cheapest invariant that separates"
            + " 'rendered something' from 'wrote an empty buffer'."
        ),
        "budget_s": 30.0,
        "needs_gpu": true,
        "milestone": "M0",
    }


func run(harness: Node) -> Dictionary:
    var err: String = harness.setup_for(REQUIRED_PRESET)
    if err != "":
        return fail(err)
    var out_dir: String = "smoke"
    var shot: Dictionary = await harness.capture_shot(out_dir, "static", HarnessCfg.CONVERGE_FRAMES)
    if shot["error"] != "":
        return fail(shot["error"] as String)

    var image: Image = Image.load_from_file(shot["png"] as String)
    if image == null:
        return fail("cannot re-read captured PNG at %s" % shot["png"])
    var distinct: int = _count_distinct_colors(image)
    if distinct < MIN_DISTINCT_COLORS:
        return fail(
            "captured frame has %d distinct colours, need >= %d; artifact: %s"
            % [distinct, MIN_DISTINCT_COLORS, shot["png"]],
            distinct
        )
    return ok("captured %s with %d distinct colours" % [shot["png"], distinct], distinct)


func _count_distinct_colors(image: Image) -> int:
    var seen: Dictionary = {}
    var size: Vector2i = image.get_size()
    for y: int in range(0, size.y, SAMPLE_STRIDE):
        for x: int in range(0, size.x, SAMPLE_STRIDE):
            seen[image.get_pixel(x, y).to_rgba32()] = true
    return seen.size()
