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

Wiring it into the render path is still **not done**, and the reason is now sharper than
"it looked wrong".

The wiring was redone as one atomic change — frame on the root, bones actor-local, wheel
placements actor-local — with `vehicle_assembly` written first to check it numerically.
That gate compares every part's rendered vertex positions and every wheel's drawn geometry
against the rig's own node positions, relative to a reference vertex so the result does
not depend on where the vehicle is placed for the camera.

**With the frame wired, the gate measures every part within 0.001 mm and every wheel
within 0 mm of its rig position, and the render still puts two wheels out on open ground.**

The gate and the image disagree, so one of them is wrong, and the gate is what to fix
first: a gate that passes while the render is visibly broken is worse than having no gate,
because it will be trusted later on a change nobody looks at. Candidate explanations, none
yet confirmed:

- The gate models the renderer's composition rather than reading the frame, so a
  divergence between model and engine is invisible to it — even though that composition is
  itself measured by `skinning_transform_semantics`.
- The wheel check compares `mesh.get_aabb()` transformed by the node's global transform,
  which is the same model, not the drawn result.

The way to settle it is to make the check read pixels rather than transforms: project each
wheel's axle midpoint to screen and require the rendered pixel there to belong to the
vehicle. That closes the loop the current gate leaves open.

Until then the render path stays in rig space, where it is verified correct, and the frame
is computed but unused there.

The frame's orientation convention was wrong once and is fixed: upstream's `cameras`
section names a centre, a node *behind* it and a node to its *left*, so the roll node must
be negated to give Godot's +X. Taking it directly leaves a right-handed basis rotated half
a turn, and the vehicle renders upside down — which it did.

## Still to build

The actor-local reference frame. Upstream sets the scene node's position and never its
orientation, so today all vehicle rotation is baked into vertices. The bridge must build a
frame from the same three reference nodes and express bone transforms in actor-local
space, or the instance transform carries no rotation and TAA smears every turning vehicle.
