class_name FlexPoses
extends RefCounted
## Deformation poses for the FlexBody equivalence spike.
##
## Analytic rather than simulated: the spike is testing an algebraic identity, so the
## poses are chosen to break it if it can be broken. They deliberately exceed anything a
## vehicle reaches, including shear and non-uniform scale, because those are what a
## rotation-and-scale pose representation silently discards.

const POSES: Array[String] = ["rest", "twist", "bend", "shear", "squash", "extreme"]


static func apply(pose: String, rest: PackedVector3Array) -> PackedVector3Array:
    var out: PackedVector3Array = PackedVector3Array()
    out.resize(rest.size())
    for i: int in rest.size():
        out[i] = _displace(pose, rest[i])
    return out


static func _displace(pose: String, p: Vector3) -> Vector3:
    match pose:
        "rest":
            return p
        "twist":
            var angle: float = p.z * 0.9
            return Vector3(
                p.x * cos(angle) - p.y * sin(angle), p.x * sin(angle) + p.y * cos(angle), p.z
            )
        "bend":
            return Vector3(p.x, p.y + p.z * p.z * 0.35, p.z)
        "shear":
            return Vector3(p.x + p.y * 0.6, p.y, p.z + p.y * 0.25)
        "squash":
            return Vector3(p.x * 1.6, p.y * 0.45, p.z * 1.15)
        "extreme":
            var twisted: Vector3 = _displace("twist", p)
            var sheared: Vector3 = _displace("shear", twisted)
            return Vector3(sheared.x * 1.4, sheared.y * 0.6 + sin(p.x * 2.0) * 0.3, sheared.z)
        _:
            return p
