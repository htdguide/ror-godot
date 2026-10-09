# Hard-won facts

Audience: anyone changing the solver, the compatibility shim, the terrain, the renderer or the
gates. Every entry here was measured, most of them after a wrong answer, and each one costs an
afternoon to rediscover.

Light, colour and capture have their own file: `hard-won-facts-light.md`. They were split out when
this one hit the 400-line cap, and they are the area this project has been wrong about most often.

Vehicles and their mods have their own file: `hard-won-facts-mods.md` — how a truck, car, wheel,
mesh or material is read and built. Split out when this one hit the 400-line cap.

- **Winding.** The OGRE reader reverses every triangle and leaves the vertex normals exactly as
  authored. Measured in the file, index order and the authored normals agree on 99–100% of
  triangles, which reads as "do not touch it" — but in file order the vehicle is culled from
  outside and drawn from inside. Something between the loader and the drawn pixel mirrors the
  geometry and has not been isolated; a negative-determinant basis in the pose path is the
  first place to look. Do not negate the normals to "match" the reversal: `body_blocks_sun`
  measures 2.13× with them as authored and 0.73× negated, which is the sun appearing to shine
  through the bodywork.
- **Directives are not section rows.** `set_node_defaults` and friends carry no section header
  and were being read as data, inventing five phantom nodes and two cinecams — one of them a
  spring value. `TruckParser.DIRECTIVES` exists to stop that.
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
- **Volumetric fog remembers the last frame, and the memory belongs to the viewport, not the
  world.** Godot reprojects the fog's froxels from a history buffer, and a gate's container tears
  down the world and keeps the viewport. `DayCycle` turns the fog on for `day < 0.5` — twilight and
  night — so `a_vehicle_photoset_through_the_day` photographed the same vehicle 0.1% differently in
  a second run of the same gate in one session, at 05:30, 18:00 and 21:00 only: at midnight the
  fog is near black and the history invisible, by day there is no fog. Three wrong answers came
  first and each was measured out: a cloud phase (the numbers did not move to ten digits — the
  clouds were not in those frames), more convergence frames (the drift grew), a wait for the sky's
  radiance (the sky is `PROCESS_MODE_QUALITY`). `HarnessCapture.make_frames_independent` switches
  the reprojection off for every gate world, and the two runs then agree to fifteen digits. The
  rule the foliage and the sea taught — a measured frame must not depend on when it was taken —
  has a second half: it must not depend on the frames before it either.
- **Two fogs do not add up to one visibility, and a gate can pass on the one that has not
  arrived yet.** `fog_bank` stated 0.01304 per metre as its exponential fog and also asked for the
  volumetric froxel layer, which is a second medium 96 m deep adding about 0.003 per metre inside
  that reach. The picture faded at 0.0161 over the first 80 m and 0.0149 past it; Koschmieder's
  one `k` cannot describe that, and the stated 300 m was really 240. The gate had passed at 0.8%
  because volumetric fog reprojects from a history that starts empty, and six frames in it was
  mostly not there. Turning the history off for measurements (`make_frames_independent`) made the
  gate read the fog that was actually drawn, which is the only reason it went red. The preset is
  exponential alone now, reading 0.01325 against 0.01304.
- **A band left wide "until the sky can be graded against" has to be narrowed the day it can,
  or it stays a sanity check forever.** `daylight_shadows_are_readable` held the sun-to-sky ratio
  between 1.5 and 40 because Godot's `PhysicalSkyMaterial` could not be calibrated, with a note
  saying the HDRI sky would be the fix. The HDRI skies arrived, were calibrated to 13:1, and the
  band stayed at 1.5 to 40 for two days with the handoff still calling the balance open at 7.2:1.
  It is the published 10 to 18 now; the control is the photograph at the gain it came with, 4.7:1.
