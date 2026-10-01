extends GateBase
## The distance holds still while the foreground moves. A truck falling cannot change the colour
## of ground forty metres behind it.
##
## **Why this gate exists.** The user reported the background grid flickering white during the
## hero truck's drop. Every gate in the suite was green at the time, and all 85 of them stayed
## green while it happened, because each one measures a number out of one frame and a flicker
## lives between frames. The suite had no way to notice a renderer that could not draw the same
## scene twice.
##
## What it turned out to be: `Sky.process_mode` left at its default, which approximates the
## radiance map across frames. A rough ground takes its specular from that map, so an unconverged
## map landed on the distance first and hardest — measured, a band of far ground alternated
## between 0.6703 and 0.9906 luminance on alternate frames, long after the truck had come to rest
## and with the camera bolted down. Two discrete values, flipping: not noise, a toggle.
##
## **The oracle is an invariant and the strongest kind there is.** It states nothing about what
## the renderer should draw, only that a scene which is not changing must not change — so it
## cannot be satisfied by agreeing with a number this project wrote, and it needs no reference
## image, no threshold anybody picked, and no updating when the art changes. Determinism also
## underwrites every golden-image gate in the suite: a renderer that draws two different pictures
## of one scene makes every comparison against a stored frame a coin toss.
##
## **It took two miswired controls to arrive at this scene, and both are worth recording.** The
## first version measured a genuinely still scene and passed with the bug still in the code — a
## static scene settles its radiance map once and never shows the fault. The second added a small
## box moving in the foreground; it "failed", but the only pixels that moved were the box's own,
## so the control proved nothing except that a moving box moves. Neither gate was worth anything
## and both looked completely reasonable. The project's rule — a control that produces no change
## is miswired until proven otherwise — is what caught them, twice in a row.
##
## What reproduces it is the hero truck: a real vehicle whose pose is rewritten every frame. So
## this gate runs the same drop `vehicle_drops_live` runs, and measures a window of **distant
## ground the truck never occupies and never shadows**. That keeps the oracle an invariant rather
## than a golden image: a truck landing in the middle distance has no physical business changing
## the colour of ground forty metres behind it, whatever the renderer is doing internally.
##
## It skips when the hero asset is absent, as every gate that needs it does.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const PRESET: String = "hero_3q"
const SUBSTEP_HZ: float = 2000.0
const DROP_HEIGHT_M: float = 0.8
## Frames to let the renderer settle before the drop. Shader compilation and the first shadow
## pass happen here, and neither is the fault being looked for.
const SETTLE_FRAMES: int = 4
## Frames compared against each other afterwards. Enough to catch a toggle with a period longer
## than two, which is what an incrementally updated resource usually produces.
const FRAMES: int = 10
## Pixels are sampled on a grid rather than read individually: a flicker that covers a quarter of
## the frame does not need every pixel to find, and `get_pixel` in a script is slow enough that
## reading two million of them ten times over would dominate the gate's budget.
const SAMPLE_STEP: int = 4
## The window measured: distant ground on the far side of the frame from the moving box, chosen
## off the reported failure. In the frames the user saw, this is the band that alternated between
## 0.6703 and 0.9906 luminance — the checker washing to white and back.
const BAND_FROM: Vector2i = Vector2i(100, 280)
const BAND_TO: Vector2i = Vector2i(400, 340)
## Frames of falling before the measurement starts. The truck is down and still by here, so
## anything the band does afterwards is not the truck arriving.
const DROP_FRAMES: int = 40
## How much the sampled mean may move between two frames of a still scene.
##
## Not zero, because a float capture quantises and the comparison is over a subsample; but close
## enough to zero that the fault this was written for — a mean moving by 0.32 — is three orders
## of magnitude clear of it.
const MEAN_TOLERANCE: float = 0.0005
## How far any single sampled pixel may move. A flicker confined to a small part of the frame
## would otherwise be averaged away by the rest of it, which is exactly how this one hid: the
## whole-frame mean moves much less than the band that is actually flickering.
const PIXEL_TOLERANCE: float = 0.02


