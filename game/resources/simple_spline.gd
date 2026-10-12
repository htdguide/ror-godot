class_name SimpleSpline
extends RefCounted
## Ogre's `SimpleSpline` as upstream's inertia curves use it, the GDScript twin of `RorSpline` in
## `ror_inertia.cpp`: Hermite segments through the points with Catmull-Rom tangents, `t` spread
## evenly over the segments, and Ogre's rule that a curve whose first and last points coincide is
## closed. Only y is interpolated; that is all upstream reads.

var _y: PackedFloat32Array = PackedFloat32Array()
var _tangent: PackedFloat32Array = PackedFloat32Array()


## A spline through `flat`, upstream's [x0, y0, x1, y1, ...] (`InertiaModels.MODELS`).
static func of(flat: Array) -> SimpleSpline:
    var spline: SimpleSpline = SimpleSpline.new()
    var xs: PackedFloat32Array = PackedFloat32Array()
    for i: int in range(0, flat.size() - 1, 2):
        xs.append(float(flat[i]))
        spline._y.append(float(flat[i + 1]))
    var count: int = spline._y.size()
    spline._tangent.resize(count)
    if count < 2:
        return spline
    var y: PackedFloat32Array = spline._y
    var closed: bool = xs[0] == xs[count - 1] and y[0] == y[count - 1]
    for i: int in count:
        if i == 0:
            spline._tangent[i] = 0.5 * (y[1] - y[count - 2]) if closed else 0.5 * (y[1] - y[0])
        elif i == count - 1:
            spline._tangent[i] = spline._tangent[0] if closed else 0.5 * (y[i] - y[i - 1])
        else:
            spline._tangent[i] = 0.5 * (y[i + 1] - y[i - 1])
    return spline


func interpolate_y(t: float) -> float:
    if _y.is_empty():
        return 0.0
    var segment: float = t * float(_y.size() - 1)
    var index: int = int(segment)
    t = segment - float(index)
    if index + 1 >= _y.size():
        return _y[mini(index, _y.size() - 1)]
    if t == 0.0:
        return _y[index]
    if t == 1.0:
        return _y[index + 1]
    var t2: float = t * t
    var t3: float = t2 * t
    return (2.0 * t3 - 3.0 * t2 + 1.0) * _y[index] + (-2.0 * t3 + 3.0 * t2) * _y[index + 1] \
            + (t3 - 2.0 * t2 + t) * _tangent[index] + (t3 - t2) * _tangent[index + 1]
