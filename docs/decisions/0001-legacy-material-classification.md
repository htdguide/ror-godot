# ADR 0001: Legacy materials become PBR by class, not by hand

Audience: contributors, and mod authors who want to know what happens to their work.

Status: accepted, 2026-09-25. Implemented in M2.

## Context

Rigs of Rods' community library is diffuse-only. An OGRE `.material` script stores a
texture unit and a Blinn-Phong pass: ambient, diffuse and specular colours, a shininess
exponent, blend and cull modes. There is no metallic, no roughness, no normal map, no
ambient occlusion, and no notion of what a surface is made of.

Godot's renderer is metallic-roughness PBR. Feeding it a diffuse texture and nothing
else produces a uniform, plastic-looking surface for every material in the game: chrome
does not reflect, glass does not refract, rubber and leather look identical to painted
steel. The renderer would be objectively better and the game would not look better,
which is the worst possible outcome for this project.

Re-authoring textures is not available: there are thousands of published mods, we do not
own them, and the compatibility promise is that they load unmodified.

## Decision

Every legacy material is assigned a **material class**, and the class supplies the PBR
parameters the legacy format never stored. The mod's own diffuse texture is used as
albedo, unchanged.

Classes and what each one sets: car paint (clearcoat over a tinted base, low roughness),
chrome and bare metal (metallic 1, very low roughness), glass (transmission, Fresnel,
thin-walled, no alpha-blend hack), rubber and tyre (high roughness, no metallic, slight
sheen), leather and cloth (mid-high roughness with sheen), plastic (mid roughness, IOR
1.5), painted rust and dirt (non-metallic, high roughness), lamp lens (transmission plus
emission when lit), carbon fibre (anisotropic).

Classification draws on four sources, in descending order of trust:

1. **The `.material` script.** This is authored data rather than a guess, and most mods
   carry it. The specular colour and shininess exponent map onto roughness directly;
   `scene_blend alpha_blend` identifies glass and decals; `cull_hardware none` identifies
   thin panels, which also need their own shadow-casting treatment. Legacy Blinn-Phong
   shininess is a real signal that is easy to forget is already there.
2. **Names.** Material, texture and submesh names. The community names things
   conventionally enough for this to carry most of the remaining cases.
3. **Image statistics.** Near-neutral, bright and low-detail suggests chrome; very dark
   and low-variance suggests rubber. Too weak to lead, useful to break ties.
4. **A sidecar override** placed next to the mod, never inside it, for anything the
   heuristics get wrong. The mod is not edited and the author re-publishes nothing.

## What we deliberately do not derive

- **Normal maps.** Height-from-luma turns painted logos, lettering and grille decals
  into embossed relief. A wrong guess is more visibly wrong than a flat surface.
- **Ambient occlusion.** No reliable source in a diffuse texture.
- **Metallic, by default.** Guessing metallic from an image is the fastest route to
  making every vehicle look like kitchen foil. Non-metal is the default; metal is
  entered through an explicit class.

## Known limitation: baked-in lighting

Legacy textures frequently have shading, ambient occlusion and specular highlights
painted into the diffuse map. Under PBR with image-based lighting this double-shades: a
highlight painted into the texture plus a real highlight from the sky.

A de-lighting pass can suppress it, but it damages well-authored textures when it
misfires. It is therefore implemented as an opt-in per material rather than applied
across the library, on the same reasoning as the normal-map decision above: for an asset
we do not own and cannot inspect individually, a wrong automatic correction is worse than
a visible but honest limitation.

## Rejected alternatives

- **Uniform default material for everything.** Cheapest, and it forfeits the entire
  visual argument for the rewrite.
- **Hand-authoring PBR sets for the library.** Correct and unbounded. Not a finite task
  for thousands of mods we do not own.
- **Requiring mod authors to supply PBR maps.** Breaks the compatibility promise, and
  the long tail of unmaintained mods would simply never be updated.
- **Machine-learned material assignment from renders.** No oracle to verify it against,
  and the failure mode is confident and wrong across the whole library at once.

## Consequences

- A `material_class` table becomes a real, reviewed asset of this project, and its
  accuracy is measurable: the classifier reports its class distribution and its
  unclassified share over a mod corpus.
- Misclassification is visible and cheap to fix through a sidecar, so the M2 human
  session explicitly asks which materials read wrong, by name.
- Vehicles will look materially different from today even though no texture changed,
  which is the point, and some of that difference will be wrong at first.