- **A wall-clock measurement cannot be held to the order check, and saying so is better than
  loosening it.** `a_full_scene_renders_inside_its_budget` measures a frame time: 10.998 ms in
  order, 11.049 shuffled, 10.960 and 10.982 twice in the same order. That is the machine, not a
  dependence on what ran before, and a 1e-5 bound on it would be asking a computer to be a clock.
  The gate declares `measured_is_wall_clock` and the order check compares its verdict and says it
  did, by name, on every run. The tolerance itself stays at 1e-5 for everything else.
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
- **Soft ground is a separate branch of upstream's contact law and it is most of what makes sand
  sand.** A ground model with a non-zero `solid ground level` has a power-law fluid above it —
  drag, buoyancy, anisotropy — and the solid law only applies below that depth. Without it La
  Paz's desert braked and cornered within a few per cent of its asphalt. With the friction
  numbers reaching the wheels, a rig leaned on at 0.7 g slides 5.41 m on the dirt against 3.88 m
  on the road.
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
- **Terrain3D's `uv_scale` is two over the tiling distance, not one over it**, and it samples at
  `world.xz * uv_scale - 0.5`. Measured on La Paz's road, whose texture is a 10.1 m cross-section:
  at 1/10.1 it tiled over 20.2 m, and the half-tile offset put the double yellow line at the kerb.
  Ground textures are rolled half a tile to cancel it — measured 0.35 m from the middle of the
  asphalt, against 5.10 m before.
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
- **Every gate in the suite can be green while something is visibly broken.** Missing vertex
  normals, tyres buried 0.34 m in the ground, and a door hanging a metre off its hinges all
  passed every check that existed at the time, because each measured nodes and the nodes were
  right. When the user reports something, believe them and go find the number that shows it.
- **A negative control that does not fire is not a control, even when it is the right idea.**
  Re-enabling fog was the obvious break for a sky-ambient gate, since fog is additive and fog had
  already been caught bending a wedge once. At chart distance it moved the measurement 0.42% and
  left linearity at 0.00%, so it proved nothing and was thrown out rather than counted. Lifting
  the chart shader's black by 0.02 fired at 46.2%.
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
- **`extension/SConstruct` wrote its library to `../game/bin` while the engine loads `bin/`.** The
  path dated from when the project lived in `game/`, so a rebuild produced a fresh binary
  somewhere nothing reads and the old one stayed loaded — a C++ change that silently does nothing
  is worse than one that fails to compile. Same stale-root trap as `res://` and
  `HarnessCapture.artifact_root`; that is three times now, and the lesson is to check where a
  build artifact actually lands before believing a native change took effect.
- **`setup_for` used to add a world beside the old one, so a second setup measured the first
  scene.** Nothing errored. Two completely different weather presets produced byte-identical
  captures — peak, histogram bins and sampled mean agreeing to six decimals — because the viewport
  held two environments, two suns and two cameras, and the camera that entered first stays
  current. `vehicle_renders` had been writing a `vehicle_rear` artifact that was the front view
  for as long as it existed. The wrong answer was stable, repeatable and order-independent, so the
  determinism and order-independence checks could not see it: those prove a measurement is
  consistent, never that it is of the right thing.
- **A structural check that matches on a node's name is not a structural check.** Godot renames a
  node whose name is taken, so the leaked second `BlockoutWorld` arrived as `@Node3D@2` and a
  check looking for the name counted one world and passed with the bug deliberately restored.
  Identify a node by what it contains — here, its `WorldEnvironment` — not by what it is called.
- **`global_basis` on a node outside the scene tree reports nothing useful.** A gate built two
  worlds detached, aimed their lights and compared directions: both read (0, 0, -1) and the
  comparison passed with the fault deliberately in place. The aiming had worked — once the node is
  in the tree the direction is correct — it is the *reading* that is meaningless detached. Compare
  transforms on nodes that are in the tree, or compare local ones.
- **A gate that compares two code paths cannot see a fault both paths share.** `a_weather_switch_is
  _a_weather` builds a world two ways and requires them to match, which catches the two drifting
  apart and nothing else: deleting a line from the function they both call breaks them identically
  and they still compare equal. Verified rather than assumed. Guarding a seam is not the same as
  checking a property is applied at all.
- **Two presets that differ in the ways you are not measuring make a comparison vacuous.** The
  same gate first switched `golden_dusk` to `noon_clear`, which share every environment field it
  compared, so half the gate passed regardless. Switching from `spike_black` — no atmosphere at
  all against a physical sky — is what made the environment half able to fail.
- **Instancing La Paz's scenery won nothing, and the measurement is the point.** Grouping placed
  objects into `MultiMesh` batches took 101 nodes to 34 and left peak draw calls at 116 either way
  (15.98 ms against 16.11). A 4 km map with a hundred objects was never spending its frame on
  them: a node census of that scene is 34 object batches, one Terrain3D, two meshes and two
  lights, so the terrain dominates. The change is worth keeping because batch count grows with
  distinct meshes times occupied tiles rather than with placements, which is what a ten-thousand
  object map needs — but it is a scalability change and calling it a speedup would be false.
- **The gate's terrain scene and the session's are not the same scene.** `ror_terrain_photoset`
  renders La Paz with no vegetation and no vehicle and reports 116 draw calls; the window, with
  both, reported 135 to 202. Any performance claim has to name which of the two it was measured
  in, and a budget met in the first says nothing about the second.
