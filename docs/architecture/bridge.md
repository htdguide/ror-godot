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

## Open: applying the actor frame in the render path

The frame's own algebra is verified by `actor_frame_rigid_motion`: rigid vehicle motion
appears in the frame while actor-local bone transforms stay put to within 4e-6, against a
deformation response five orders of magnitude larger.

Wiring it into the render path is still **not done**, and the fault is now named.

`vehicle_assembly` compares the vehicle's drawn silhouette against where its rig projects
it. With the frame wired, the body is drawn **874 x 374 px where the rig places it at
368 x 857 px** — the same extents transposed. The body is rendered rotated exactly 90
degrees, which is the frame's own yaw, applied once and never undone.

That means **the bone transforms are not reaching the vehicle's geometry**: the body is
drawn at `instance * vertex`, not `instance * bone * vertex`. Reading the bones back with
`skeleton_bone_get_transform` returns exactly `T^-1`, so they are written correctly and
simply not used for these meshes.

Two engine questions were eliminated on the way, both by measurement:

- Composition is `instance * bone * vertex`, confirmed at 1 px
  (`skinning_transform_semantics`).
- Rotation is not the problem. `skinned_rotation_sweep` tracks a skinned point through 0,
  30, 60, 85, 90, 95, 180 and 270 degrees of instance yaw, all within 1 px. An earlier
  version of that sweep reported the point vanishing between 85 and 95 degrees; the scene
  had the blockout scale props in it and the point was passing inside one of the boxes.

The difference is not in the mesh either. `skinning_mesh_variants` walks a synthetic mesh
from a single-bone points cloud all the way to the vehicle's shape — unindexed triangles,
indexed triangles, UVs, a `CUSTOM0` stream, a 292-bone skeleton, a bone index of 291, and
an instance whose own transform is identity under a rotated parent. **All eight skin
correctly, within 1 pixel.**

So every property the vehicle's meshes have, in isolation, works. What remains is that for
the real vehicle meshes the model and the pixels disagree: reading bone 0 back gives
exactly `T^-1`, the instance's global transform is exactly the frame, and computing
`instance * bone * vertex` by hand gives precisely the position the rig predicts — while
the drawn silhouette is that shape rotated by the frame's yaw.

The next experiment bisects code path against data: put a synthetic quad through
`SkinnedFlexbody` itself, with the same calls in the same order, and see whether it skins.
If it does, the difference is the real mesh's data — 1860 vertices, 292 triads, real
indices — and the search narrows to what in that data differs from the synthetic case. If
it does not, the difference is in `SkinnedFlexbody`'s own sequence, most likely the fact
that it writes the pose twice: once inside `build()` with an identity frame, and again
immediately afterwards with the real one.

The frame's orientation convention was wrong once and is fixed: upstream's `cameras`
section names a centre, a node *behind* it and a node to its *left*, so the roll node must
be negated to give Godot's +X. Taking it directly leaves a right-handed basis rotated half
a turn, and the vehicle renders upside down — which it did.

## Still to build

The actor-local reference frame. Upstream sets the scene node's position and never its
orientation, so today all vehicle rotation is baked into vertices. The bridge must build a
frame from the same three reference nodes and express bone transforms in actor-local
space, or the instance transform carries no rotation and TAA smears every turning vehicle.
