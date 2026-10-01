extends GateBase
## The brightest thing in frame is brighter than white. Nothing is clamped on the way out.
##
## **PLAN M2 acceptance 4.** A render target that clips has thrown the highlights away before any
## tonemapper gets to see them, and no tonemap curve, no exposure and no grade recovers them
## afterwards — a sky that clipped is flat white for the rest of the pipeline. The whole reason
## this project moved to a float capture path was that an 8-bit one destroyed every sun-to-sky
## figure it recorded, so the buffer having real headroom is load-bearing rather than tidy.
##
## **How a clamp is told from a bright picture.** Both have pixels at 1.0, so counting them says
## nothing. A clamp has two signatures a bright picture does not:
##
## - **A ceiling.** Nothing anywhere exceeds 1.0. A display-referred buffer cannot hold more than
##   white by construction, so a single sample above it is proof the buffer is not one — and the
##   test is "strictly above", not "above by some margin". Demanding a margin was the first
##   version and it was wrong: it asked the scene to be bright rather than the buffer to be deep.
##   Measured, noon peaks at 2.4 and golden dusk at 1.205 with the same camera, because dusk is
##   dimmer at a fixed exposure and not because the buffer changed. A gate that failed dusk for
##   that would be grading the weather.
## - **A plateau.** Clamping maps a whole range of different values onto one, so pixels pile up at
##   exactly 1.0 in a way a continuous scene never produces.
##
## Both are checked, because either alone is arguable and together they are not.
##
## **The plateau is measured as a histogram shape, not as a share, and that was a correction.**
## Counting the pixels sitting within a hair of white and calling a large number a clamp does not
## work: a big smooth sky crosses 1.0 somewhere, and the band of pixels near the crossing is as
## wide as the gradient is shallow. Measured, 0.356% of samples landed within 0.002 of white in a
## frame that is not clamped at all. So the bin at white is compared against the bin immediately
## below it, which is the thing that actually distinguishes the two: a clamp empties the
## neighbour and piles everything into white, while a gradient fills both about equally.
##
## **The camera is aimed at the sun, and that correction came from a measurement.** A first run
## framed the hero truck and peaked at 1.376 — above white, but under the margin this gate asks
## for, and the honest reading of that is not that the buffer is short of range. It is that the
## shot had no sun in it: the brightest thing in a three-quarter view of a truck is the sky, and a
## scene that contains no highlight cannot demonstrate headroom. So the camera is turned to face
## the sun the weather preset places, which is the condition the acceptance calls sun-backlit, and
## the threshold is left where it was rather than lowered to fit the first picture that missed.
##
## The tonemapper is set to linear for the measurement. The shipped curve compresses highlights
## towards white by design, so measuring through it would ask "does the curve roll off", which is
## a different question with the opposite right answer. Everything else is the weather preset's
## own: this asks what the renderer actually produces, not what a darkroom produces.
##
## Only the weather presets that exist are measured. The acceptance names night and sun-backlit
## presets and neither has been built yet — `noon_clear` and `golden_dusk` are what this project
## ships, and a gate that invented two more would be grading its own homework.

const SHOT: String = "hero_3q"
const WEATHERS: Array[String] = ["noon_clear", "golden_dusk"]
const CONVERGE: int = 3
## Pixels are sampled on a grid: a clipped sky is tens of thousands of pixels, not one.
const SAMPLE_STEP: int = 3
## What counts as white. The render target is scene-referred and linear, so 1.0 is the value a
## display-referred buffer would have had to stop at.
const WHITE: float = 1.0
## The width of the histogram bin at white, and of the comparison bin just below it.
const PLATEAU_EPSILON: float = 0.002
## How many times fuller the bin at white may be than the bin just below it. A smooth gradient
## puts roughly the same count in both; a clamp empties the lower bin into the upper one, so the
## ratio runs to hundreds or to infinity. Ten is well clear of either.
const MAX_PLATEAU_RATIO: float = 10.0


