class_name FlexbodyBinder
extends RefCounted
## Places a flexbody's mesh into rig space and assigns each vertex its locator triad,
## following FlexBody's constructor.
##
## Placement, from upstream:
##     normal      = normalize(diffY x diffX)
##     position    = P[ref] + offset.x*diffX + offset.y*diffY + offset.z*normal
##     refX        = normalize(diffX); refY = refX x normal
##     orientation = Quaternion(refX, normal, refY) * rot
##
## Binding, per vertex: ref is the nearest node, nx the nearest of the rest, ny the
## nearest of what remains that does not lie along ref->nx. The number of distinct
## (ref, nx, ny) triples is the bone count a skinned vehicle needs, which is the figure
## ADR 0002 left open.

const DEGENERATE_EPSILON: float = 0.0001


## Rig-space transform for one flexbody entry.
static func placement(nodes: PackedVector3Array, entry: Dictionary) -> Transform3D:
    var origin: Vector3 = nodes[entry["ref"] as int]
    var diff_x: Vector3 = nodes[entry["nx"] as int] - origin
    var diff_y: Vector3 = nodes[entry["ny"] as int] - origin
    var normal: Vector3 = diff_y.cross(diff_x).normalized()
    var offset: Vector3 = entry["offset"] as Vector3
    var position: Vector3 = origin + offset.x * diff_x + offset.y * diff_y + offset.z * normal
    var ref_x: Vector3 = diff_x.normalized()
    var ref_y: Vector3 = ref_x.cross(normal)
    # Upstream builds the orientation from the three axes, then applies the authored
    # rotation. Basis columns are those axes, in the same order.
    var axes: Basis = Basis(ref_x, normal, ref_y)
    var rot_deg: Vector3 = entry["rot_deg"] as Vector3
    var authored: Basis = Basis.from_euler(
        Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))
    )
    return Transform3D(axes * authored, position)


## Returns {"triads": int, "vertices": int, "shared": float} for one placed mesh.
## `shared` is the average number of vertices per triad, which is what decides whether
## bone-per-triad is cheaper than streaming vertices.
static func bind_stats(
    nodes: PackedVector3Array, forset: PackedInt32Array, vertices: PackedVector3Array
) -> Dictionary:
    var seen: Dictionary = {}
    for vertex: Vector3 in vertices:
        var triad: Vector3i = _triad_for(nodes, forset, vertex)
        if triad.x < 0:
            continue
        seen["%d_%d_%d" % [triad.x, triad.y, triad.z]] = true
    var triads: int = seen.size()
    return {
        "triads": triads,
        "vertices": vertices.size(),
        "shared": 0.0 if triads == 0 else float(vertices.size()) / float(triads),
    }


static func _triad_for(
    nodes: PackedVector3Array, forset: PackedInt32Array, vertex: Vector3
) -> Vector3i:
    var ref: int = _nearest(nodes, forset, vertex, -1, -1, Vector3.ZERO)
    if ref < 0:
        return Vector3i(-1, -1, -1)
    var nx: int = _nearest(nodes, forset, vertex, ref, -1, Vector3.ZERO)
    if nx < 0:
        return Vector3i(-1, -1, -1)
    # ny must not be collinear with ref->nx, or the triad frame has no normal.
    var axis: Vector3 = (nodes[nx] - nodes[ref]).normalized()
    var ny: int = _nearest(nodes, forset, vertex, ref, nx, axis)
    if ny < 0:
        return Vector3i(-1, -1, -1)
    return Vector3i(ref, nx, ny)


static func _nearest(
    nodes: PackedVector3Array,
    forset: PackedInt32Array,
    vertex: Vector3,
    exclude_a: int,
    exclude_b: int,
    reject_axis: Vector3
) -> int:
    var best: int = -1
    var best_distance: float = INF
    for node: int in forset:
        if node == exclude_a or node == exclude_b:
            continue
        if reject_axis != Vector3.ZERO and exclude_a >= 0:
            var along: Vector3 = (nodes[node] - nodes[exclude_a]).normalized()
            if absf(along.cross(reject_axis).length()) < DEGENERATE_EPSILON:
                continue
        var distance: float = nodes[node].distance_squared_to(vertex)
        if distance < best_distance:
            best_distance = distance
            best = node
    return best
