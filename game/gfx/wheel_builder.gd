class_name WheelBuilder
extends RefCounted
## Builds a meshwheels2 wheel: an external rim mesh posed by the axle nodes, and a tyre
## swept procedurally around them.
##
## Follows FlexMeshWheel. The rim sits at the axis midpoint with X along the axle
## (reversed on the right side), Y across the axis toward the first tread ray, Z their
## cross. The tyre is a six-vertex cross-section swept once per ray:
##
##     v0 = axis0 + rim_radius*radial      rim edge, outer
##     v1 = o - 0.05*(o - axis0)
##     v2 = o - 0.10*(o - n)
##     v3 = n - 0.10*(n - o)
##     v4 = n - 0.05*(n - axis1)
##     v5 = axis1 + rim_radius*radial      rim edge, inner
##
## with V texture coordinates 0, 0.23, 0.27, 0.73, 0.77, 1 and U running with the ray.

const CROSS_SECTION_V: Array[float] = [0.0, 0.23, 0.27, 0.73, 0.77, 1.0]
const RIM_INSET: float = 0.05
const TREAD_INSET: float = 0.10


## Rim transform, in rig space.
static func rim_transform(nodes: PackedVector3Array, wheel: Dictionary) -> Transform3D:
    var axis0: Vector3 = nodes[wheel["node1"] as int]
    var axis1: Vector3 = nodes[wheel["node2"] as int]
    var centre: Vector3 = (axis0 + axis1) * 0.5
    var axis: Vector3 = (axis0 - axis1).normalized()
    var x: Vector3 = axis if (wheel["side"] as String) != "r" else -axis
    var y: Vector3 = axis.cross(_reference_ray(axis)).normalized()
    return Transform3D(Basis(x, y, x.cross(y)), centre)


## Tyre mesh, in rim-local space.
static func build_tyre(nodes: PackedVector3Array, wheel: Dictionary) -> ArrayMesh:
    var axis0: Vector3 = nodes[wheel["node1"] as int]
    var axis1: Vector3 = nodes[wheel["node2"] as int]
    var centre: Vector3 = (axis0 + axis1) * 0.5
    var axis: Vector3 = (axis0 - axis1).normalized()
    var rays: int = maxi(wheel["rays"] as int, 3)
    var tire_radius: float = wheel["tire_radius"] as float
    var rim_radius: float = wheel["rim_radius"] as float
    var reference: Vector3 = _reference_ray(axis)
    var inverse: Transform3D = rim_transform(nodes, wheel).affine_inverse()

    var vertices: PackedVector3Array = PackedVector3Array()
    var normals: PackedVector3Array = PackedVector3Array()
    var uvs: PackedVector2Array = PackedVector2Array()
    var indices: PackedInt32Array = PackedInt32Array()

    for i: int in rays + 1:
        var angle: float = TAU * float(i) / float(rays)
        var radial: Vector3 = (reference * cos(angle) + axis.cross(reference) * sin(angle)).normalized()
        var outer: Vector3 = axis0 + radial * tire_radius
        var inner: Vector3 = axis1 + radial * tire_radius
        var section: Array[Vector3] = [
            axis0 + radial * rim_radius,
            outer - (outer - axis0) * RIM_INSET,
            outer - (outer - inner) * TREAD_INSET,
            inner - (inner - outer) * TREAD_INSET,
            inner - (inner - axis1) * RIM_INSET,
            axis1 + radial * rim_radius,
        ]
        var section_normals: Array[Vector3] = [axis, radial, radial, radial, radial, -axis]
        for v: int in section.size():
            vertices.append(inverse * section[v])
            normals.append(inverse.basis * section_normals[v])
            uvs.append(Vector2(float(i) / float(rays), CROSS_SECTION_V[v]))

    for i: int in rays:
        for v: int in CROSS_SECTION_V.size() - 1:
            var a: int = i * CROSS_SECTION_V.size() + v
            var b: int = a + CROSS_SECTION_V.size()
            indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))

    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh: ArrayMesh = ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh


## Any vector across the axis will do at rest: a wheel at spawn has no preferred rotation,
## and the solver supplies real tread nodes once it runs. Upstream uses the ray to the
## first tread node, which is generated the same arbitrary way.
static func _reference_ray(axis: Vector3) -> Vector3:
    var candidate: Vector3 = Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
    return (candidate - axis * candidate.dot(axis)).normalized()