- **The order check was comparing two gates against themselves.** It paired result lines by name,
  taking the first for pass one and the second for pass two — but a gate may run gates, and
  `the_console_reports_a_run_as_it_happens` runs `gate_metadata` and `static_state` while
  `console_fronts_agree` asks three times for a gate that does not exist. Measured: four result
  lines each for those two names and six for the phantom, so both of pass one's lines were paired
  against each other and pass two was discarded. Two real gates were not order-checked at all and
  a name that never ran at the top level was. Nested results now say so and are skipped; the check
  compares 90 names where it used to compare 91, and reports any name that still appears more than
  twice rather than silently keeping the first two.
- **Reducing evidence to a verdict before saving it makes a failure unactionable.** The order check
  turns ~190 result lines into one line and kept none of them, so an intermittent "ran in only one
  of the two passes" could not be investigated after the fact. It now writes the whole session to
  `artifacts/order-check/session.txt` every run.
- **A leak check with slack hides a leak until something else lands on top of it.** Every nested
  gate run built its own full-window `TextureRect` and left it in the tree — three nodes, under a
  slack of eight, invisible for as long as it existed. Adding two more nodes per run took it to
  nine and the container leak check caught the whole thing at once.
- **`generate_mipmaps` on a block-compressed image fails, and the failure is silent to the
  player.** Godot refuses with "Cannot generate mipmaps from compressed image formats" and the
  material ends up without its texture. `RorTerrainSkin` has guarded this since it was written;
  `MeshAssembler` and `FlareBuilder` never did, so the Mazda 626 — a `.car` whose textures are all
  DXT — arrived with no bodywork while its seats and dash, which are not compressed, looked fine.
  One guarded path and one unguarded path for the same operation is the shape of this bug, and it
  is the third time in this project: the traction map was the same.
- **A screenshot key that counts from zero destroys the evidence it was pressed to capture.**
  `play-0.png` was overwritten by every new session, so three shots of a reported fault came back
  as one and two stale ones from hours earlier. Named by the clock now.
- **`global_transform` on a detached node lies, and it lied twice in one session.** First the
  flexbody direction comparison, then a "uniform offset" of every drawn part from the node box —
  reported, chased, and non-existent. Measured in the tree, the hero truck's worst part sits
  2.18 m from the centre of its own node box, which is half a 4.5 m car: a bumper is at the end.
  Compare transforms in the tree, and pick a reference that means something.
- **Counting is a real oracle when the source states the count.** Upstream computes its spawn
  budget before allocating — `rays * 2` nodes and `rays * 8` beams for a mesh wheel against
  `rays * 4` and `rays * 20` for a flexbody one — so a gate can check the shape of a rig against
  somebody else's arithmetic rather than against this project's opinion. What a beam is worth is
  a separate question; how many there are is not.
- **Every texture in a Terrain3D array has to be the same size, and a terrain's layers routinely
  are not.** La Paz ships four 512-square layers and renders correctly; Russia ships 640s beside
  512s and Starling Island a 2048 beside a 512, and both rendered as flat white ground. The array
  is rejected whole rather than dropping the odd one out, so *no* layer gets a texture — which is
  why the symptom is a uniformly white terrain and not one wrong-looking surface. Ogre has no such
  rule, so the mods are correct and the constraint belongs to this renderer. Every layer is
  brought to the largest size any of them ships.
- **A `.tobj` line is not always an object.** The format carries vehicle spawns (`truck`,
  `truck2`, `load`, `boat`) and zones (`spawnZone_...`) alongside object placements, and reading
  them all as objects counts things that were never meant to be drawn: 13 of Russia's 38
  "placements" and 63 of Starling Island's 1502. Harmless to the picture, and it makes every
  count of what a terrain holds wrong.
- **Blender's Ogre exporter names a material after its own texture.**
  `Material.005/TEXFACE/asphaltshingles.dds` — no `.material` script declares it, because the name
  *is* the declaration. Starling Island ships meshes using those and they drew untextured beside
  houses that were fine.
- **What is left untextured on a loaded terrain is mostly content that is not installed.** After
  the TEXFACE names resolve, Starling Island still has 48 bare object surfaces, and they ask for
  `Material`, `Material.001`, `Material.004`, `default` and `tracks/master` — names declared in no
  file in this checkout. `tracks/master` is Rigs of Rods base content, the same gap as the
  `seat.mesh` several of its vehicles want. Not a loader fault, and worth knowing before anybody
  goes looking for one.

