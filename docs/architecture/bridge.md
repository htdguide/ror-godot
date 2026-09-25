# The softbody-to-Godot bridge

Audience: contributors.

Rigs of Rods' solver computes node positions; Godot draws meshes. This document is how
the first becomes the second. The decisions behind it are ADR 0002 (skinning), ADR 0003
(two deformation paths) and ADR 0004 (measured bone counts).

## The identity

FlexBody computes, per vertex:

    diffX  = P[nx] - P[ref]
    diffY  = P[ny] - P[ref]
    nCross = normalize(diffX x diffY)
    dst    = diffX*c.x + diffY*c.y + nCross*c.z + P[ref] - centre

With `F` the matrix whose columns are `(diffX, diffY, nCross)`, that is `dst = F*c +
P[ref] - centre`: one affine transform applied to a constant per-vertex vector, which is
single-bone linear blend skinning with weight 1.0. The bone is the locator triad's frame
and `c` is the bind-space position.

## Binding

Per vertex, upstream picks three nodes from the flexbody's `forset`:

1. `ref` — the nearest node.
2. `nx` — the nearest of the rest.
3. `ny` — the nearest remaining node whose direction from `ref` is **within 45 degrees of
   orthogonal** to `ref->nx`, that is `|dot| <= sqrt(2)/2`. Falls back to node 0 when
   nothing qualifies.

The orthogonality criterion is load-bearing and not an optimisation. A merely
non-collinear third node produces a sliver frame whose inverse is enormous; bind
coordinates computed through it are huge, and the mesh collapses the moment it is
skinned. Implementing "not collinear" instead of "roughly orthogonal" produced exactly
that, and the failure looks like broken skinning rather than a broken bind.

Bind coordinates are `c = F_bind^-1 * (v - P[ref])`, matching upstream.

## Driving it

Each frame, per bone: `RenderingServer.skeleton_bone_set_transform(skeleton, bone,
F_current * F_bind^-1)`.

Three details that are easy to get wrong:

- **Never `Skeleton3D`'s pose API.** `F` is non-orthonormal: its columns carry the stretch
  and shear of the node triangle, which is what makes the deformation soft rather than
  rigid. A pose stored as translation, rotation and scale discards shear silently, and the
  result is a subtly stiff vehicle with no error anywhere to find.
- **Set an explicit `custom_aabb`.** A server-driven skeleton has no node tracking its
  deformed bounds, so the instance is culled against its bind-pose bounds and vanishes as
  soon as it deforms far enough.
- **Node names must be unique.** Godot discards a duplicate name and replaces it with a
  generated one, so anything finding nodes by name stops working while the render still
  looks correct.
- **Attach the skeleton once the instance is in the tree**, or re-attach on `tree_entered`.
  An attachment made outside the tree is lost on entry and the mesh draws unskinned.

## Two paths

`flexbodies` meshes skin, as above. `submesh`/`cab` geometry is FlexObj: a vertex is a
node, so positions skin trivially with one bone per node, but normals are recomputed from
triangle geometry every frame and over-stretched triangles are collapsed to fake tearing.
Neither survives skinning, so those meshes skin positions and stream recomputed normals.
See ADR 0003; tearing is still open.

Routing is per mesh, not per vehicle: a mesh skins when it uploads fewer bytes that way.
On the hero vehicle four small glass meshes fall on the streaming side.

## What is verified, and what is not

`flexbody_lbs_equivalence` proves the identity on a synthetic lattice under extreme
poses. `vehicle_skinning` proves it on a real mod's body mesh: 1860 vertices, 292 bones,
max error 0.40 mm across rest, heave, twist, pitch and crush. Both carry a negative
control that injects a known bone error and fails if the measurement misses it, plus a
minimum geometry coverage, because a correct result paints black and an empty frame would
otherwise score as perfect.

Not yet verified: that motion vectors follow from Godot's previous-bone-pose path. That is
M3's `mv_correctness` gate, and until it passes the claim stays an expectation.

## Transform composition, measured

For a `MeshInstance3D` with a skeleton attached through
`RenderingServer.instance_attach_skeleton`, the engine composes:

    world = instance_global_transform * bone_transform * vertex

This is measured, not assumed. `skinning_transform_semantics` renders one vertex with one
bone and one instance transform, and compares the rendered pixel against each candidate
composition: the documented one lands within 1 pixel, while "instance ignored" and "bone
ignored" are 319 and 227 pixels away. It was written because inference from assembled
vehicle renders produced a contradiction, and guessing at engine semantics from a complex
scene is how a wrong convention gets baked in permanently.

Also verified by readback: `SkinnedFlexbody.set_pose` writes exactly `T^-1 * F_current *
F_bind^-1`, confirmed against `RenderingServer.skeleton_bone_get_transform`.

## The actor frame, and the bug that hid behind it

The frame is wired: the vehicle root carries it, bones and wheel placements are
actor-local, and `vehicle_assembly` measures every part and wheel within a millimetre of
its rig position with the drawn silhouette agreeing.

Getting there took four rounds, and the cause was none of the things it looked like:

> **A skeleton attached to a `MeshInstance3D` that is outside the scene tree is lost when
> that node enters the tree.** The mesh then draws unskinned, with no error anywhere.

`VehicleBuilder` builds its parts and hands back a root that the caller adds to the tree,
so every attachment was being discarded a moment after it was made. Every check that
modelled the renderer agreed with itself — bone readback returned `T^-1`, the instance's
global transform was the frame, and `instance * bone * vertex` computed by hand matched the
rig — because the model was right and the GPU simply was not using the bones.
`SkinnedFlexbody` now re-attaches on `tree_entered`, which also makes it independent of
whether its parent was in the tree when it was built.

What the search cost, and what it bought: composition, rotation, every mesh property, the
class itself and the real data at every size were each eliminated by measurement, and each
of those is now a gate. Three separate false leads came from the same mistake — comparing a
measurement of what is *visible* against a computation over *everything*:

- sampling individual vertices on a top-down view, where half of them are occluded;
- a rotation sweep whose scene still contained the blockout scale props, so the point
  passed inside a box and appeared to vanish;
- a scale test comparing the centroid of visible pixels against the projected centroid of
  an object extending outside the frame.

The gate that finally caught the real fault compares *silhouettes*, per part, of geometry
kept fully in frame.

The frame's orientation convention was wrong once and is fixed: upstream's `cameras`
section names a centre, a node *behind* it and a node to its *left*, so the roll node must
be negated to give Godot's +X. Taking it directly leaves a right-handed basis rotated half
a turn, and the vehicle renders upside down — which it did.

## Still to build

The actor-local reference frame. Upstream sets the scene node's position and never its
orientation, so today all vehicle rotation is baked into vertices. The bridge must build a
frame from the same three reference nodes and express bone transforms in actor-local
space, or the instance transform carries no rotation and TAA smears every turning vehicle.
