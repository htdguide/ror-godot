# ADR 0003: The bridge needs two deformation paths, not one

Audience: contributors.

Status: accepted, 2026-09-25. Extends ADR 0002.

## Context

ADR 0002 established that FlexBody deformation is exactly single-bone linear blend
skinning. That covers vehicles whose visual geometry comes from external OGRE meshes
through the `flexbodies` section.

It does not cover the other path. Rigs of Rods also builds geometry procedurally from
the `submesh` / `texcoords` / `cab` sections, handled by `FlexObj`, and that path is not
a corner case: both vehicles in upstream's own content pack use it exclusively, with no
`flexbodies` and no `.mesh` files at all.

## What FlexObj actually does

Per frame, from the upstream twin and source:

    centre      = midpoint of the first two vertices' nodes
    position[v] = node(v) - centre
    for each triangle:
        n = (p1-p0) x (p2-p0); s = |n|
        if s > reference_area: collapse the triangle       # torn panels vanish
        accumulate n/s into the three vertex normals
    normalise the accumulated normals

Three things follow. **Positions are trivially skinnable**: a vertex is a node, so it is
bone-per-node with translation-only transforms, even simpler than FlexBody. **Normals are
not**: they are recomputed each frame from triangle geometry and smoothed across shared
vertices, while skinning would carry the bind-pose normal through a translation and leave
it unchanged. **Tearing is not**: a triangle whose area exceeds its spawn reference is
collapsed to a degenerate, which is how torn body panels disappear, and that is a
per-triangle geometry edit no bone transform can express.

## Decision

Two paths, chosen per mesh at load time:

- **FlexBody meshes skin**, per ADR 0002: one bone per locator triad, full affine bone
  transforms through RenderingServer. These are the large, detailed meshes where the
  bandwidth and motion-vector wins matter.
- **FlexObj meshes skin their positions** with one bone per node, and stream a recomputed
  normal buffer. Positions through bones keeps motion vectors working, which is the part
  that matters for milestone (b); normals are small for these meshes — vertex counts are
  in the hundreds — so streaming only the normal region is cheap and preserves upstream's
  smoothing exactly rather than approximating it with a flat-shaded derivative.

Choosing per mesh rather than per vehicle matters: a vehicle can use both, with a
procedural cab and external meshes for body parts.

## Open: tearing

Collapsing a stretched triangle is a per-triangle operation and does not fit either
skinning path. Two candidate treatments, neither yet chosen:

1. A per-triangle visibility mask in a small buffer, with the shader discarding
   collapsed triangles.
2. An index-buffer update that drops collapsed triangles, keeping the vertex data
   untouched.

The second is likely cheaper and keeps the vertex path pure, but it makes the index
buffer dynamic. This is deferred until a vehicle in the harness can actually be torn,
because guessing without a test case is how the wrong one gets chosen.

## Consequence for hero-asset choice

A `submesh`-only vehicle exercises FlexObj and never FlexBody; a `flexbodies` vehicle
does the reverse. The M1 corpus therefore needs at least one of each, and upstream's
content pack supplies only the FlexObj kind — a community vehicle with `flexbodies` must
be fetched to measure real locator-triad bone counts, which remains open from ADR 0002.