static func meta() -> Dictionary:
    return {
        "name": "the_render_target_has_headroom",
        "proves": "the render target carries highlights above white instead of clamping them, in every weather this project ships",
        "builds_on": ["captures_carry_real_light"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "in each of %d weathers the brightest sampled pixel exceeds white, and the histogram"
            % WEATHERS.size()
            + " bin at white is at most %.0fx the bin below it" % MAX_PLATEAU_RATIO
        ),
        "why": (
            "a clipped highlight is gone before any tonemapper sees it, and no curve or exposure"
            + " recovers it. This project already lost every sun-to-sky figure it recorded to an"
            + " 8-bit capture path, which is the same fault one stage later. Counting bright"
            + " pixels cannot tell a clamp from a bright picture; a ceiling and a plateau can."
        ),
        "budget_s": 180.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var reported: PackedStringArray = PackedStringArray()
    var worst_peak: float = INF
    for weather: String in WEATHERS:
        var err: String = harness.setup_for(SHOT, weather)
        if err != "":
            return fail(err)
        var environment: Environment = _environment(harness)
        if environment == null:
            return fail("the world has no environment, so there is no tonemapper to set")
        # Linear, so what is measured is what the renderer produced rather than what the shipped
        # curve made of it. Nothing else about the preset is touched.
        environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
        environment.tonemap_exposure = 1.0

        _aim_at_sun(harness, weather)
        await harness.advance_frames(1, "static", "headroom")

        var shot: Dictionary = await harness.capture_hdr(
            "headroom/%s" % weather, "static", CONVERGE
        )
        if (shot["error"] as String) != "":
            return fail(shot["error"] as String)
        var image: Image = shot["image"] as Image
        if image == null:
            return fail("the %s capture came back with no image" % weather)

        var measured: Dictionary = _scan(image)
        var peak: float = measured["peak"] as float
        var at_white: int = measured["at_white"] as int
        var below: int = measured["below"] as int
        var ratio: float = float(at_white) / maxf(float(below), 1.0)
        worst_peak = minf(worst_peak, peak)
        if peak <= WHITE:
            return fail(
                "under %s nothing in the frame exceeds white: the brightest sampled channel is"
                % weather + " %.4f, so the render target stopped where a display-referred buffer"
                % peak + " would have. Every highlight above that is already gone and no"
                + " tonemapper downstream can bring it back.",
                peak
            )
        if ratio > MAX_PLATEAU_RATIO:
            return fail(
                "under %s the histogram bin at white holds %d samples against %d in the bin just"
                % [weather, at_white, below] + " below it, %.0fx fuller. That is a plateau rather"
                % ratio + " than a distribution: a range of different values has been mapped onto"
                + " one, which is what clamping looks like in a histogram.",
                ratio
            )
        reported.append(
            "%s peaks at %.1f, white bin %d against %d below" % [weather, peak, at_white, below]
        )
    return ok(
        "the render target carries highlights: %s" % ", ".join(reported), worst_peak
    )


## Turns the camera to face the sun the weather preset placed, keeping where it stands.
##
## The sun's own direction rather than a hand-written angle: a preset that moves its sun would
## otherwise leave this gate quietly photographing empty sky and still passing.
func _aim_at_sun(harness: Node, weather: String) -> void:
    var preset: Dictionary = WeatherCfg.get_preset(weather)
    var toward: Vector3 = (preset.get("sun_from", Vector3.UP) as Vector3).normalized()
    var from: Vector3 = harness.camera.global_position
    harness.camera.look_at_from_position(from, from + toward, Vector3.UP)


func _environment(harness: Node) -> Environment:
    var holder: WorldEnvironment = (
        harness.world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    )
    return holder.environment if holder != null else null


## The brightest channel anywhere, and two adjacent histogram bins: the one straddling white and
## the one immediately below it. Their ratio is what tells a clamp from a gradient.
func _scan(image: Image) -> Dictionary:
    var size: Vector2i = image.get_size()
    var peak: float = 0.0
    var at_white: int = 0
    var below: int = 0
    for y: int in range(0, size.y, SAMPLE_STEP):
        for x: int in range(0, size.x, SAMPLE_STEP):
            var colour: Color = image.get_pixel(x, y)
            for channel: float in [colour.r, colour.g, colour.b]:
                peak = maxf(peak, channel)
                if absf(channel - WHITE) <= PLATEAU_EPSILON:
                    at_white += 1
                elif channel < WHITE - PLATEAU_EPSILON and channel >= WHITE - 3.0 * PLATEAU_EPSILON:
                    below += 1
    return {"peak": peak, "at_white": at_white, "below": below}
