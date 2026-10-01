# Hard-won facts

Audience: anyone changing the solver, the compatibility shim, the terrain, the renderer or the
gates. Every entry here was measured, most of them after a wrong answer, and each one costs an
afternoon to rediscover.

- **Read the file before believing anything about a rig.** The hero truck states its own node
  masses, its own torque curve by name, its own wheel drive flags and its own beam scale. Four
  separate faults this session were the parser ignoring something the file said, not the
  physics being wrong. `game/tools/rig_report.gd` prints what a file actually declares.
- **Axle nodes must be ordered so the first has the smaller z**, which upstream does at spawn
  and files do not. Stated outer-node-first on both sides — as the hero truck does — the axis
  vector points outward on one side of the rig and inward on the other, so the same torque
  drives the left wheels forward and the right wheels backward. It cost 4.70 m of travel with
  3.41 m of it sideways; ordered, the same run does 105 m straight.
- **A directive keyword has to end at a separator.** `set_beam_defaults_scale` begins with
  `set_beam_defaults`, and matched on the prefix it was read as one, with `_scale` as its
  first argument — which parses as a spring of 0 N/m.
- **A lone bare word is not always a section header.** The hero truck's `torquecurve` body is
  the single word `gas`, naming one of upstream's predefined models; `author`, `fileinfo` and
  `guid` are keywords belonging to no section at all. Its `guid` line, read as a `globals`
  row, parsed as a cargo mass of 4.1e147 kg.
- **Winding.** The OGRE reader reverses every triangle and leaves the vertex normals exactly as
  authored. Measured in the file, index order and the authored normals agree on 99–100% of
  triangles, which reads as "do not touch it" — but in file order the vehicle is culled from
  outside and drawn from inside. Something between the loader and the drawn pixel mirrors the
  geometry and has not been isolated; a negative-determinant basis in the pose path is the
  first place to look. Do not negate the normals to "match" the reversal: `body_blocks_sun`
  measures 2.13× with them as authored and 0.73× negated, which is the sun appearing to shine
  through the bodywork.
- **The vehicle renders in rig space.** `VehicleBuilder.build` computes the actor frame and puts
  it on the root, and poses bones in actor-local space, so the two compose back to rig space.
  Wiring the frame through properly makes two wheels render out on open ground; see the comment
  in `vehicle_builder.gd` and `docs/architecture/bridge.md`. Mixing the two spaces is what put
  the interior camera outside the cab.
- **The hero truck's `cab`/`submesh` sections are collision only** — zero `texcoords`, material
  `tracks/trans`, every triangle flagged `c`. ADR 0003's FlexObj path is not what is missing
  here, and the cab roof that looked absent was the lit-through bodywork instead.
- **Directives are not section rows.** `set_node_defaults` and friends carry no section header
  and were being read as data, inventing five phantom nodes and two cinecams — one of them a
  spring value. `TruckParser.DIRECTIVES` exists to stop that.
- **A rig declares several cinecams** and only some are inside the cab. The hero truck's first
  is 0.22 m above its own roof; its second is the driver's eye.
- **Steering wheel rake is 121°, not upstream's −59°.** The mesh's thinnest axis is the column
  and on this wheel it runs along the stalk rather than the face, so flipping the sign trades
  one fault for the other. 121 = 180 − 59: the 180 is this project's prop chain differing from
  upstream's by a handedness, the sign is the stalk. `game/tools/prop_axis_probe.gd` measures it.
- **A surface map is stored row by row, z outer and x inner**, because that is the order the
  solver reads a heightfield in. Stored the other way round it is transposed, and a transposed
  map is not obviously wrong: the right surfaces appear, in the wrong places, and the first
  symptom was the terrain drawing sand where the solver gripped concrete.
- **A gate that measures the wrong quantity passes on the fault it was written for.** Measured
  twice here. A gate on the deleted valley read how deep a lake's water was, which is mostly the
  floor descending under a flat water level, and passed with the basin set to half a metre. And
  the negative control for `terrain_collision_agreement`'s transposition check was first wired to
  the wrong copy of the surface-map build — `TerrainWorld.surface_map()`'s lazy fallback, which
  `populate` never reaches — so the break changed nothing and the gate looked worthless when it
  was not. **A negative control that produces no change is a miswired control until proven
  otherwise.**