- **`builds_on` is a claim that one gate covers another, and it quietly retires the one it
  names.** The graph schedules the suite, so an edge marks its target implied and stops running
  it. Fourteen gates were added in one day with an edge apiece recording only which gate came
  first — "this is about roads, that is about objects" — and the implied share of the suite went
  past the 40% `gate_chain` allows. Every one of those edges was false in the sense the graph uses:
  a gate that drops a rig onto one box does not cover a gate that counts every box on the map.
  Removing them took the suite from 43 implied to 35, and the fourteen are roots now. The bound is
  the only thing that noticed; the edges themselves looked reasonable in every individual review.

- **A suite that stops early used to report that it passed.** `tools/gate.sh` counts the result
  lines the engine hands it, and a gate that never runs emits none — so a run cut short printed
  "110 gates run in 1 window; all passed" for a suite of 124, with fourteen gates simply absent
  and nothing to say so. The engine now states what it planned (`HARNESS_SUITE_PLAN`) and what it
  accounted for (`HARNESS_SUITE_DONE`), and the front end fails when the tally does not match.
- **What cut it short was the frame backstop, not a crash.** `--quit-after` is a hard stop in
  frames so a hung gate cannot block the suite, and it was 3600. Two photoset gates — a day an
  hour at a time and a vehicle from four sides at nine of those hours — added about six hundred
  captured frames, the engine reached the limit mid-run and quit cleanly, and the truncated run
  read as green. The limit is 60000 now, and the tally is what notices if it is ever reached.

- **A solver on its own thread is safe by making every entry point wait, not by making the
  caller careful.** `RorSolver.step_async` posts a frame's substeps to the solver's `std::thread`;
  `sync()` is the first statement of every other method, so a caller that asks for positions
  while a step runs gets the stepped ones and merely loses the overlap. The alternative — a
  contract that nothing touches the solver between post and wait — was broken on the first day by
  a gate that set the throttle right after `drive.step()`. `PlayDrive` keeps the overlap by taking
  a snapshot of everything it draws or shows before it posts, and drawing from that.
- **The gate that holds the thread could not see a missing guard until it read the solver
  itself.** Reading positions after `PlayDrive.step` returns passed with the guard removed from
  `get_positions`, three runs out of three: the frame's own deform and submit (0.8 ms) outlast
  the step (0.47 ms), so the read always landed after it. The check that bites posts a step to a
  bare solver and reads it in the same breath; torn at frame 0 without the guard.
- **`git checkout <file>` on a file with uncommitted work is an undo of the work.** Said here
  because it cost a rebuild: a control that edited one line of `ror_solver.cpp` was "restored"
  that way and took the day's guards with it. Restore a control from a copy of the working file.

- **Drawing last frame's physics is one frame of lag, and under varying frame times it is a
  stutter.** The solver thread's first form was upstream's model — post this frame's step, draw
  the last completed one — and with vsync off the window runs 9 to 13 ms, so the lag varied
  frame to frame; every vehicle judders and no gate can tell, because gates hold positions and
  not when they are drawn. Post first, pose last, same frame; the overlap is whatever the session
  does in between, and at 0.5 ms a step that was never the point.
- **A `Range` set from a script does not emit `value_changed` in this build**, in a headless tree
  or in one with a window, for `HSlider`, `SpinBox` and `ProgressBar` alike; a drag does. A gate
  that wants to prove a slider is wired calls the handler the signal holds
  (`value_changed.get_connections()`), which is the handler a drag would call.
- **A panel that is not refreshed from the state it edits teaches nobody anything.** Picking a
  preset changed the world and left every slider behind; the rows are now built from one table of
  every key the renderer reads and refreshed from `PlayWeather.state()` on every preset, hour and
  open, and the gate reads the renderer's source for the key set so the table cannot grade itself.

- **A map change has to remove what every builder adds, and the list goes stale the day a
  builder is added.** The session's removal list named objects, roads and trees; the sea came
  later and stayed up through every map change. The list is one constant beside the builders
  now and a gate reads the builders' source for their root names. And the weather goes back on
  *after* the new map is built: the backdrop ring is unlit and takes the hour's dimming at
  grade time, so a map built under a night preset came in at full daylight brightness.
- **`tools/build_terrain3d.sh` installed into `game/addons/`, a folder nothing loads, since the
  PLAN 0.7 tree mirror moved `addons/` to the root.** Dev never noticed because its addon was
  built before the move and never rebuilt; the production checkout, built fresh, had Terrain3D
  compiled and absent. The same stale-root trap `extension/SConstruct` had, and the reason a
  fresh checkout is the only test of a build script.

