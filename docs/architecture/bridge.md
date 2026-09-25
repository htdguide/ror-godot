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

## Open: applying the actor frame in the render path

The frame itself is verified. `actor_frame_rigid_motion` shows rigid vehicle motion
appearing in the frame while actor-local bone transforms stay put to within 4e-6, against
a deformation response five orders of magnitude larger.

Wiring it into the render path is a separate matter and is **not done**. Putting the frame
on the vehicle root while expressing bones and wheel placements in actor-local space
should be a no-op by construction — `T * (T^-1 * v)` is `v` — and it is not: the body and
the wheels separate by roughly half a metre, consistently, while both are individually
correct when the frame is identity.

Rather than ship a transform that is half understood, the render path stays in rig space
and the frame is computed but unused there. Two things are known and worth writing down
for whoever picks this up:

- With `ActorFrame.of()` forced to identity, the full vehicle renders correctly: body,
  wheels in their arches, everything. So the skinning path and the wheel path are each
  right on their own.
- The frame's own orientation convention was wrong once already and is now fixed:
  upstream's `cameras` section names a centre, a node *behind* it and a node to its
  *left*, so the roll node must be negated to give Godot's +X. Taking it directly leaves a
  right-handed basis rotated half a turn, and the vehicle renders upside down — which is
  what it did.

## Still to build

The actor-local reference frame. Upstream sets the scene node's position and never its
orientation, so today all vehicle rotation is baked into vertices. The bridge must build a
frame from the same three reference nodes and express bone transforms in actor-local
space, or the instance transform carries no rotation and TAA smears every turning vehicle.
