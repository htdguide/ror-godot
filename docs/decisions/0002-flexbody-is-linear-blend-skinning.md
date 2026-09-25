# ADR 0002: FlexBody deformation is linear blend skinning, and the bridge uses it

Audience: contributors.

Status: accepted, 2026-09-25. Verified on GPU by the `flexbody_lbs_equivalence` gate.
Resolves risks R1 and R2 from the project plan.

## Context

The plan's single largest risk was whether Rigs of Rods' FlexBody deformation can be
expressed as linear blend skinning. Everything downstream rested on it. If it can, the
bridge uploads a few thousand bone transforms per actor per frame instead of hundreds of
kilobytes of vertex data, the deformation runs on the GPU, and — the real prize — motion
vectors come from Godot's own previous-bone-pose path, which is what milestone (b) needs
and what stock Godot does not provide for a mesh whose vertices are rewritten by hand.

## The finding

From `FlexBody::computeFlexbody()` in the upstream source, per vertex:

    diffX  = P[nx] - P[ref]
    diffY  = P[ny] - P[ref]
    nCross = normalize(diffX x diffY)
    dst    = diffX*c.x + diffY*c.y + nCross*c.z + P[ref] - center

Writing `F` for the 3x3 matrix whose columns are `(diffX, diffY, nCross)`, this is

    dst = F*c + (P[ref] - center)

— one affine transform applied to a constant per-vertex vector `c`. That is single-bone
linear blend skinning with weight 1.0, where the bone is the locator triad's frame and
`c` is the bind-space position. Not an approximation: an identity.

Normals are transformed by the same `F` (upstream does not use the inverse transpose
either), which is exactly what Godot's skinning does, so normals agree for the same
reason.

## Decision

The bridge skins. Specifically:

1. **One bone per unique locator triad**, not per node. A triad is `(ref, nx, ny)`.
2. **Bone transforms are written through `RenderingServer.skeleton_bone_set_transform`,
   never through `Skeleton3D`'s pose API.** `F` is deliberately non-orthonormal: its
   columns carry the stretch and shear of the node triangle, which is what makes the
   deformation soft rather than rigid. Any API storing a pose as translation, rotation
   and scale discards shear silently, and the result would be a subtly stiff truck with
   no error anywhere to find.
3. The transform written is the full skinning matrix, `F_current * F_bind.inverse()`.
4. The instance is an ordinary `MeshInstance3D`; only the skeleton is server-driven.
5. **An explicit `custom_aabb` is required.** A server-driven skeleton has no
   `Skeleton3D` node tracking deformed bounds, so the instance is otherwise culled
   against its bind-pose bounds and vanishes as soon as it deforms.

## Evidence

`flexbody_lbs_equivalence` builds a synthetic lattice, binds vertices to triads exactly
as the upstream spawner does, and drives it through six poses including shear,
non-uniform scale and a combined extreme case that far exceeds anything a vehicle
reaches. The CPU reference is computed with the upstream formula and handed to the GPU
as a vertex attribute; a shader measures, per vertex, the distance between Godot's
skinned result and that reference.

Result: 720 bones, 4320 vertices, **max error 0.0000 mm in every pose**, threshold 1 mm.

The gate carries a negative control: a deliberate 5 mm error is injected into one bone
and the measurement must detect it. Without that control the gate would pass just as
happily if the shader, the capture or the decode were broken and every pixel read zero —
which is precisely what happened during development, twice. It also enforces a minimum
geometry coverage, because a perfect result paints black and is otherwise
indistinguishable from nothing rendering at all.

## Consequences

- Per-frame upload becomes bone transforms, not vertices: kilobytes rather than hundreds
  of kilobytes per actor, and independent of mesh detail. Raising vehicle poly counts
  costs nothing on the CPU side, which matters because that is the point of the rewrite.
- Deformation moves to the GPU, leaving CPU for the solver.
- Motion vectors are expected to follow from Godot's previous-bone-pose path. Expected,
  not proven: the `mv_correctness` gate in M3 proves it, and until it does this remains
  an expectation.
- **Rigs of Rods sets scene node position only, never orientation**
  (`m_scene_node->setPosition(m_flexit_center)`), so today every bit of vehicle rotation
  is baked into vertices. The bridge must build a full reference frame from the same
  three nodes and express bone transforms in actor-local space, or the instance
  transform carries no rotation and TAA smears every turning truck. Confirmed in the
  source rather than assumed.

## Open questions

- **Bone count on real vehicles.** The spike used 720. A real truck's count is its
  number of unique locator triads, which must be measured on actual mods in M1 along
  with Godot's practical ceiling.
- **FlexMeshWheel** is generated geometry on a different path and is not covered by this
  identity. It needs its own treatment.

## Footnote: an unresolved anomaly

Instances created directly with `RenderingServer.instance_create2` (or
`instance_create` plus `instance_set_base`/`instance_set_scenario`) rendered nothing in
this project, with valid RIDs, an explicit transform, visibility, layer mask and custom
AABB all set, while the identical mesh in a `MeshInstance3D` rendered correctly. The
cause was not found. It is not on the path the bridge needs, so it was not pursued
further; it is recorded here in case it resurfaces.
