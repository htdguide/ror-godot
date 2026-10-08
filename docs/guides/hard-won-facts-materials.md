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

- **A coated surface has two roughnesses and the engine takes one, so pick between them by
  Fresnel.** Handing it the coat's outright makes every panel a 0.06-roughness mirror of the sky at
  every angle, which is wrong in a way that only shows when the sky and the ground are far apart in
  brightness: reported from a window at 6.1 h, the hero truck's bed shining at dawn. A sun 1.62
  degrees up puts almost nothing on a horizontal panel directly, and the dawn sky is within a stop
  and a half of noon's while the ground is eighteen times darker, so a body that mirrors the sky
  reads as lit from nowhere. `ROUGHNESS = mix(paint, coat, clearcoat * F(NdotV))` instead: a panel
  seen face-on reflects the sky the way its paint does, broadly and dully, and becomes the coat's
  mirror only as it turns away. It is also what the coat actually reflects, which is the argument
  for it. The brightest pixel on the truck at that hour fell from 0.3028 to 0.2399.
  **The mirror-to-sky ratio was ruled out first**: measured across the dawn it holds at 0.31 to
  0.50 from 5.9 h to noon, so the radiance map is not specially wrong at any hour and the fault was
  in how much of it the paint was told to show.

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

- **A surface that reads the screen behind it must write `ALPHA`, and a constant will not do.**
  Writing `ALPHA` is what puts a surface in the transparent pass, and the transparent pass is where
  the screen texture and the depth of what is behind it exist. The sea without it came back opaque:
  `hint_depth_texture` measured zero water everywhere and `hint_screen_texture` sampled black, so
  it drew as a sheet of its own scattering colour with no bed, no shoreline and nothing under it.
  `water.gdshader` takes its `ALPHA` from a uniform rather than a literal 1.0, because a constant
  is something the compiler can fold away and take the transparent pass with it.

- **A screen texture must not be mipmapped and must be read with `textureLod(..., 0.0)`.** With
  `filter_linear_mipmap` the mip comes from the screen-space derivatives, and on a surface seen at
  a grazing angle those are enormous: the sea picked the smallest mip, which is the average of the
  whole frame, and painted itself one flat colour at every angle and every depth.

- **`EMISSION` is in physical light units, so a screen-texture read cannot go in it.** What comes up
  through water is light that was lit and exposed already, which is exactly what `EMISSION` is for —
  and at a daylight exposure the normalisation is of the order of a thirty-thousandth, so an
  emission of 1.0 renders black. Measured: a sea told to emit pure green came back with no green in
  it. Godot exposes that normalisation to neither a shader nor a script —
  `CameraAttributesPhysical` has no method for it — so there is nothing to divide by, and the
  refracted view sits in `ALBEDO` where the light falling on the surface multiplies it. Outdoors
  that is nearly right, because the same sky lit the sea bed; a shadow across the water is where it
  is wrong.

- **Godot's dielectric reflection does reach the horizon; a sea band against a sky band is not how
  to measure it.** This entry used to record the sea just under the horizon reading 0.296 of the sky
  just over it, with a mirror at 0.93, as an unexplained shortfall of the dielectric response.
  `a_sea_reflects_the_sky_by_fresnel` measures the sea against a mirror *at the same angle* under a
  furnace sky with no haze and finds 0.47 at 82 degrees and 0.77 at 89 against the Fresnel
  equations' 0.43 and 0.90 — the engine's fitted Fresnel, and the sea does nothing to it. What the
  0.296 was measuring is not re-derived; it is superseded. What the gate did find was the shader
  stating `SPECULAR = 0.5`, a 4% reflectance where water has 2%, with `WATER_F0` written unused
  beside it. Handing Fresnel to the engine as `METALLIC` remains the wrong fix: the ramp measures
  right and the sea comes out a flat milky sheet, because a metal has no diffuse term.

- **Published absorption figures are listed by wavelength and shaders are written in RGB.** Pure
  water absorbs about 0.01 per metre at 440 nm, 0.06 at 550 and 0.35 at 650 — shortest first.
  Entered in that order they put the largest coefficient on blue, and every shoreline in the game
  came out with a bright orange band along it, because shallow water was absorbing everything
  except red. Red is the one water takes first.

