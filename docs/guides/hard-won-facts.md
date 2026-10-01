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
