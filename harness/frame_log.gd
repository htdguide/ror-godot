class_name FrameLog
extends RefCounted
## `--frame-log`: one line every `FRAMES` frames with the median and worst frame, the 3D resolution
## drawn and the solver's share. A session on a machine nobody here can watch — a Windows PC
## reporting "fullscreen is slow" — can paste the lines instead of describing them.

## How many frames go into each printed line.
const FRAMES: int = 300

## Frame times since the last line, in milliseconds.
var _frame_ms: PackedFloat32Array = PackedFloat32Array()
var _clock: int = 0


func tick(viewport: Viewport, split: bool, drive: PlayDrive) -> void:
    # The wall clock, not `delta`: Godot smooths `delta` towards whole display intervals, and a log
    # read off it showed a split window at a steady 10.0 ms with VSync off.
    var now: int = Time.get_ticks_usec()
    if _clock > 0:
        _frame_ms.append(float(now - _clock) / 1000.0)
    _clock = now
    if _frame_ms.size() < FRAMES:
        return
    _frame_ms.sort()
    var rows: float = viewport.get_visible_rect().size.y * viewport.scaling_3d_scale
    print("PLAY  frames: median %.1f ms, worst %.1f ms over %d; 3D drawn at %d rows%s; solver %.2f ms" % [
        _frame_ms[_frame_ms.size() / 2], _frame_ms[_frame_ms.size() - 1], _frame_ms.size(),
        int(rows), " x2 (split)" if split else "",
        float(drive.solver_usec) / 1000.0 if drive != null else 0.0])
    _frame_ms.clear()
