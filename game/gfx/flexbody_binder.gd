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

## Upstream requires the third node to be within 45 degrees of orthogonal to ref->nx:
## |dot| <= sqrt(2)/2. This is not a detail. A merely non-collinear third node produces a
## sliver frame whose inverse is enormous, and the bind coordinates computed through it
## explode, which collapses the mesh the moment it is skinned.
const ORTHOGONALITY_LIMIT: float = 0.70710678
## Upstream falls back to node 0 when nothing satisfies the criterion. Counted rather
## than hidden, because a mesh needing the fallback often is a mesh bound to the wrong
## node set.
const FALLBACK_NODE: int = 0


## Rig-space transform for one flexbody entry.
## `upstream_rotation` picks how the authored angles are composed. See `authored_rotation`: a
## flexbody wants upstream's order, a prop does not, and they are not the same question.
static func placement(
    nodes: PackedVector3Array, entry: Dictionary, upstream_rotation: bool = false
) -> Transform3D:
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
    return Transform3D(
        axes * authored_rotation(entry["rot_deg"] as Vector3, upstream_rotation), position
    )


## The authored angles as a rotation, composed the way the thing being placed expects.
##
## **Upstream composes Z, then Y, then X** — `FlexFactory.cpp:91-93` for a flexbody. Measured
## against `Basis.from_euler`, whose default order is YXZ, the two are **identical** for the hero
## truck's flexbodies (`180, -90, 0`) and differ by exactly 180 degrees about X for the Mazda 626
## (`270, 180, 180`). That 180 is the whole of the fault: the Mazda loaded upside down, roof to
## the road, fully textured and the right way round in every other respect.
##
## So this is a loader fix and not a car fix. Any mod whose flexbody rotation turns about more
## than one axis was being placed by the wrong composition; the hero truck never noticed because
## its own numbers make the two orders agree, which is exactly how a convention bug survives.
##
## **Props keep the old composition, and that is deliberate rather than tidy.** Upstream uses the
## same Z, Y, X order for them (`ActorSpawner.cpp:1681-1683`) but builds a prop's base frame
## differently from a flexbody's, so applying the flexbody change to props alone turns the hero
## truck's steering column to point up and forward instead of down, which
## `props_sit_in_the_vehicle` catches on a physical expectation. Fixing props properly means
## porting their own placement, which is a separate piece of work with its own evidence.
static func authored_rotation(rot_deg: Vector3, upstream: bool) -> Basis:
    if upstream:
        return (
            Basis(Vector3.BACK, deg_to_rad(rot_deg.z))
            * Basis(Vector3.UP, deg_to_rad(rot_deg.y))
            * Basis(Vector3.RIGHT, deg_to_rad(rot_deg.x))
        )
    return Basis.from_euler(
        Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))
    )


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


## Full binding for a placed mesh: which triad each vertex belongs to, the triads
## themselves, and each vertex's bind-space coordinates. This is what the skinning path
## needs; bind_stats above only counts.
static func bind(
    nodes: PackedVector3Array, forset: PackedInt32Array, vertices: PackedVector3Array
) -> Dictionary:
    var triads: Array[Vector3i] = []
    var triad_index: Dictionary = {}
    var bone_of_vertex: PackedInt32Array = PackedInt32Array()
    var coords: PackedVector3Array = PackedVector3Array()
    bone_of_vertex.resize(vertices.size())
    coords.resize(vertices.size())

    for i: int in vertices.size():
        var triad: Vector3i = _triad_for(nodes, forset, vertices[i])
        if triad.x < 0:
            bone_of_vertex[i] = 0
            coords[i] = Vector3.ZERO
            continue
        var key: String = "%d_%d_%d" % [triad.x, triad.y, triad.z]
        if not triad_index.has(key):
            triad_index[key] = triads.size()
            triads.append(triad)
        bone_of_vertex[i] = triad_index[key] as int
        coords[i] = FlexReference.triad_transform(
            nodes, triad.x, triad.y, triad.z, Vector3.ZERO
        ).affine_inverse() * vertices[i]

    return {"triads": triads, "bone_of_vertex": bone_of_vertex, "coords": coords}


## Bone transforms for a pose: one per triad, in the same order as `triads`.
static func bone_transforms(
    nodes: PackedVector3Array, triads: Array[Vector3i]
) -> Array[Transform3D]:
    var out: Array[Transform3D] = []
    for triad: Vector3i in triads:
        out.append(FlexReference.triad_transform(nodes, triad.x, triad.y, triad.z, Vector3.ZERO))
    return out


## CPU reference positions for a pose, the way FlexBody computes them.
static func reference_positions(
    nodes: PackedVector3Array, binding: Dictionary, triads: Array[Vector3i]
) -> PackedVector3Array:
    var coords: PackedVector3Array = binding["coords"] as PackedVector3Array
    var bone_of_vertex: PackedInt32Array = binding["bone_of_vertex"] as PackedInt32Array
    var frames: Array[Transform3D] = bone_transforms(nodes, triads)
    var out: PackedVector3Array = PackedVector3Array()
    out.resize(coords.size())
    for i: int in coords.size():
        out[i] = frames[bone_of_vertex[i]] * coords[i]
    return out


static func _triad_for(
    nodes: PackedVector3Array, forset: PackedInt32Array, vertex: Vector3
) -> Vector3i:
    var ref: int = _nearest(nodes, forset, vertex, -1, -1)
    if ref < 0:
        return Vector3i(-1, -1, -1)
    var nx: int = _nearest(nodes, forset, vertex, ref, -1)
    if nx < 0:
        return Vector3i(-1, -1, -1)
    var ny: int = _nearest_orthogonal(nodes, forset, vertex, ref, nx)
    return Vector3i(ref, nx, ny)


static func _nearest(
    nodes: PackedVector3Array,
    forset: PackedInt32Array,
    vertex: Vector3,
    exclude_a: int,
    exclude_b: int
) -> int:
    var best: int = -1
    var best_distance: float = INF
    for node: int in forset:
        if node == exclude_a or node == exclude_b:
            continue
        var distance: float = nodes[node].distance_squared_to(vertex)
        if distance < best_distance:
            best_distance = distance
            best = node
    return best


## The nearest node whose direction from ref is within 45 degrees of orthogonal to
## ref->nx, which is what keeps the triad frame well conditioned.
static func _nearest_orthogonal(
    nodes: PackedVector3Array, forset: PackedInt32Array, vertex: Vector3, ref: int, nx: int
) -> int:
    var vx: Vector3 = (nodes[nx] - nodes[ref]).normalized()
    var best: int = -1
    var best_distance: float = INF
    for node: int in forset:
        if node == ref or node == nx:
            continue
        var distance: float = nodes[node].distance_squared_to(vertex)
        if distance >= best_distance:
            continue
        var vt: Vector3 = (nodes[node] - nodes[ref]).normalized()
        if absf(vx.dot(vt)) > ORTHOGONALITY_LIMIT:
            continue
        best_distance = distance
        best = node
    return FALLBACK_NODE if best < 0 else best