- **A place a gate stands on has to be derived, not written down.** This is what the generated
  valley and test park cost when they were removed: every gate holding a coordinate on them had
  no subject left. A coordinate means something on one map and nothing on the next, so a gate
  searches an author's own heightmap for the ground it needs — a slope, a level patch, a drivable
  heading — in a fixed order so the answer is the same on every machine, and reports where it
  went. The same lesson cost 2.5 m of a road apron when a feature's bounds were written down
  beside it rather than derived from it.
- **Importing 4.2 M cells of terrain costs about 4 s, and it is most of the suite's runtime.**
  `world/terrain_cache.gd` is what makes it affordable, and it verifies itself against the
  terrain's own heightmap on load because a cache is otherwise a golden artifact. The cache key
  is the readers plus a salt from the terrain: upstream's shipped package is three terrains over
  one set of files, so keying it on the directory serves one map's heights for another.
- **Process-global state hides in more places than `static var`.** `Harness.rng` was one RNG
  seeded once for the process, and every gate that drew from it advanced it, so the numbers a
  gate was handed depended on how many draws the gates before it had made. `extension_parity`
  measured 5.89e-06 in one order and 1.35e-06 in another. A gate container owns the RNG now and
  seeds it the same every time. The rule this generalises to: anything a gate reads that outlives
  a gate is state, whatever keyword declares it.
- **A `SubViewport` isolates a gate only with `own_world_3d` set.** Without it the viewport draws
  into the parent's `World3D` and the container contains nothing: one gate's `DirectionalLight3D`
  lights the next gate's frame.
- **Orphan count is the exact leak signal; node count is not.** The engine adds nodes of its own
  during a run — overlay and tooltip scaffolding — so a container that leaves a few nodes behind
  has not necessarily leaked. A node with no parent that did not exist before has no innocent
  explanation, so that is the counter with no slack on it.
- **A gate that renders animated geometry has no deterministic frame, and "renderer warm-up" is
  the wrong explanation to reach for.** `ror_terrain_photoset` drifted in its fourth decimal and
  it was written off as shader compilation and probe timing warming across a process. Running
  two passes in *one* session made the drift bigger and monotonic — 0.282191, 0.282288, 0.282456
  — and monotonic is not what warm-up looks like. `surfaces_are_visible` rendered the same
  terrain three times in the same session bit for bit, which said it was not general. Turning the
  vegetation off made it stop. It was `foliage.gdshader` swaying on `TIME`: a captured frame
  depended on the wall clock, and with one gate per process every run started near zero and
  landed in the same part of the sway. The shader takes a `wind_phase` now, a gate fixes it, and
  the drift went from 9.4e-4 to 1.1e-7. **Anything a gate photographs that moves with `TIME` has
  to be given a phase.**
- **A wrong explanation shows up as a tolerance.** The order check was loosened to 1e-3 to admit
  that drift, with the reasoning written down beside it, and the reasoning was wrong — so the
  loosening hid a real bug for two commits. A tolerance widened to fit an unexplained measurement
  is a bug with a comment on it. It is 1e-5 now.
- **"The terrain takes a smaller share of its light from the sky than anything standing on it"
  was never true.** It stood in this project's docs for a long time, measured at 21%, then 13.6%,
  then 111%, then 22.6%, moving with whatever else had changed — and it was a roughness mismatch
  inside `terrain_takes_the_light` itself. Its reference patch used
  `TerrainWorld.COLOUR_MAP_ROUGHNESS`, 0.6, which is *one term* of Terrain3D's roughness
  (`(color_map.a - 0.5) * 2 + normal_rough.a` plus a per-asset modifier) and not the result. The
  per-asset modifier is `RorTerrainSkin.ROUGHNESS`, 0.9. A smoother patch takes more of its light
  from the sky's specular than rougher ground does, so the gate was comparing two different
  materials and calling the difference a property of the ground. **Matched, they agree to 0.0%.**
  A comparison gate is only as good as the sameness of the two things it compares, and "same
  albedo" is not the same as "same material".
