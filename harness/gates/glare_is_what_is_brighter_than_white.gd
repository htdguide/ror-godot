extends GateBase
## A lens scatters what is brighter than white, in proportion, and leaves everything else alone.
##
## **Bloom is the easiest effect in a renderer to get wrong in a way nobody can name.** Set its
## threshold too low and every pale surface grows a halo, the picture goes soft, and the usual
## verdict is "it looks a bit washed out" rather than "the glare threshold is under white". So the
## three things worth holding are the three a threshold means:
##
##   nothing under it glares     a mid-grey patch is the same with the glare on and off
##   what is over it does        a highlight above white puts light into the dark around it
##   and more of it glares less  raising the threshold takes energy away, never adds it
##
## None of that is a number from outside this project — a lens's veiling glare is a per cent or two
## of the light and this chooses how much of it to draw — so the oracle is the definition of a
## threshold rather than a measurement of a real lens. What it catches is the whole family of ways
## a bloom is wired wrongly: applied before the tonemapper, keyed off the wrong channel, or
## thresholded in display space where everything is under one.
##
## The frame is read as light rather than as display pixels, because glare is added in HDR and a
## halo an 8-bit frame rounds away is still energy in the picture.

const PRESET: String = "diag_topdown"
const WEATHER: String = "spike_black"
const CONVERGE: int = 4
## The two patches: one far above white, one safely under it. Both are unshaded, so what they emit
## is what this gate chose and not what some light did.
const BRIGHT: float = 8.0
const DIM: float = 0.93
const PATCH_M: float = 0.7
const BRIGHT_AT: Vector3 = Vector3(-1.4, 1.0, 0.0)
const DIM_AT: Vector3 = Vector3(1.4, 1.0, 0.0)
## Where the halo is read: beside the bright patch, far enough out to be background rather than
## patch, in metres.
const HALO_OFFSET_M: float = 0.75
## How much the dark beside a highlight has to gain for the glare to be doing anything at all.
const MIN_HALO: float = 0.002
## How much of a halo a sub-threshold patch may put beside it, as a share of the one the highlight
## puts. **Read beside the patch and not on it**, because a patch wide compared with the blur barely
## brightens its own middle — dropping the threshold far below it moved its centre by 0.73%, which
## no sane bound would catch. And the patch is just *under* white rather than dark, because a dark
## one puts no halo beside it at any threshold at all, so a check using one would pass whatever the
## renderer did.
## Near enough to nothing: with the threshold where it belongs this reads 0.0000, and with it
## dropped to 0.4 — under the patch — it reads 0.71% of the highlight's own halo. The bound is the
## gap between those, not a fraction anybody likes the look of.
const MAY_LEAK: float = 0.005
## The raised threshold the monotonic check uses, against `RenderCfg.GLOW_HDR_THRESHOLD`.
const RAISED_THRESHOLD: float = 7.2


