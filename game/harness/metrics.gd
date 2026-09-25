class_name HarnessMetrics
extends RefCounted
## Per-frame performance sampling, printed as one machine-parsable line per frame.
##
## The line prefix is an interface, not a convenience: tooling greps for it, so it
## does not change. Timings come from the wall clock rather than from frame delta,
## because --fixed-fps makes delta a constant and therefore useless for measurement.

const LINE_PREFIX: String = "HARNESS_METRIC "
const SUMMARY_PREFIX: String = "HARNESS_SUMMARY "
const USEC_PER_MSEC: float = 1000.0
## Frames excluded from the percentile summary and reported on their own. The first
## rendered frames pay for world construction and shader compilation.
const WARMUP_FRAMES: int = 2

var _frame_ms: PackedFloat64Array = PackedFloat64Array()
var _last_usec: int = 0
var _viewport_rid: RID


func begin(viewport: Viewport) -> void:
    _viewport_rid = viewport.get_viewport_rid()
    _last_usec = Time.get_ticks_usec()


## Samples one frame and prints it. Returns the sample so a gate can assert on it.
func sample(frame: int, tag: String) -> Dictionary:
    var now: int = Time.get_ticks_usec()
    var frame_ms: float = float(now - _last_usec) / USEC_PER_MSEC
    _last_usec = now
    _frame_ms.append(frame_ms)

    var row: Dictionary = {
        "frame": frame,
        "tag": tag,
        "frame_ms": snappedf(frame_ms, 0.01),
        "draw_calls": _render_info(RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
        "primitives": _render_info(RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
        "objects": _render_info(RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
        "video_mem_mb": _mem_mb(Performance.RENDER_VIDEO_MEM_USED),
        "texture_mem_mb": _mem_mb(Performance.RENDER_TEXTURE_MEM_USED),
    }
    print(LINE_PREFIX + JSON.stringify(row))
    return row


## Prints the run summary. Reports percentiles, never the mean: the mean hides the
## hitches that are the whole reason to measure.
func summarize(extra: Dictionary) -> Dictionary:
    var sorted: Array[float] = []
    var warmup_ms: float = 0.0
    for i: int in _frame_ms.size():
        if i < WARMUP_FRAMES:
            warmup_ms = maxf(warmup_ms, _frame_ms[i])
            continue
        sorted.append(_frame_ms[i])
    sorted.sort()
    var row: Dictionary = {
        "frames": _frame_ms.size(),
        "warmup_frames": WARMUP_FRAMES,
        "warmup_ms_max": snappedf(warmup_ms, 0.01),
        "steady_frames": sorted.size(),
        "frame_ms_p50": snappedf(_percentile(sorted, 0.50), 0.01),
        "frame_ms_p99": snappedf(_percentile(sorted, 0.99), 0.01),
        "frame_ms_max": snappedf(_percentile(sorted, 1.0), 0.01),
    }
    row.merge(extra, true)
    print(SUMMARY_PREFIX + JSON.stringify(row))
    return row


func _percentile(sorted: Array[float], q: float) -> float:
    if sorted.is_empty():
        return 0.0
    var index: int = int(round(q * float(sorted.size() - 1)))
    return sorted[clampi(index, 0, sorted.size() - 1)]


func _render_info(info: RenderingServer.ViewportRenderInfo) -> int:
    if not _viewport_rid.is_valid():
        return -1
    return RenderingServer.viewport_get_render_info(
        _viewport_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, info
    )


func _mem_mb(monitor: Performance.Monitor) -> float:
    return snappedf(Performance.get_monitor(monitor) / 1048576.0, 0.01)