- **Godot's sky ambient does not follow the sun within a capture.** `daylight_shadows_are_readable`
  took its shaded sample by swinging the sun 180°, which with a `PhysicalSkyMaterial` drags the
  atmosphere below the horizon and measures night rather than shade. Replacing that with
  `sky_mode = SKY_ONLY` — same sun, same sky, direct light off — gave a **bit-identical** result,
  which is the interesting part: the ambient did not change when the sun moved, though it does
  change with turbidity. The radiance map that feeds `ambient_light_sky_contribution` is not
  regenerated per frame at `Sky.PROCESS_MODE_AUTOMATIC`. The method was wrong in principle and
  right by accident; it is correct by construction now.
- **A physically-proportioned daylight ratio and this project's shadow gates are in direct
  conflict, and it is a design decision rather than a bug.** Calibrating the sky to a measured
  10.7:1 sun-to-sky (against clear daylight's 10:1 to 18:1) cannot simultaneously satisfy
  `shadows_are_not_black`'s floor of 0.085 displayed shadow *and* its ceiling of 4x displayed
  sunlit-to-shadow — except by compressing highlights so hard that the image goes flat, which is
  what exposure 3.4 did. Removing the fill light makes it worse: shadows fall to 0.0221. The
  gate's own reasoning cites print holding about 1:8, so its 4x is stricter than the figure it
  argues from. **Nothing here was changed to resolve it.**
- **Photograph a step wedge, not a grey card.** Six patches a stop apart found two faults in one
  run that a single mid-grey patch could not have shown, because both were *additive* and an
  offset bends a measurement most where the subject is darkest. The brightest patch was 1% high
  and the darkest 9% high — one patch anywhere on that wedge would have read "about right".
- **`use_measurement_environment` was never dark.** It set the ambient colour to black and the
  ambient energy to zero and left `ambient_light_sky_contribution` at 1.0 — and at 1.0 the ambient
  comes from the sky whatever the colour says. It also left **fog** on, which adds a constant to
  every pixel in the frame. Every gate that ever measured something "in the dark" had both. Both
  are off now, along with `reflected_light_source`.
- **With the room actually dark, the lighting path is exact.** A photographed wedge is linear in
  reflectance to **0.00%**, doubling a light is a factor of two to **0.00%**, and a two-light
  ratio measures 6.80:1 against 6.80:1. So nothing is wrong with the renderer's lights or with
  the capture — which places the remaining sun-to-sky puzzle squarely in the **sky ambient**
  path, and nowhere else.
- **Lambert's cosine law will correct your expectation before it corrects the renderer.** The
  lighting-ratio check first compared a photograph against 20000/5000 = 4:1 and the photograph
  said 6.80:1 — a 70% error that was entirely the gate's. The fill arrives at 54 degrees, so
  cos(54) = 0.588 of it lands and 20000 / (5000 x 0.588) is 6.80 exactly. A photographer aims an
  incident meter at the camera for the same reason.
- **A capture can carry light, and it takes one flag.** `SubViewport.use_hdr_2d` makes the
  viewport texture `FORMAT_RGBAH` and linear, so values above white survive: an unshaded quad at
  albedo 4.0 reads 25.312 through it and 1.000 without it. 25.312 is `srgb_to_linear(4.0)`, which
  is also the reminder that `StandardMaterial3D.albedo_color` is sRGB on the way in — to inject a
  known linear value you need a shader uniform straight into `ALBEDO`, not a material colour.
  `Image.save_exr` then writes it. `captures_carry_real_light` calibrates the path end to end:
  0.25, 0.75, 2.0 and 8.0 read back within 0.24%.
- **Calibrating the instrument did not settle the sun-to-sky question, and that is itself the
  finding.** Measured through the HDR capture the ratio is **6.4:1** — the first trustworthy
  figure — but it still moves with exposure: 6.4:1 at ISO 32, 2.7:1 at 64, 19.2:1 at 16, on one
  unchanged scene, with a capture proven linear to 0.24% up to a value of 8. A gain cannot change
  a ratio, so the non-linearity is in the *render*, not the capture. The suspicion is that under
  physical light units the sky's ambient contribution and the direct light do not share an
  exposure normalisation. **Two instruments have now been wrong in a row on this question; the
  lesson is to calibrate before measuring, not after being surprised.**
- **A ratio read off an 8-bit PNG is not a ratio of light, and it cannot be fixed by dividing.**
  `daylight_shadows_are_readable` reads its "scene-referred" samples out of a captured PNG, which
  is 8-bit and display-encoded. Turning on physical light units exposed it: the *same scene* gave
  1.3:1 at ISO 100, 3.4:1 at 25, 12.2:1 at 12 and 38.6:1 at 6. **A gain cannot change a ratio**,
  so the measurement is not linear — the sunlit sample saturates at the top and the shaded one
  quantises toward zero at the bottom, and only a narrow exposure window is valid at all. Undoing
  the sRGB transfer does not rescue it (1.8, 3.6, 9.4, 28.8 across the same sweep). **Every
  sun-to-sky figure this project has recorded came from this measurement** — 3:1, 4:1, 10.7:1 —
  and none of them is a light ratio. Measuring a 10:1 scene needs an HDR capture path; until there
  is one, no number from this gate should be compared against a physical illuminance figure.
- **Physical light units do not make the exposure fall out for free.** With
  `use_physical_light_units`, the sun at 100 klx and `CameraAttributesPhysical` doing the
  exposure, the ISO still ended up being chosen by a *shadow* gate rather than by the sun: above
  ISO 40 La Paz's pale ground bleaches, below 32 the shadow drops under
  `shadows_are_not_black`'s 0.085 floor, and the window between them is half a stop wide. The
  gates' thresholds were calibrated when the scene was brighter than daylight, and they now bound
  the exposure from both sides.
- **A fill light cannot lift a shadow it is itself shadowed by.** Raising `FILL_LUX` from 6 000 to
  20 000 moved the measured shadow from 0.0479 to 0.0578 against a floor of 0.085 — a three-fold
  increase buying a fifth of what was needed, because the fill casts shadows too and the region
  being measured is in both. Exposure is what moves a shadow floor; a fill moves the sides.
- **A config flag can claim a thing the code does not do, and nothing will catch it.**
  `weather_cfg.gd` carried `physical_sky: true` for every daylight preset while `_build_sky`
  built a two-colour `ProceduralSkyMaterial` gradient. No gate could see it: every lighting gate
  was graded against whatever sky was actually being built, so the name being a lie cost nothing
  and was invisible until somebody read both files. A flag named after a technique is worth
  checking against the technique.
- **An atmosphere model is dimmer than a gradient tuned to look right, and that is the point.**
  Switching the clear presets to `PhysicalSkyMaterial` moved sun-to-sky from 3.2:1 to 4.1:1 —
  toward clear daylight's ~14:1 — and darkened the whole frame, so
  `daylight_shadows_are_readable` failed on its own readability floor with exactly the right
  diagnosis: *"the light is there and the grading is burying it."* Exposure is the control for
  that, and it went 0.7 to 1.05 to put the displayed shaded surface back at 0.066 where it had
  been. Fixing it with sky energy instead would have undone the ratio it was meant to improve.
- **A terrain with no traction map grips like gravel, not like the first ground model.** Upstream
  keeps two defaults (`Collisions.cpp:134-135`): `defaultgm` is concrete and is for collision
  meshes, `defaultgroundgm` is gravel and is what the ground uses when landuse is absent or
  cannot answer. Reading the wrong one made Rigs of Rods' own shipped gravel map grip like a road.
- **Upstream's `.otc` keys are almost all optional and their defaults are not zero.**
  `OTCParser::LoadMasterConfig` defaults `PageSize` to 1025, `WorldSizeY` to 50, `WorldSizeX/Z` to
  1024 and `Heightmap.0.0.raw.size` to 1025. A reader that requires them rejects terrains the game
  loads: the shipped map sets four keys and leaves nine to the parser.
- **`Flat=1` means there is no heightmap at all, and the page file still names one.** Upstream
  defines the page at height zero and `TerrainGeometryManager::getHeightAt` returns 0.0 before it
  reads anything, so the filename is never opened — which is why the shipped map names a `.png`
  it does not ship. A reader that opens it fails on the map the game starts with.
- **`Image.create_from_data` takes a `use_mipmaps` flag, and an image's byte array contains its
  mipmap chain.** Passing `false` for an image that has them means "expected 1920000 bytes, got
  2559756", the image is not created, and whatever was going to use it gets nothing. This cost
  more than any other single line in the project: `RorTerrainSkin.rolled` did it, so every ground
  texture rolled to cancel Terrain3D's half-tile offset came out **blank**, and the consequences
  were recorded as four separate findings that were all this one bug:
  - "Terrain3D is drawing the ground from the colour map and the texture assets attached to it
    reach nothing." They reached nothing because they were empty. Darkening an albedo, whitening
    `albedo_color` and taking normal depth to zero each changed the render by 0.0000 — they were
    changing a black texture into a slightly different black texture.
  - "The ground takes far less of its light from the sky than a surface standing on it", measured
    at 13.6%, 36% and 111% on three terrains. Measured against blank ground.
    `terrain_takes_the_light` reads 22.6% and passes on its original threshold now.
  - The M2 ground material was scoped around replacing Terrain3D's shading to fix both. It does
    not need to.
  **Prefer `image.duplicate()` to rebuilding an image from its own bytes**, and if you must
  rebuild one, pass `image.has_mipmaps()`.
- **Three of the four findings above were one bug; the fourth was a correct measurement.** Worth
  separating, because the fourth looks like collateral and is not. La Paz ships `blank_NRM.dds` for
  **all four** of its splat layers — its normal maps really are flat. "Taking the normal map's
  depth to zero changed nothing" was a true statement about a blank normal map. When a batch of
  findings turns out to share a cause, the ones that survive are the ones to check individually.
- **Per-surface roughness does reach Terrain3D's picture**, and the claim that it did not was
  untestable rather than wrong. Terrain3D composes roughness as
  `(color_map.a - 0.5) * 2 + normal_rough.a` plus `_texture_roughness_mod_array[id]`, so the
  per-asset value is a shader input — but `RorTerrainSkin` sets all four of La Paz's assets to the
  same 0.9, so there was no difference to observe even with working textures. Swept across all
  assets it moves the rendered ground 0.0996 luma, mirror to matte.
- **Nothing in the Rigs of Rods terrain format carries roughness.** An `.otc` layer is
  `tile_m, albedo, normal, blendmap, channel, alpha` and that is all. So any per-surface roughness
  is this project's invention, which is exactly what it refuses to multiply over an author's
  imagery elsewhere. A single constant is the defensible choice until a format carries better.
- **Terrain3D turns its checkerboard on when a texture array is empty, and this project switched
  it off two lines later.** `Terrain3DMaterial::_update_texture_arrays` calls
  `set_show_checkered(true)` when `get_texture_count() == 0`; `TerrainWorld._show_surfaces` sets
  it to false unconditionally, with a comment explaining that the checkerboard is a placeholder
  for missing textures. It was not a placeholder, it was the diagnosis, and turning it off hid
  the blank textures for as long as they existed. A debug view a dependency turns on by itself is
  worth reading before switching off.
- **Terrain3D packs its textures into an array when its asset list is initialised, and a change
  to an asset afterwards is invisible until the array is repacked.** `update_texture_list()` is
  the call it makes itself and it is exposed to script. Reassigning a whole new `Terrain3DAssets`
  is *not* equivalent and silently does nothing: `Terrain3D::set_assets` reinitialises only while
  the node is inside a world, and an array that is already packed stays packed.
- **A patch compared with the terrain has to be matched in albedo even when the measurement is a
  ratio.** The ratio cancels diffuse albedo but not specular, which does not scale with it: a
  fixed 0.18 grey moved the patch's own sun response from 2.12 to 1.71 with nothing else changed.
  `terrain_takes_the_light` calibrates the patch against the ground in the frame itself.
- **Upstream gives a shock four times the file's breaking threshold** in force
  (`SetBeamStrength(beam, def.beam_defaults->breaking_threshold * 4.f)`), and a shock's force is
  mostly damping: at the hero truck's 2400 Ns/m against a 4000 N threshold it snaps at 1.7 m/s of
  suspension travel. Two of its dampers were breaking while the rig settled onto its own springs,
  before anything had been driven, and the third went on the next landing — reported in a session
  as recovering the truck breaking a wheel.
- **An unshaded material draws its albedo and ignores emission**, so a lamp built that way is the
  same brightness on and off. And a lens standing proud of the bodywork as a lit quad is a square
  on the front of the truck, which is what a session called an ugly rectangle. Lamps are additive
  sprites with a radial falloff now, which is also what upstream draws: off adds nothing.
- **A QuadMesh faces its own +Z**, and a lamp holder is built with -Z along the lamp's normal, so
  a lens added without a half turn shows its back to the world: culled from outside the vehicle,
  visible from inside it.
- **Soft ground is a separate branch of upstream's contact law and it is most of what makes sand
  sand.** A ground model with a non-zero `solid ground level` has a power-law fluid above it —
  drag, buoyancy, anisotropy — and the solid law only applies below that depth. Without it La
  Paz's desert braked and cornered within a few per cent of its asphalt. With the friction
  numbers reaching the wheels, a rig leaned on at 0.7 g slides 5.41 m on the dirt against 3.88 m
  on the road.
- **Braking distance does not separate two surfaces on this rig**: the brakes run out before the
  tyres do, so both stop in the same distance. Cornering does not either — the outside wheels
  load up enough to grip on both. Leaning on a parked rig with tilted gravity does, and it is the
  same test `surfaces_change_grip` uses for a single node.
- **The sky a session sees and the sky the gates measure are not the same sky, on purpose.** A
  window gets the marched clouds; a gate gets the stated gradient. Swapping the cloud sky under
  the gates took the hero truck from 2.27x brighter lit from the front to 1.02x and stopped the
  tunnel being darker inside than out, because a sky full of bright cloud raises the irradiance
  the whole scene is lit by. That gap — an overcast sky that does not yet light like one — is
  the same gap as the project's 3:1 sun-to-sky balance, and both want M2's HDRI work.
- **Distance haze flattens every contrast measurement.** Fog is on by default for sessions, and
  `GateBase.clear_fog` takes it away for gates that measure light or framing: with it on, a body
  lit from the front and one lit from behind wash to the same number, and distant ground takes
  the colour of the sky and counts as sky.
- **A rig's aerodynamics depend on one section in its file.** Upstream drags a rig that declares
  `fusedrag` as a single flat plate from the fuselage's width, and every other rig node by node
  with a turbulent model. Given the wrong one the hero truck stopped accelerating at 63 km/h in
  fourth gear at full throttle; given its own — a 0.1 m fuselage, which is almost no drag — it
  reaches 288 km/h in top gear. Upstream's own fuselage code also sets the fuselage's back node
  to its front node, which zeroes the airfoil term; the port keeps that.
- **Terrain3D's `uv_scale` is two over the tiling distance, not one over it**, and it samples at
  `world.xz * uv_scale - 0.5`. Measured on La Paz's road, whose texture is a 10.1 m cross-section:
  at 1/10.1 it tiled over 20.2 m, and the half-tile offset put the double yellow line at the kerb.
  Ground textures are rolled half a tile to cancel it — measured 0.35 m from the middle of the
  asphalt, against 5.10 m before.
- **A cab's cluster belongs on the steering wheel, not on the dashboard prop or the eye.** The
  eye is a cinecam and hangs where a camera hangs; the hero truck's dashboard prop is a 0.8 mm
  placeholder because its dashboard is painted into the cab mesh. The wheel is the one thing in
  a cab that is always where the cab is.
- **A steering wheel turns about y after its rake** — upstream's chain is
  `Quaternion(rake, UNIT_X) * Quaternion(steer, UNIT_Y)` — and the mesh agrees: 0.207 m through
  the column against a 0.371 m rim. Composed as a single Euler triple it turns about an axis that
  is not the column, and an Euler *reading* of the result drifts with the rake: 175.71 degrees
  for a turn of 175.
- **Every odef object is pitched -90 degrees about its own x axis**, unconditionally, for every
  object on every terrain (upstream's `TerrainObjectManager::LoadTerrainObject`). Object meshes
  in this library are authored z-up. Without that turn La Paz's 99 roadside poles lie on their
  sides in the ground — 6 m of mesh along z, 2 m along y, nothing above the surface — and the
  terrain looks like an empty desert that loaded correctly.
- **A terrain states its own heightmap scale and it is not a guess.** A height is
  `sample / 65535 * WorldSizeY` and the lattice is `PageSize - 1` cells of
  `WorldSizeX / (PageSize - 1)` metres. The oracle for all of it is the terrain's own
  `StartPosition`: La Paz says a vehicle starts at 7.375 m and the decoded heightmap is 7.375 m
  there. With the rows flipped it is 4.4 m out, with the bytes swapped 33 m.
- **An imported terrain's textures must not be tinted by this project's palette.** Terrain3D
  multiplies a texture's `albedo_color` over the colour map, and drawing La Paz's asphalt
  through this project's idea of asphalt (0.20 grey) rendered its roads pure black beside
  ground that was correct. A loaded terrain's colour map is white and its surfaces are neutral.
- **A Terrain3D control map id with no texture behind it renders pure black.** A loaded terrain
  names surfaces upstream's ground models have never heard of — La Paz adds `dirt` and
  `softsand` — and the texture set has to cover every index the world can write.
- **Ogre's `texture_unit scale` scales the texture, not the coordinates.** A stated 0.04 means
  the texture tiles twenty-five times across what the mesh's UVs cover. La Paz's ground skirt is
  one 20 km quad; without it the horizon is a beige wall.
- **Every gate in the suite can be green while something is visibly broken.** Missing vertex
  normals, tyres buried 0.34 m in the ground, and a door hanging a metre off its hinges all
  passed every check that existed at the time, because each measured nodes and the nodes were
  right. When the user reports something, believe them and go find the number that shows it.
- **A sky's energy is not in the lux a light is stated in.** `DirectionalLight3D.light_intensity_lux`
  takes its value literally under physical light units; a sky's `energy_multiplier` never goes
  through that conversion. Measured against a key light of stated lux in a dark room, one unit of
  uniform sky radiance delivers **98,325.74 lx** to a facing surface — reproducible to ten
  significant digits, invariant to the sky's radiance over a 16x range, to the panorama's
  resolution (16x8 and 256x128 agree exactly) and to the radiance map's size. It sits 1.70% under
  1e5 and that gap is unexplained. So a sky left at `energy_multiplier = 1.0` is worth roughly as
  much illuminance as the noon sun, which is why no amount of turning the sun up or the turbidity
  down ever brought the sun-to-sky balance near clear daylight's figure.
- **Sky ambient *is* exposed like a light.** One stop gains a key light by 2.0000x and a uniform
  sky by 2.0000x, 0.00% apart. The exposure-dependent sun-to-sky ratio that prompted four rounds
  of measurement — 6.4:1 at ISO 32, 2.7:1 at 64, 19.2:1 at 16 — was the old uncalibrated
  instrument, fog and leaked sky ambient, and not the sky path at all.
- **A negative control that does not fire is not a control, even when it is the right idea.**
  Re-enabling fog was the obvious break for a sky-ambient gate, since fog is additive and fog had
  already been caught bending a wedge once. At chart distance it moved the measurement 0.42% and
  left linearity at 0.00%, so it proved nothing and was thrown out rather than counted. Lifting
  the chart shader's black by 0.02 fired at 46.2%.
- **Under physical light units a light has a colour temperature, and no temperature is neutral.**
  `Light3D.light_temperature` defaults to 6500 K and photographs as (1.0, 0.9419, 0.9919) once the
  brightest channel is normalised — a 6% green deficit, constant across a thirty-fold brightness
  range, on top of whatever `light_color` says. Sweeping the temperature moves the cast but never
  through neutral: measured at 5000 K it is (1.0, 0.790, 0.629) and at 9000 K (0.674, 0.741, 1.0),
  and red-equals-blue and green-equals-red cross at different temperatures. The cause is which
  locus the conversion walks: 6500 K on the Planckian locus sits below the daylight locus that
  sRGB's white point is on. So every light in this project carries a slight cast, and a colour
  measurement has to white balance off a known patch rather than assume the light is white.
- **A colour measurement cannot go through a luminance.** A channel swap, a doubled transfer
  function or a tinted tonemapper all leave luminance plausible, so every luma-based gate in this
  suite is blind to them by construction. Measured: swapping red and blue in the chart shader
  costs 113 delta E on the worst patch and 41.5 on average while a luminance reading barely moves.
- **White balancing off a reference patch buys accuracy and costs a whole fault class.** It is the
  only honest way to measure colour under a light that is not neutral, and it makes a tinted light
  undetectable — measured, a green light at (0.8, 1.0, 0.8) leaves the chart gate green at 0.029
  delta E. Three degrees of freedom spent on the white card still leaves fifty-four values and the
  six published grey luminances to predict, so the method is not weak; it is specifically blind.
- **A `Sky` left at its default `process_mode` does not render the same picture twice.** The
  radiance map is approximated across frames, and anything rough enough to take its specular from
  that map inherits the approximation: measured on the hero truck's drop, a band of distant ground
  alternated between 0.6703 and 0.9906 luminance on alternate frames — the far half of the checker
  washing to pure white and back — with the camera bolted down and the truck long since at rest.
  Two discrete values flipping, not noise. `Sky.PROCESS_MODE_QUALITY` fixes it and the band then
  holds to 0.000000. Grazing angles take it worst, which is why it was the distance that flickered.
- **The suite can be 85-for-85 green while the picture visibly flickers.** Every gate measured a
  number out of a single frame, and a flicker lives *between* frames, so nothing in the suite could
  see it. The user saw it first. Frame-to-frame determinism is also what every golden-image gate
  quietly assumes, so it was load-bearing and untested at the same time.
- **Two miswired negative controls in a row, on the same gate.** A determinism gate on a genuinely
  still scene passed with the bug still in the code, because a static scene settles its radiance
  map once and never shows the fault. The second version added a moving box and "failed" — but the
  only pixels that moved were the box's own, so it proved a moving box moves. Both gates looked
  entirely reasonable and both were worth nothing. What reproduces the fault is a real vehicle
  being re-posed every frame, measured on ground the vehicle never touches.
- **Damage to a rig is six beam fields and a per-node count, not one.** A hit changes a beam's
  `rest_length` (the bend), both yield stresses, the recomputed `minmax_stress`, the `strength`
  where upstream softens a beam instead of snapping it, and `broken` — and breaking a beam also
  decrements `active_beams` on both of its nodes, which upstream consults before it will break the
  last beams holding a cab node. `RigBuilder.place` restored node positions, velocities and rest
  lengths and its own documentation called that "undeformed": true of bends, false of breaks. A
  reset truck came back on its wheels still holding every snapped beam and shed its doors and
  wheels again on the next step. Measured: a crash leaves 45 of 1995 beams broken and 500 bent.
  Repair restores a snapshot of the beams as built rather than recomputing them — recomputing
  would be a second implementation of rig building, free to drift from the first.
- **`extension/SConstruct` wrote its library to `../game/bin` while the engine loads `bin/`.** The
  path dated from when the project lived in `game/`, so a rebuild produced a fresh binary
  somewhere nothing reads and the old one stayed loaded — a C++ change that silently does nothing
  is worse than one that fails to compile. Same stale-root trap as `res://` and
  `HarnessCapture.artifact_root`; that is three times now, and the lesson is to check where a
  build artifact actually lands before believing a native change took effect.
