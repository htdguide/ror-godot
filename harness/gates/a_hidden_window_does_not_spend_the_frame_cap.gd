extends GateBase
## A suite window that cannot draw does not spend the `--quit-after` cap: while it is minimised
## `FrameCapWatch` throttles the main loop to a few iterations a second, and the run resumes
## drawing when the window is shown again.
##
## Godot counts the cap in main-loop iterations. A minimised window draws nothing and iterated
## 180,000 times a second, so the 60,000 the suite allows went in a third of a second and the
## engine quit with code 0 part way through, silently: the suite's unexplained early exits.
##
## The oracle is the engine's own iteration counter against the wall clock, the window minimised
## for 1.5 s, with the watch attached; without it the same second and a half runs to hundreds of
## thousands.

const HIDDEN_S: float = 1.5
## A stall is noticed after `STALL_ITERATIONS`, then one iteration per `STALL_SLEEP_MS`: 23 for
## 1.5 s, and the minimise animation draws a few more frames before the window stops drawing.
const MAX_ITERATIONS: int = 60


static func meta() -> Dictionary:
    return {
        "name": "a_hidden_window_does_not_spend_the_frame_cap",
        "proves": "a minimised suite window iterates a few times a second instead of spending the --quit-after cap, says it stalled, and draws again once shown",
        "builds_on": [],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "at most %d iterations in %.1f s minimised; a stall reported; frames drawn again within 5 s of restoring" % [MAX_ITERATIONS, HIDDEN_S],
        "why": "a minimised window iterated 180,000 times a second and the suite quit silently at its 60,000-iteration cap.",
        "budget_s": 15.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    if DisplayServer.get_name() == "headless":
        return ok("skipped: a headless engine has no window to hide", 0)
    var tree: SceneTree = harness.get_tree()
    var watch: FrameCapWatch = FrameCapWatch.new()
    watch.attach(tree, 0)
    var mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
    var start_frames: int = Engine.get_process_frames()
    var start_ms: int = Time.get_ticks_msec()
    while Time.get_ticks_msec() - start_ms < int(HIDDEN_S * 1000.0):
        await tree.process_frame
    var iterations: int = Engine.get_process_frames() - start_frames
    var stalled: int = watch.stalled_iterations
    DisplayServer.window_set_mode(mode)
    var drawn_before: int = watch.drawn
    var restore_ms: int = Time.get_ticks_msec()
    while watch.drawn < drawn_before + 3 and Time.get_ticks_msec() - restore_ms < 5000:
        await tree.process_frame
    var redrawn: int = watch.drawn - drawn_before
    watch.detach()
    if redrawn < 3:
        return fail("the window drew %d frames in 5 s after it was restored" % redrawn)
    if stalled == 0:
        return fail("minimised for %.1f s, the watch never noticed the window had stopped drawing (%d iterations)" % [HIDDEN_S, iterations])
    if iterations > MAX_ITERATIONS:
        return fail("minimised for %.1f s the engine iterated %d times, more than %d: the cap is being spent" % [HIDDEN_S, iterations, MAX_ITERATIONS])
    return ok("minimised %.1f s: %d iterations (%d throttled), drawing again after restore" % [HIDDEN_S, iterations, stalled], iterations)
