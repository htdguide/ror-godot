# ADR 0005: Godot winds front faces clockwise, and two gates had it backwards

Audience: contributors.

Status: accepted, 2026-10-03.

## The claim

Godot draws a triangle as front-facing when its vertices run **clockwise** in screen space.
Equivalently, for a triangle `(a, b, c)` with an authored normal `n`, the triangle faces the way
its normal points when

    cross(b - a, c - a) · n <= 0

and a closed mesh wound outward encloses a **negative** signed volume under `Σ a · (b × c) / 6`.

## How it was settled

Not by argument. By measuring meshes the engine builds and draws itself, which are correct by
construction:

| mesh | agreement under `· n >= 0` | signed enclosed share |
|---|---|---|
| `BoxMesh` | 0.0% | -1.00 |
| `SphereMesh` | 0.0% | -0.52 |
| `CylinderMesh` | — | -0.78 |

Both probes are in `history/` and both checks now run inside the gates that depend on them, as a
control that fails the gate before it reports anything about content.

## What it cost

`an_object_is_wound_the_way_its_file_is` and `a_closed_object_encloses_its_own_volume` were both
written with the opposite sign. Both were green. To make them green, `ObjectWinding.arrays` was
changed to un-reverse what `OgreMeshReader` hands over — which turned **every terrain object in
the library inside out**, and the un-reversal was then documented as a fact about the vehicle path
rather than as a sign error.

Nothing in the suite could see it, because a back face is culled and a wall turned the wrong way
renders as empty sky: the fault and the absence of the fault are the same photograph. It was
visible only from a window, and was reported three times in those terms — "walls visible from one
side only", "the outside texture is facing inside", "broken textures which are visible only when
being inside of the building".

## What follows from it

- `OgreMeshReader`'s reversal is the Ogre-to-Godot conversion, for a vehicle and for a building
  alike. There is no object-only correction.
- 20 of the library's 433 closed object meshes are wound inward **in their own files** —
  `store02`, `firehouse`, `haus3`, `haus4`, Russia's `hall`, La Paz's horizon and ground skirt.
  Those are turned per mesh by `ObjectWinding.is_inside_out`, winding and normals together,
  decided by signed volume so that no normal is needed to decide it. **La Paz's horizon and ground
  skirt are in that list and a horizon is a thing you stand inside**; if either reads wrong from a
  session window, that is where to look first.
- A gate may not assert a convention. If a claim depends on one, it measures the engine's own
  output first and fails as a broken instrument rather than as a finding. `object_photoset`
  photographs `BoxMesh` before any content for the same reason.
