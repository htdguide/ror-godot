class_name FrameCapWatch
extends RefCounted
## Watches the engine's `--quit-after` cap for a suite run: says so on the last frame the cap
## allows, and keeps a window that cannot draw from spending the cap.
##
## **A hidden window spent the cap in a third of a second.** Godot's `--quit-after` counts
## main-loop iterations, not drawn frames. While the window is minimised (and, on macOS, while it
## cannot be drawn for any other reason) the engine stops drawing but keeps iterating, as fast as
## the CPU allows: 564,765 iterations in three seconds against 529 frames drawn, vsync on or off.
## A gate waiting for frames waits correctly, but the 60,000-iteration cap is gone in moments and
## the engine quits with code 0 and no word. That was the suite's silent early exit: six runs on
## 2026-10-13, and one on 2026-10-14 that the cap notice below caught at its sixth gate.
##
## So while nothing draws, each iteration sleeps `STALL_SLEEP_MS`: a hidden minute costs a few
## hundred iterations instead of eleven million, the run resumes where it was when the window is
## shown again, and the log says when it stalled and for how long.

## Iterations without a drawn frame before the window counts as unable to draw. A frame that
## loads a map in one iteration is a single iteration; this is many in a row.
const STALL_ITERATIONS: int = 8
const STALL_SLEEP_MS: int = 100

var cap: int = 0
var drawn: int = 0
var stalled_iterations: int = 0
var _last_draw_frame: int = 0
var _stalled_since_ms: int = -1
var _said_cap: bool = false
var _tree: SceneTree = null


func attach(tree: SceneTree, cap_frames: int) -> void:
    _tree = tree
    cap = cap_frames
    _last_draw_frame = Engine.get_process_frames()
    tree.process_frame.connect(_on_process_frame)
    RenderingServer.frame_post_draw.connect(_on_drawn)


func detach() -> void:
    if _tree != null and _tree.process_frame.is_connected(_on_process_frame):
        _tree.process_frame.disconnect(_on_process_frame)
    if RenderingServer.frame_post_draw.is_connected(_on_drawn):
        RenderingServer.frame_post_draw.disconnect(_on_drawn)
    _tree = null


func _on_drawn() -> void:
    drawn += 1
    _last_draw_frame = Engine.get_process_frames()
    if _stalled_since_ms >= 0:
        print("HARNESS_STALL {\"resumed\": true, \"hidden_s\": %.1f, \"iterations\": %d}" % [
            float(Time.get_ticks_msec() - _stalled_since_ms) / 1000.0, stalled_iterations])
        _stalled_since_ms = -1


func _on_process_frame() -> void:
    var frames: int = Engine.get_process_frames()
    if cap > 0 and not _said_cap and frames >= cap - 2:
        _said_cap = true
        print("HARNESS_QUIT {\"code\": 0, \"from\": \"the --quit-after cap of %d frames\"}" % cap)
    if DisplayServer.get_name() == "headless" or frames - _last_draw_frame < STALL_ITERATIONS:
        return
    if _stalled_since_ms < 0:
        _stalled_since_ms = Time.get_ticks_msec()
        stalled_iterations = 0
        print("HARNESS_STALL {\"resumed\": false, \"why\": \"the window is not drawing (minimised or hidden); the run waits for it\"}")
    stalled_iterations += 1
    OS.delay_msec(STALL_SLEEP_MS)
