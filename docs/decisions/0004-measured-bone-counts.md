# ADR 0004: Measured bone counts, and a correction to ADR 0002's expectation

Audience: contributors.

Status: accepted, 2026-09-25. Closes the bone-count question ADR 0002 left open.

## Measurement

Hero asset, `S10offroad.truck`, 255 nodes, flexbodies placed and bound with upstream's
own rules (nearest node, nearest of the rest, nearest non-collinear third):

    6456 vertices bind to 1077 locator triads
    51 696 bytes/frame skinned   vs   154 944 bytes/frame streamed   =  3.0x

Per mesh, vertices to bones: body 1860/303, bed 1035/214, door 702/94, hood 644/64,
front bumper 603/28, gauges 40/8, windows 57/45, door glass 3/2.

## Correction

ADR 0002 said the skinning path would upload "kilobytes rather than hundreds of
kilobytes". On a real vehicle the saving is **3x, not orders of magnitude**. The estimate
was made before any vehicle had been measured and it was too optimistic; the figure above
is the one to use.

Two reasons the real number is lower. Locator triads are far more numerous than intuition
suggests, because a triad is per *vertex neighbourhood* rather than per panel: 1860
vertices over 92 candidate nodes still produce 303 distinct nearest-three combinations.
And small meshes bind almost one triad per vertex — the door glass needs 2 bones for 3
vertices.

## What survives, and why the decision does not change

- **3x is still a real saving**, and it is measured rather than assumed.
- **Bone count is independent of mesh detail.** This is the part that matters. Triads are
  a function of the node rig, not of the geometry bound to it, so tripling a vehicle's
  polygon count triples the streamed cost and leaves the skinned cost flat. Raising
  vehicle detail is a stated goal of this project, so the gap widens exactly where it is
  wanted.
- **Motion vectors remain the real prize**, unchanged by this measurement.
- Deformation still runs on the GPU rather than on CPU the solver wants.

## Routing rule

Skinning is chosen per mesh, not per vehicle: a mesh skins when it uploads fewer bytes
that way, and streams otherwise. On the hero asset four meshes fall on the streaming side
— both window meshes and both door-glass meshes, at 1.2x to 1.3x — and they are tiny, so
the streaming path costs almost nothing there. This is the third routing rule alongside
the FlexBody and FlexObj split in ADR 0003.

## Gate

`flexbody_bone_count` measures bytes per frame both ways and requires skinning to win by
at least 2x across the vehicle. Its first version required a per-mesh ratio instead and
failed on the door glass, which was the gate being wrong rather than the design: one bad
mesh is a routing choice, not a refutation.
