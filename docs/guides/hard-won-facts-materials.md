# Hard-won facts: materials and spatial shaders

Audience: anyone writing or changing a `.gdshader` that shades a surface, or any code that reads a
built material back. Split out of `hard-won-facts-light.md` when that file approached the project's
400-line cap; a surface's own shading is a subject of its own, and most of what is below is Godot's
conventions rather than this project's choices.

See `hard-won-facts-light.md` for exposure, skies and anything that measures a frame.

- **Godot's `StandardMaterial3D.clearcoat` does not layer. It trades the paint away for the
  highlight.** Measured on one ball under this project's own noon at a fixed exposure, with nothing
  changing but the coat (`harness/dev/paint_probe.gd`): a coat of 0.25 keeps 0.959 of the bare
  paint head-on, a coat of 1.0 keeps 0.840, and the engine's coat of 1.0 also *darkens* the
  silhouette, from 0.3881 to 0.3415. A clear coat is a dielectric film at IOR 1.5. It reflects 4%
  of what arrives head-on, so the paint under it should lose 4% and not 16%, and what it reflects
  should appear as a reflection rather than vanishing. That artefact is the whole reason
  `material_cfg.gd` carried a car-paint coat of 0.25: panels read as half transparent at any
  higher value, with the truck's own roll bar showing through its bed side. `vehicle_paint.gdshader`
  composes the layers the way `KHR_materials_clearcoat` states instead — `base * (1 - clearcoat *
  F(NdotV)) + clearcoat_brdf` — and keeps 0.952 of the paint at full coverage while lifting the
  silhouette from 0.3895 to 0.3974. `a_clear_coat_keeps_the_paint_under_it` holds it, with the
  engine's own coat in the same frame as the control.

- **`StandardMaterial3D` has no sheen and no transmission in 4.7.** `MaterialCfg` has stated both
  per class since it was written and `MaterialClass.apply` read neither, because there is no
  property to write them to — checked by name against a live material, not from the documentation.
  So every seat and every tyre in the library was drawn as a plain dielectric. A sheen lobe is a
  shader or it is nothing; `a_cloth_lobe_lights_the_silhouette` holds the one in
  `vehicle_paint.gdshader`.

- **Godot multiplies whatever `light()` adds to `DIFFUSE_LIGHT` by `ALBEDO` itself.** A shader that
  applies the albedo in its own diffuse term applies it twice, and the error is invisible on a
  white surface: measured on one mid-grey patch under one sun, the shader read 0.1696 where the
  built-in material read 0.7602, and the gap tracked the albedo rather than being a constant.
  Multiply by `(1.0 - METALLIC)` and the `1/PI`, and nothing else.

- **Writing `ALPHA` at all puts a surface in the transparent pass.** Not writing a value below one —
  writing the builtin. The surface then loses the depth prepass and is sorted per object, and on the
  hero truck the painted panels stopped covering what was behind them: the vehicle's share of the
  frame fell from 53% to 42% and `vehicle_renders` caught it. An opaque material must not mention
  `ALPHA`.

- **`return` does not compile inside `light()`**: "Using 'return' in the 'light' processor function
  is incorrect". A surface facing away from the light has to add nothing rather than be skipped, so
  clamp `NdotL` at zero and let the arithmetic come out as zero.

- **Image-based lighting runs at one roughness per pixel, and a coated surface has two.** The sharp
  one is the one that reads — a car body looks like a car body because the sky slides along its
  shoulder line — so `vehicle_paint.gdshader` hands `ROUGHNESS` to the engine as the coat's and
  carries the paint's own roughness to `light()` in `BACKLIGHT`, which Godot reads only in the
  lighting code the shader replaces. Without that the coat is a pure loss: it takes the Fresnel
  share away from the paint and gives back a direct specular lobe a fraction of a pixel wide, which
  measured as a *darker* silhouette than no coat at all.

- **A second pass over the same geometry drew nothing, and it is not understood.** The obvious way
  to give a coat its own radiance lookup is a `next_pass`, which is what Godot documents layered
  materials for. Tried as a `next_pass` on the mesh's own material, as a `next_pass` on a
  `material_override`, and as a `material_overlay`, with and without `no_depth_test`, opaque
  unshaded red and additive alike: not one pixel of the frame changed, while reddening the base
  shader in the same scene showed immediately. Whatever the reason, the coat's sharp reflection of
  the sky is still Godot's image-based lighting and not a second lobe.

- **A vehicle surface is not always a `StandardMaterial3D` any more**, so do not cast one.
  `MeshAssembler.material_for` returns the layered shader for the classes that need it, and
  `VehiclePaint.albedo_colour`, `.albedo_map` and `.roughness_map` read either kind. The facing
  checks skipped every `ShaderMaterial` on purpose — vegetation and water have no albedo they can
  read — and that skip would have quietly dropped the body panels out of every facing gate the day
  paint stopped being a built-in material.
