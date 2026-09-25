class_name FlexReference
extends RefCounted
## Rigs of Rods' FlexBody deformation, ported verbatim, as the ground truth the skinned
## path is measured against.
##
## From FlexBody::computeFlexbody() in the upstream source:
##
##     diffX  = P[nx] - P[ref]
##     diffY  = P[ny] - P[ref]
##     nCross = normalize(diffX x diffY)
##     dst    = diffX*c.x + diffY*c.y + nCross*c.z + P[ref] - center
##
## Written as a matrix F with columns (diffX, diffY, nCross), that is dst = F*c + P[ref]
## - center: one affine transform applied to a constant per-vertex vector. That is
## single-bone linear blend skinning, exactly, which is what the spike verifies Godot
## reproduces on the GPU.


static func deform_vertex(
    nodes: PackedVector3Array,
    ref: int,
    nx: int,
    ny: int,
    coords: Vector3,
    center: Vector3
) -> Vector3:
    return triad_transform(nodes, ref, nx, ny, center) * coords


## The locator triad's frame as an affine transform. Its basis is deliberately
## non-orthonormal: the columns carry the stretch and shear of the node triangle, which
## is what makes the deformation soft rather than rigid. Any API that decomposes a pose
## into translation, rotation and scale destroys exactly this, which is why the bridge
## writes bone transforms through RenderingServer rather than through Skeleton3D.
static func triad_transform(
    nodes: PackedVector3Array, ref: int, nx: int, ny: int, center: Vector3
) -> Transform3D:
    var origin: Vector3 = nodes[ref]
    var diff_x: Vector3 = nodes[nx] - origin
    var diff_y: Vector3 = nodes[ny] - origin
    var n_cross: Vector3 = diff_x.cross(diff_y).normalized()
    return Transform3D(Basis(diff_x, diff_y, n_cross), origin - center)


## Deforms every vertex the way FlexBody does, for a whole pose.
static func deform_all(
    nodes: PackedVector3Array, lattice: FlexLattice, center: Vector3
) -> PackedVector3Array:
    var out: PackedVector3Array = PackedVector3Array()
    out.resize(lattice.vertex_count())
    for i: int in lattice.vertex_count():
        out[i] = deform_vertex(
            nodes, lattice.loc_ref[i], lattice.loc_nx[i], lattice.loc_ny[i],
            lattice.loc_coords[i], center
        )
    return out


## Bone transforms for one pose: one per unique triad, in the same order as the bones.
static func bone_transforms(
    nodes: PackedVector3Array, lattice: FlexLattice, center: Vector3
) -> Array[Transform3D]:
    var out: Array[Transform3D] = []
    for b: int in lattice.bone_count():
        out.append(
            triad_transform(nodes, lattice.triad_ref[b], lattice.triad_nx[b], lattice.triad_ny[b], center)
        )
    return out
