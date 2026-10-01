extends GateBase
## Setting the scene up twice leaves one scene, and the second picture is the second scene's.
##
## **Found by a measurement that was too good.** `the_render_target_has_headroom` photographs the
## sun under two weather presets, and the two came back identical — peak, histogram bins, and a
## sampled mean agreeing to six decimal places. Two different skies cannot do that. `setup_for`
## was adding each new world beside the old one instead of replacing it, so the viewport held two
## environments, two suns and two cameras, and the camera that entered first stays current: the
## second setup changed nothing that was rendered.
##
## **What makes this worth a gate of its own is how quietly it lied.** Nothing errored, nothing
## looked wrong, and a gate measuring the second scene got a clean, plausible, repeatable number
## belonging to the first. `vehicle_renders` had been writing a `vehicle_rear` artifact that is
## the front view for as long as it has existed. Any gate that ever measures two setups is
## exposed to it, and the suite's determinism and order-independence checks cannot see it: the
## wrong answer is perfectly stable and perfectly order-independent.
##
## Two things are asserted, because either alone leaves a way to be wrong:
##
## - **One world.** The structural fact. A second world in the tree is the fault itself, whatever
##   it does or does not do to a given frame.
## - **Two different pictures.** The consequence a person would notice. A fix that removed the
##   old world but left the old camera current would pass the first check and fail this one.
##
## The pictures are compared as a sampled mean rather than pixel by pixel: what is being asked is
## whether the renderer is looking at a different scene, and two weathers differing by hundreds
## of units of luminance answer that without any tolerance worth arguing over.

const SHOT: String = "hero_3q"
## Two weathers whose skies and suns are plainly different: noon against dusk.
const FIRST: String = "noon_clear"
const SECOND: String = "golden_dusk"
const CONVERGE: int = 2
const SAMPLE_STEP: int = 16
## How much the sampled mean must move between the two setups. Measured, these two weathers sit
## about 1410 and 916 apart in summed sampled luminance, so this asks for a fraction of the real
## difference and would still catch a second picture that was merely the first one again.
const MIN_DIFFERENCE: float = 0.05


static func meta() -> Dictionary:
    return {
        "name": "a_second_setup_replaces_the_first",
        "proves": "calling setup_for twice leaves one world in the viewport and renders the second scene, not the first",
        "builds_on": ["smoke"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "after two setups there is exactly one world in the viewport, and the two captures'"
            + " sampled means differ by at least %.0f%%" % (MIN_DIFFERENCE * 100.0)
        ),
        "why": (
            "setup_for used to add a world beside the old one rather than replace it, so a second"
            + " setup changed nothing that was rendered and every measurement taken after one"
            + " belonged to the first scene. It errored at nothing and produced stable,"
            + " repeatable, order-independent wrong answers, which is precisely what the rest of"
            + " this suite is built to trust."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "D0",
    }


func run(harness: Node) -> Dictionary:
    var err: String = harness.setup_for(SHOT, FIRST)
    if err != "":
        return fail(err)
    var first: float = await _mean(harness, "setup/first")

    err = harness.setup_for(SHOT, SECOND)
    if err != "":
        return fail(err)
    var second: float = await _mean(harness, "setup/second")

    var worlds: int = _count_worlds(harness)
    if worlds != 1:
        return fail(
            "after two setups the viewport holds %d worlds: each one has its own environment, sun"
            % worlds + " and camera, and the camera that entered first stays current — so the"
            + " second setup changes nothing that is rendered and everything measured afterwards"
            + " belongs to the first scene",
            worlds
        )
    if first <= 0.0:
        return fail("the first capture came back black, so there is nothing to compare against")
    var moved: float = absf(second - first) / first
    if moved < MIN_DIFFERENCE:
        return fail(
            "two setups, two different weathers, and the picture barely moved: sampled means"
            + " %.4f and %.4f, %.3f%% apart. The second scene is not what is being rendered."
            % [first, second, moved * 100.0],
            moved
        )
    return ok(
        "one world after two setups, and %s against %s moves the sampled mean %.4f to %.4f"
        % [FIRST, SECOND, first, second],
        moved
    )


## How many worlds are sitting in the host the harness built into.
##
## A world is identified by what it contains — its `WorldEnvironment` — and **not** by its name,
## which was the first attempt and did not work. Godot renames a node whose name is already taken,
## so the leaked second world arrived as `@Node3D@2` and a check looking for `BlockoutWorld` sailed
## straight past it: with the bug deliberately restored, this counted one world and the gate only
## failed on the picture. A structural check that matches on a name the engine is free to rewrite
## is not a structural check.
func _count_worlds(harness: Node) -> int:
    var host: Node = harness.world.get_parent()
    if host == null:
        return 0
    var found: int = 0
    for child: Node in host.get_children():
        if child is Node3D and child.get_node_or_null(^"WorldEnvironment") != null:
            found += 1
    return found


## A sampled mean luminance of the current frame.
func _mean(harness: Node, tag: String) -> float:
    await harness.advance_frames(CONVERGE, "static", tag)
    var texture: ViewportTexture = harness.render_viewport().get_texture()
    var image: Image = texture.get_image() if texture != null else null
    if image == null or image.is_empty():
        return 0.0
    var size: Vector2i = image.get_size()
    var total: float = 0.0
    var counted: int = 0
    for y: int in range(0, size.y, SAMPLE_STEP):
        for x: int in range(0, size.x, SAMPLE_STEP):
            total += image.get_pixel(x, y).get_luminance()
            counted += 1
    return total / float(maxi(counted, 1))