static func meta() -> Dictionary:
    return {
        "name": "glare_is_what_is_brighter_than_white",
        "proves": "the lens's glare puts light around a highlight brighter than white, leaves a surface under the threshold untouched, and weakens when the threshold is raised",
        "builds_on": ["tonemap_and_exposure"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "a halo over %.3f in light, a sub-threshold patch putting under %.0f%% of that beside"
            % [MIN_HALO, MAY_LEAK * 100.0] + " itself, and less glare at a higher threshold"
        ),
        "why": (
            "a bloom whose threshold sits under white hazes every pale surface in the game and"
            + " reads as a soft picture rather than as a bug, which is how it survives. The three"
            + " properties here are what a threshold is for, and each of them fails loudly for a"
            + " different wiring mistake."
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
        return fail("the world has no environment to glare in")
    var environment: Environment = holder.environment
    environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    environment.tonemap_exposure = 1.0
    var ground: Node3D = harness.world.get_node_or_null(^"Ground") as Node3D
    if ground != null:
        ground.visible = false
    harness.world.add_child(_patch(BRIGHT_AT, BRIGHT))
    harness.world.add_child(_patch(DIM_AT, DIM))

    var beside: Vector3 = BRIGHT_AT + Vector3(HALO_OFFSET_M, 0.0, 0.0)
    var readings: Dictionary = {}
    for named: Array in [
        ["off", false, RenderCfg.GLOW_HDR_THRESHOLD],
        ["on", true, RenderCfg.GLOW_HDR_THRESHOLD],
        ["raised", true, RAISED_THRESHOLD],
    ]:
        environment.glow_enabled = bool(named[1])
        environment.glow_hdr_threshold = float(named[2])
        var shot: Dictionary = await harness.capture_hdr(
            "glare/%s" % (named[0] as String), "static", CONVERGE
        )
        if (shot["error"] as String) != "":
            return fail(shot["error"] as String)
        var image: Image = shot["image"] as Image
        if image == null:
            return fail("the capture at %s could not be read" % shot["exr"])
        readings[named[0]] = {
            "halo": _at(harness, image, beside),
            "dim": _at(harness, image, DIM_AT + Vector3(HALO_OFFSET_M, 0.0, 0.0)),
        }

    var halo_off: float = (readings["off"] as Dictionary)["halo"] as float
    var halo_on: float = (readings["on"] as Dictionary)["halo"] as float
    var halo_raised: float = (readings["raised"] as Dictionary)["halo"] as float
    var dim_off: float = (readings["off"] as Dictionary)["dim"] as float
    var dim_on: float = (readings["on"] as Dictionary)["dim"] as float
    var said: String = (
        "beside the highlight %.4f off, %.4f on, %.4f at a threshold of %.1f; beside the %.2f"
        % [halo_off, halo_on, halo_raised, RAISED_THRESHOLD, DIM]
        + " patch %.4f off and %.4f on" % [dim_off, dim_on]
    )

    var halo: float = halo_on - halo_off
    if halo < MIN_HALO:
        return fail(
            "a highlight %.1f times white puts %.4f of light into the dark beside it, under the"
            % [BRIGHT, halo] + " %.3f this gate asks for (%s): the glare is not reaching the"
            % [MIN_HALO, said] + " picture",
            halo
        )
    var leak: float = absf(dim_on - dim_off) / maxf(halo, 0.000001)
    if leak > MAY_LEAK:
        return fail(
            "a surface at %.2f, under a threshold of %.1f, put a halo of %.4f beside it — %.0f%%"
            % [DIM, RenderCfg.GLOW_HDR_THRESHOLD, absf(dim_on - dim_off), leak * 100.0]
            + " of the highlight's own, over the %.0f%% allowed (%s): the threshold is not where"
            % [MAY_LEAK * 100.0, said] + " it says it is",
            leak
        )
    if halo_raised >= halo_on:
        return fail(
            "raising the threshold from %.1f to %.1f did not weaken the glare: %.4f against %.4f"
            % [RenderCfg.GLOW_HDR_THRESHOLD, RAISED_THRESHOLD, halo_raised, halo_on]
            + " (%s). A threshold that changes nothing is not one" % said,
            halo_raised - halo_on
        )
    return ok(
        "%s. The halo is %.4f of light, the sub-threshold surface moved %.2f%%, and a threshold of"
        % [said, halo, leak * 100.0]
        + " %.1f leaves %.0f%% of it" % [RAISED_THRESHOLD, 100.0 * (halo_raised - halo_off) / halo],
        halo
    )


## One flat patch emitting a stated value, facing the camera overhead.
func _patch(at: Vector3, value: float) -> MeshInstance3D:
    var patch: MeshInstance3D = MeshInstance3D.new()
    var plane: PlaneMesh = PlaneMesh.new()
    plane.size = Vector2(PATCH_M, PATCH_M)
    patch.mesh = plane
    var flat: StandardMaterial3D = StandardMaterial3D.new()
    flat.albedo_color = Color(value, value, value)
    flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    patch.material_override = flat
    patch.position = at
    return patch


func _at(harness: Node, image: Image, at: Vector3) -> float:
    var where: Vector2 = harness.camera.unproject_position(at)
    var size: Vector2i = image.get_size()
    var viewport: Vector2 = harness.render_viewport().get_visible_rect().size
    var x: int = clampi(int(where.x / viewport.x * float(size.x)), 0, size.x - 1)
    var y: int = clampi(int(where.y / viewport.y * float(size.y)), 0, size.y - 1)
    var total: float = 0.0
    var counted: int = 0
    for dy: int in range(-6, 7, 2):
        for dx: int in range(-6, 7, 2):
            total += image.get_pixel(
                clampi(x + dx, 0, size.x - 1), clampi(y + dy, 0, size.y - 1)
            ).get_luminance()
            counted += 1
    return total / maxf(float(counted), 1.0)