static func meta() -> Dictionary:
    return {
        "name": "the_distance_does_not_flicker",
        "proves": "distant ground holds exactly still while something moves in the foreground, so no golden image and no single-frame measurement is a coin toss",
        "builds_on": ["vehicle_drops_live"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "over %d frames of a landed truck still being posed, the distant band's mean moves"
            % FRAMES + " less than %.4f and no pixel in it moves more than %.2f"
            % [MEAN_TOLERANCE, PIXEL_TOLERANCE]
        ),
        "why": (
            "the user saw the background grid flicker white and all 85 gates were green through"
            + " it, because every one of them measures a number out of a single frame and a"
            + " flicker lives between frames. It was the sky's radiance map being approximated"
            + " across frames, landing on the rough ground's specular; the far field alternated"
            + " between 0.6703 and 0.9906 luminance with the camera bolted down. Determinism is"
            + " also what every golden-image gate in this suite quietly assumes."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)

    var built: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    var truck: TruckParser = built["truck"] as TruckParser
    harness.world.add_child(built["root"] as Node3D)
    var rig: Dictionary = RigBuilder.build(truck, DROP_HEIGHT_M)
    if (rig["error"] as String) != "":
        return fail(rig["error"] as String)
    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_ground(0.0, true)
    var substeps: int = int(SUBSTEP_HZ / 60.0)

    await harness.advance_frames(SETTLE_FRAMES, "static", "settle")
    for _frame: int in DROP_FRAMES:
        solver.step(1.0 / SUBSTEP_HZ, substeps)
        VehicleBuilder.apply_pose(built, truck, solver.get_positions())
        await harness.advance_frames(1, "static", "drop")

    var previous: PackedFloat32Array = PackedFloat32Array()
    var size: Vector2i = Vector2i.ZERO
    var worst_mean: float = 0.0
    var worst_mean_frame: int = 0
    var worst_pixel: float = 0.0
    var worst_pixel_at: Vector2i = Vector2i.ZERO
    var worst_pixel_frame: int = 0
    # The truck is down by now, but its pose is still rewritten every frame — which is what keeps
    # the renderer redoing the work that was landing on the distance.
    for frame: int in FRAMES:
        solver.step(1.0 / SUBSTEP_HZ, substeps)
        VehicleBuilder.apply_pose(built, truck, solver.get_positions())
        await harness.advance_frames(1, "static", "still")
        var texture: ViewportTexture = harness.render_viewport().get_texture()
        var image: Image = texture.get_image() if texture != null else null
        if image == null or image.is_empty():
            return fail("frame %d captured nothing; is the window rendering?" % frame)
        size = image.get_size()
        var current: PackedFloat32Array = _sample(image)
        if previous.is_empty():
            previous = current
            continue
        if current.size() != previous.size():
            return fail("the viewport resized mid-gate, so there is nothing to compare")
        var total: float = 0.0
        for index: int in current.size():
            var moved: float = absf(current[index] - previous[index])
            total += moved
            if moved > worst_pixel:
                worst_pixel = moved
                worst_pixel_frame = frame
                worst_pixel_at = _where(index, size)
        var mean: float = total / float(current.size())
        if mean > worst_mean:
            worst_mean = mean
            worst_mean_frame = frame
        previous = current

    if worst_pixel > PIXEL_TOLERANCE:
        return fail(
            "the truck is down and the distance changed anyway: the pixel at %d, %d"
            % [worst_pixel_at.x, worst_pixel_at.y]
            + " moved %.4f between frames %d and %d, and the frame's mean moved %.5f."
            % [worst_pixel, worst_pixel_frame - 1, worst_pixel_frame, worst_mean]
            + " A renderer that draws two different pictures of one still scene makes every"
            + " golden image in this suite a coin toss.",
            worst_pixel
        )
    if worst_mean > MEAN_TOLERANCE:
        return fail(
            "the whole frame drifts between renders of a still scene: the sampled mean moved"
            + " %.5f at frame %d, with no single pixel moving more than %.4f — so this is a"
            % [worst_mean, worst_mean_frame, worst_pixel]
            + " shift across the image rather than a flicker in one place.",
            worst_mean
        )
    return ok(
        "%d frames of a landed truck still being posed, %dx%d: the distant band's mean"
        % [FRAMES, size.x, size.y]
        + " moves at most %.6f and its worst pixel %.5f, so the distance holds still"
        % [worst_mean, worst_pixel],
        worst_pixel
    )


## The measured band as a flat list of sampled luminances.
func _sample(image: Image) -> PackedFloat32Array:
    var out: PackedFloat32Array = PackedFloat32Array()
    var size: Vector2i = image.get_size()
    for y: int in range(BAND_FROM.y, mini(BAND_TO.y, size.y), SAMPLE_STEP):
        for x: int in range(BAND_FROM.x, mini(BAND_TO.x, size.x), SAMPLE_STEP):
            out.append(image.get_pixel(x, y).get_luminance())
    return out


## Where a sample sits in the frame, so a failure names a place a person can go and look.
func _where(index: int, _size: Vector2i) -> Vector2i:
    var across: int = int(ceil(float(BAND_TO.x - BAND_FROM.x) / float(SAMPLE_STEP)))
    return Vector2i(
        BAND_FROM.x + (index % across) * SAMPLE_STEP,
        BAND_FROM.y + (index / across) * SAMPLE_STEP
    )