- **A mirror is not darker than the sky; the zenith is.** A chrome ball under this project's noon
  reads 0.425 of the sky near the top of the same frame, which looks like reflections being
  systematically dim and is not: the ball's top mirrors the zenith and the frame's top is sky near
  the horizon, which is brighter. Compare a reflection against the sky in the direction it actually
  mirrors — for a flat sea, the band just under the horizon against the band just over it, which
  measures 0.93 for a mirror.

- **The sky Godot draws and the radiance map it lights with do not share a scale.** A white ball in
  a white furnace came back at 2.95 times the sky drawn directly behind it, uniformly, at every
  roughness — and that factor is the camera's own exposure normalisation: the same enclosure
  photographed through a camera two and a half stops away read 1.00. So a reflection may never be
  compared against the background in the same frame unless the sky shader has been written to make
  the two agree, which is exactly what this project's own does when it divides by `light_exposure`
  in the cubemap pass and what a plain `ProceduralSkyMaterial` does not do. Read the enclosure off
  a mirror instead: a mirror returns what arrives, by definition.

- **The renderer loses energy at high roughness and grazing angles, and never gains it.** In a
  white furnace, where every surface must return exactly what lights it, a fully rough dielectric
  reads 9.3% under a smooth one at the same angle at its silhouette, and 4.3% under it at the
  middle. That is the single-scatter deficit — one bounce per reflection, a split-sum environment
  BRDF, and the light that would have bounced a second time inside the microsurface unaccounted
  for. It is why a rough surface here is slightly dark at glancing angles, and it is the same
  corner of the model as the sea reading 0.296 of the sky it mirrors at the horizon.
  `a_white_furnace_shows_nothing` bounds it: 12% of loss is allowed and 4% of gain is not, because
  an approximation of a hemisphere integral has somewhere for light to go and nowhere to get it
  from.

- **A white dielectric returns more than it receives, by construction.** Its silhouette reads 8.6%
  over its own middle in a furnace, because the metallic-roughness model takes no Fresnel share out
  of the diffuse term: at grazing the surface reflects nearly everything *and* keeps its full
  diffuse albedo. That is the model as glTF specifies it rather than a fault in Godot, so a
  measurement must compare like angle with like angle, and a metal with a metal.

- **`##` is not a comment in a `.gdshader`, and the shader still compiles.** `#` begins a
  preprocessor directive, so a doc-comment habit carried over from GDScript silently changes what
  the shader does: two `##` lines added above a uniform moved a measured clearcoat retention from
  0.9495 to 0.9797, repeatably, with no error anywhere and no other edit. Shader comments are `//`.

- **Godot 4 has no `specular` property on a material; it is `metallic_specular`.** `specular_mode`
  exists beside it and only switches the lobe off. Assigning `specular` fails at runtime rather
  than at parse time, so it reaches a gate rather than a compiler.

- **A terrain's object materials were never classified at all.** Vehicles have gone through
  `MaterialClass` since it was written; terrain objects never did, so every pane of glass, every
  tyre and every painted sign on every map was drawn at Godot's default roughness of 1.0, which is
  chalk. Found by accident: a check on derived roughness came back with 3883 of 3938 materials
  outside their class's band, because the band being compared against was Godot's default rather
  than a class. They take the class's `metallic` and `roughness` now, and only those — transparency
  and culling here come from the pass's own `scene_blend` and `cull_hardware`, which is authored
  data and beats a guess from a name.

- **A texture's mean brightness must be taken by resizing it, not by striding over it.** Reading
  every eighth pixel of a level crossing's stripes samples the stripes: two strided means of the
  same image at different steps came out 0.11 apart, which is most of the swing a derived roughness
  is allowed to move. `Image.resize` averages every pixel into the result, costs less than walking
  the image in GDScript, and gives the same answer whatever grid it is asked for.

- **A vehicle surface is not always a `StandardMaterial3D` any more**, so do not cast one.
  `MeshAssembler.material_for` returns the layered shader for the classes that need it, and
  `VehiclePaint.albedo_colour`, `.albedo_map` and `.roughness_map` read either kind. The facing
  checks skipped every `ShaderMaterial` on purpose — vegetation and water have no albedo they can
  read — and that skip would have quietly dropped the body panels out of every facing gate the day
  paint stopped being a built-in material.
