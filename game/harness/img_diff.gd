class_name ImgDiff
extends RefCounted
## Perceptual image comparison shared by gates and by the command-line differ.
##
## Compares luma after a small downsample-blur. The blur absorbs the sub-pixel
## non-determinism a GPU driver is allowed to have; without it every capture would
## differ from every other by a handful of least-significant bits and the gate would be
## reporting noise rather than regressions.

const BLUR_RADIUS: int = 1
const DEFAULT_TOLERANCE: float = 0.002
const LUMA: Vector3 = Vector3(0.2126, 0.7152, 0.0722)
const REGION_GRID: int = 8


static func compare(path_a: String, path_b: String, tolerance: float) -> Dictionary:
    var a: Image = Image.load_from_file(path_a)
    var b: Image = Image.load_from_file(path_b)
    if a == null or b == null:
        return {"pass": false, "error": "cannot load '%s' or '%s'" % [path_a, path_b]}
    if a.get_size() != b.get_size():
        return {
            "pass": false,
            "error": "size mismatch %s vs %s" % [a.get_size(), b.get_size()],
        }
    a.resize(a.get_width() / (BLUR_RADIUS + 1), a.get_height() / (BLUR_RADIUS + 1), Image.INTERPOLATE_BILINEAR)
    b.resize(b.get_width() / (BLUR_RADIUS + 1), b.get_height() / (BLUR_RADIUS + 1), Image.INTERPOLATE_BILINEAR)

    var size: Vector2i = a.get_size()
    var total: float = 0.0
    var worst: float = 0.0
    var worst_at: Vector2i = Vector2i.ZERO
    var region_error: Dictionary = {}
    for y: int in size.y:
        for x: int in size.x:
            var delta: float = absf(_luma(a.get_pixel(x, y)) - _luma(b.get_pixel(x, y)))
            total += delta
            if delta > worst:
                worst = delta
                worst_at = Vector2i(x, y)
            var key: String = "%d,%d" % [
                x * REGION_GRID / size.x, y * REGION_GRID / size.y
            ]
            region_error[key] = float(region_error.get(key, 0.0)) + delta
    var mean: float = total / float(size.x * size.y)
    return {
        "pass": mean <= tolerance,
        "mean_luma_error": snappedf(mean, 0.000001),
        "max_luma_error": snappedf(worst, 0.000001),
        "worst_pixel": "%d,%d" % [worst_at.x * (BLUR_RADIUS + 1), worst_at.y * (BLUR_RADIUS + 1)],
        "worst_region": _worst_region(region_error),
        "tolerance": tolerance,
        "a": path_a,
        "b": path_b,
    }


static func _luma(color: Color) -> float:
    return color.r * LUMA.x + color.g * LUMA.y + color.b * LUMA.z


## Names the worst eighth-of-frame cell, so a failure says where to look instead of
## only how bad it is.
static func _worst_region(region_error: Dictionary) -> String:
    var worst_key: String = ""
    var worst_value: float = -1.0
    for key: String in region_error.keys():
        if float(region_error[key]) > worst_value:
            worst_value = float(region_error[key])
            worst_key = key
    return worst_key
