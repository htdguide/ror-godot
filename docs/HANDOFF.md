# Handoff prompt

Audience: a contributor or agent picking this project up in a fresh session.

Copy everything below the line into a fresh session.

---

Continue work on **an alternative Rigs of Rods client**, built on Godot 4.x, in
`/Users/htdguide/ror-godot`. Read `docs/PLAN.md` first — it is the approved plan and it is
authoritative. It was re-scoped on 2026-09-30 from a renderer rewrite to a client: §0.5, §0.7–§0.10
and §1's ordering are the new parts and the decisions table records what was superseded. Then
`docs/architecture/bridge.md` and `docs/decisions/`.

**State on 2026-10-09 evening.** D0 (§0.8) is done. **M1's acceptance list is complete** (the
solver thread was its last item) after a week's mod-library sweep that pulled C2's format
coverage forward: 69 library vehicles and 734 archive actors load. **M2 is in progress** and had
its first human look-sweep that day: verdict "all of it looks great", four findings closed (PLAN
§1, M2). **Two builds exist**: this dev checkout, and a production checkout at
`../ror-godot-prod` (branch `prod`, `tools/prod.sh`) that bundles no content and receives work
only by `tools/prod.sh merge` on the user's word — see README. The last day's work, in order:
the solver thread, the sweep's fixes, the production build, a loading screen and a map change
that resets the weather. Trust the commit log over this file for what was touched last.
`tools/gate.sh --gate a,b,c` is sugar for `gate run a b c`; `--cmd "<line>"` runs any console
command from a shell.

**Two sections were decided on 2026-10-01 and nothing in them is built.** §0.10: client-
authoritative replication on this project's own wire at 64 players; RoRnet compatibility retired.
§0.12: the scale design (per-actor frames, islands, sleeping, a causality bound from a 1000 km/h
v_max); its first prerequisite, a hard node-velocity clamp, does not exist. Read §0.12's
order-of-work first — step 2 is two cheap measurements that decide whether any of it is urgent.

**The console.** `tools/play.sh` and `--console` open it; ` or F1 drops it down over whatever is
running, without pausing it. `help` lists the twelve commands, Tab completes and cycles, Up
recalls across runs, `alias` names a line, `bind` ties a key to one, `condump` writes the
transcript to a file. `gate run <name...>` runs gates here, in this window, each in its own
container, and reports each one as it finishes rather than summarising at the end.

**The agent's channel is the same table.** Write a file into `artifacts/console/in/<seq>.cmd`,
one command per line, and read one JSONL line per command out of `artifacts/console/out.jsonl`;
`artifacts/console/state.json` says what is loaded. A whole investigation is one write and one
read. Anything large is written to a file and the line carries the path — `gate run` over three
gates is one line for the agent and three for the person watching. `console_fronts_agree` and
`the_console_reports_a_run_as_it_happens` hold both halves of that.

**One window, all day.** `tools/dev.sh` opens a session and leaves it open; `tools/send.sh "<any
console command>"` runs in it from another shell, and so does the console in the window itself.
`gate run rig_steers` in an open session is under a second. The whole suite is `gate all` — one
window; `tools/gate.sh --all` does the same in one launch (`harness/gate_suite.gd`).

`tools/gate.sh --order-check` runs every gate twice **in one session**, once in the graph's order
and once in a seeded shuffle, comparing verdicts and measured values. Worst drift across the
suite is 4.4e-8; the one frame-time gate declares `measured_is_wall_clock` and is compared by
verdict, by name, on every run. Use `tools/gate.sh --all --every` for a number that goes in a
commit message: it starts fresh, which a session kept open all day does not, and it runs the gates
`--all` only implies — which is how a stale call in `beams_deform_and_break` sat unrun for a day.
The order after it is: M2, M2b, C1 GUI+audio, C2 format coverage+AngelScript, M3–M8, C3
airplanes+boats, C4 repository, C5 multiplayer. Local milestones first; the two networked ones
last, deliberately. The UI's design is settled in §0.11.

## Where things stand

`./tools/gate.sh --all` is green, and so are `--all --every` and `--order-check`. Run it before you
start so you know that is still true. It walks the gate graph — a gate may declare the gates its own claim
contains, so a passing gate reports those as `IMPLIED` rather than running them, and a failing one
is chased downward until the lowest failing gate names the level the fault is at. `--all --every`
ignores the graph and runs everything, which is what a release run uses; `tools/gate.sh --why
<gate>` asks the "is it this, or something under it?" question directly. See
`docs/guides/harness.md`.

**Every world is a Rigs of Rods terrain now.** This project used to generate two of its own — a
2 km valley called Valley One, and a flat test park with a dev grid — and both are removed, along
with their gates, their layout files, their water, their forest and their tunnel. PLAN §0.5 records
why in full: a world this project generates is a world whose gates are it agreeing with itself, and
the features those gates drove were placed by the same code that measured them, so a fault in the
compatibility readers could not reach any of them.

**A fresh clone has a world.** `vendor/rigs-of-rods/content` is a pinned GPL submodule holding the
map Rigs of Rods itself opens with: `simple2-terrain` (`simple2` gravel, `simple2_a` asphalt,
`simple2_w` flooded), 1024 m, `Flat=1`. It is what `tools/play.sh --truck` opens with no
arguments; `a_shipped_map_drives_from_a_fresh_clone` holds it. **That is the dev build.** The production build
(`tools/prod.sh`, branch `prod`, `../ror-godot-prod`) bundles nothing and reads `mods/` and
`maps/`; see README and PLAN §0.5.

**It drives.** `tools/play.sh --truck` opens a window and hands over the controls: throttle, brakes,
steering, gears, ignition, lights, respawn, chase camera and a HUD. The solver has the force sources
a driven rig needs, each a port of upstream's own law and each in its own file: ground contact with
static and Stribeck friction (`ror_ground`), wheel torque and braking (`ror_wheels`), engine,
gearbox and clutch (`ror_drivetrain`), steering through hydro rest length (`ror_steering`), per-node
air drag, travel bounds for shocks, ropes and support beams, and a heightfield so it stands on
terrain rather than a plane.

**The 2 kHz gap is closed.** The rig settles at upstream's own rate and diverges at 1.5 kHz;
`game/tools/stability_probe.gd` measures it by sweeping. Node masses did most of it (10 kHz to
3 kHz) and `set_beam_defaults_scale` the rest.

**Rigs of Rods terrains load, and any of them can be opened.** `tools/import_terrain.sh <zip>` puts
a terrain in the library under `assets/terrains/`, `--list` says what is there, and `tools/play.sh
--truck --map <name>` drives it. A terrain is a `.terrn2`, not a directory, because one directory is
often several terrains. La Paz is the one with relief and imagery that this was built against: its
heightmap, traction map, ground models, splat textures, 101 objects and two vegetation layers all
come from the files its author shipped.

**Grip is a property of the ground.** All nine of upstream's ground models are implemented and
checked against its own `ground_models.cfg`, the terrain lays them down per its own traction map,
and a terrain with no traction map is gravel — upstream's `defaultgroundgm`, not the first model in
the set.

**Beams bend and break.** Upstream's plasticity is ported: past its yield a beam's *rest length*
moves, so the shape it returns to is the shape it was bent into. Driven into a wall at 32 m/s the
hero truck bends 276 beams, worst by 204 mm, and breaks 51 of 1,995. At 2.4 m/s it bends none.

**The suspension travels**, 90 to 99 mm per wheel, which is what a lifted truck does.

Also working: OGRE `.mesh` reading, DDS textures, PBR materials from `managedmaterials`, flexbodies
skinned to solver nodes, rigid props, generated wheel tread that spins, flares as real lamps drawn
with the game's own flare artwork — and, where a vehicle declares `materialflarebindings`, its own
glass switched to the lit frame its author drew — a reflection probe per actor, a terrain's own
objects as solid columns,
a terrain's own vegetation in a ring that follows the driver, and recovery from a roll.

Sessions open at golden dusk unless `--weather` says otherwise (they opened at noon until
2026-10-09: the play path never asked `_default_weather`). A map change shows a loading screen
(`PlayLoading`, picture from `tools/loading_shot.sh`), removes all of the old map (`PlayMap`,
held by `a_map_change_leaves_nothing_of_the_old_map`) and puts the opening weather back over the
new one. `Esc` opens the settings panel — weather, gravity, sun,
shadows, sky brightness, exposure, cloud cover and density, wind, view distance, fog, grass
distance, lamps — with Resume and Quit in it. Controls: `G` drive, `B` reverse, `H` neutral, `I`
ignition, `N` or `L` lights, `R` recover upright, Backspace respawn, `Z`/`C`/`X` indicators,
`F5`/`F6`/`F7` chase, free and driver's seat. `K` is the main beam: a vehicle with no `h` lamps
of its own — which is most of them — puts its low beams onto the main-beam pattern instead, the
way a two-filament bulb does. `F2` cycles the weather, and `night_moon` is one of them. The settings panel's **Time of day**
slider runs the whole 24 hours instead — `DayCycle` moves the sun along its arc, hands the night
to the moon, brings the stars up through the twilight, and re-meters the camera for the light it
has just stated.

## The suite is green

156 gates. On 2026-10-09 all three forms of run pass: `--all --every` (156) and `--order-check`
(153 twice in one session, identical verdicts, worst drift 2.2e-7; two wall-clock gates compared
by verdict). Run all three before trusting a change to the solver's API or to anything that
renders: the order check caught a day-old gate measuring a wall-clock share undeclared.

**The mod-library sweep, 2026-10-04 to 2026-10-08.** Twelve downloaded packs and the shipped
Agora and DAF make a library of 69 vehicles, and nearly every loader convention calibrated on the
hero truck was wrong on a second car: all five wheel sections, `shocks2`/`shocks3` layouts,
`globals` masses, bare-word directives, the yield floors, prop rotation order, flexbody materials
per submesh, slidenodes, triangle collision for shipped hulls. The last of it was **wheels folding
under power** — 19 of 66 driveable vehicles — and the cause was the rigidity beams every wheel row
names and the loader never read (plus negative node numbers, which upstream takes the absolute
value of); see `hard-won-facts-mods.md`. `a_driven_wheel_stays_on_its_axle` holds it over every
braced vehicle. `harness/dev/drive_stance.gd` is the census and `fold_trace.gd` the timeline.

**Three gates were found red or wrong at the end of it, and each taught something written down:**

- `a_terrains_own_scenery_is_solid` asked the hero to lose 80% of whatever speed 30 m of full
  throttle came to, aimed by drift. It passed while the misread yield floors welded the hero solid,
  and failed once a 0.17 m pole could arrive between two node rows and meet nothing, or arrive at
  72 km/h and tear through 17 beams. Rewritten, not widened: it steers onto a dense node row and
  holds 25 km/h, where the truck stops with 1% of its speed. `hard-won-facts-terrain.md`.
- `beams_deform_and_break` called `set_beam_limits` with four arguments a day after it took five,
  and `--all` reported it `IMPLIED` the whole time. A true graph edge does not run a gate.
- `a_vehicle_photoset_through_the_day` drifted 0.1% between two runs in one session: volumetric
  fog's temporal history belongs to the viewport and outlives a gate's container.
  `HarnessCapture.make_frames_independent` switches it off for gate worlds. `hard-won-facts.md`,
  beside the earlier order-check entries, with the frame-time gate's `measured_is_wall_clock`.

Earlier, `terrain_takes_the_light` was red at 111% against 30%, and one wrong `use_mipmaps` flag was
all of it (`hard-won-facts.md`, `Image.create_from_data`). It passes at 22.6% on its own threshold.

## What to do next

**1. M2, the renderer milestone.** Its scope is in PLAN §1. The `WorldEnvironment` is built in
code, the captured skies are in and calibrated against published daylight, and the vehicle
`.gdshader` is written: `vehicle_paint.gdshader` layers a clear coat the way
`KHR_materials_clearcoat` states and adds the sheen Godot has no property for, held by
`a_clear_coat_keeps_the_paint_under_it` and `a_cloth_lobe_lights_the_silhouette`. The water's sky
reflection is held by `a_sea_reflects_the_sky_by_fresnel` — the sea against a mirror at six angles
under a furnace sky, to the Fresnel equations for n = 1.333; it found `SPECULAR = 0.5`, twice
water's reflectance, on day one. What is left of the milestone is a person's: the look of the haze
and the fog, and the 7.2:1 sun-to-sky balance below. `dawn_mist` and `fog_bank` are in, stated as
visibilities — two kilometres and three hundred metres — and held by Koschmieder's law to within
1.6% of what the frame does, now that the fog bank is one fog rather than two (see
`hard-won-facts.md`: a volumetric layer on top of it was a second medium, and the gate had passed on
its unconverged history); how they *look* is a sweep for a person, and the blockout stage is not
the place to do it, because its floor is unshaded and Godot does not fog an unshaded surface.
**The first look-sweep happened on 2026-10-09** — verdict "all of it looks great"; its four findings
(a facade mirroring the dawn sun, a stutter from the solver thread's one-frame lag, a panel that
did not show the preset it was on, a view distance that no longer clips) are closed and recorded
under M2 in PLAN; the panel now has a row for every key a weather states. The
legacy materials now read what their authors wrote — 88 state a specular exponent and every one is
built from it — and guess only where nothing is written, bounded to a tenth of a roughness. The perf acceptance item is met: La Paz with its
objects, its sea and the hero truck draws in 10.67 ms at 1920x1080 across 169 draw calls
(`a_full_scene_renders_inside_its_budget`). The BRDF and the image-based path have an outside oracle,
`a_white_furnace_shows_nothing`: a white ball in a white enclosure, one correct answer. It passes,
and measured that the renderer loses up to 9.3% at full roughness and grazing incidence and gains
nothing anywhere, and that Godot's drawn sky is not on the scale of the radiance map it lights with.

**What the vehicle shader does not do**, and it is the next thing anyone looking at paint will
notice: the coat's reflection of the sky is Godot's image-based lighting at the coat's roughness
rather than a lobe of its own, because a second radiance lookup is not something a shader can ask
Godot for and a second pass over the same geometry drew nothing at all. See the entry in
`docs/guides/hard-won-facts-materials.md` — that file is where the shading conventions that cost
time now live.

**What M2 no longer has to do:** write a ground material at all. Terrain3D's own shader is
metallic-roughness, and with the blank-texture bug fixed it draws the author's albedo and normal
maps and takes per-surface roughness as a real shader input.
`the_ground_draws_its_own_textures` holds both halves — darkening one splat layer to a third moves
the ground 0.2384 luma, and sweeping roughness mirror-to-matte moves it 0.0996. Nothing in the
Rigs of Rods `.otc` format carries roughness, so a single constant is the honest choice rather
than a number this project invents. `res://shaders/terrain3d_override.gdshader` is no longer a
prerequisite for anything.

**Not worth re-chasing:** La Paz ships `blank_NRM.dds` for all four layers, so its normal maps
really are flat. "Normal depth to zero changed nothing" was true.

**The sun-to-sky balance is 13:1 on both skies and two gates hold it.** Godot exposes a sky's
light twice and a lamp's once (`the_sky_does_not_follow_the_camera`, `hard-won-facts-light.md`),
so the balance used to be a property of the film — 19.2:1 at ISO 16, 1.6:1 at 128. Fixed in
`sky_clouds.gdshader`, and then calibrated: the daylight presets are photographs whose gain is set
against published clear-sky daylight (about 95 klx of sun on a surface facing it, 8 klx of
skylight, 13:1), and the day cycle's own noon is brought to the same figure. Today
`daylight_shadows_are_readable` reads 13.1:1 and the other gate 13.0:1 modelled, 13.2:1 captured;
the shadow gate's band is the published 10:1 to 18:1 now, where it was a 1.5-to-40 sanity range
waiting for a sky it could grade against. The uncalibrated photograph reads 4.7:1 and fails it.
The "7.2:1 still open" this file carried was written before the photographs arrived.

**2. What the user asks for next is the thread.** The look-sweep's leftovers are theirs (haze and
fog with the new panel rows, the money-shot sheet); M2 closes only on their word. Open code
items from the day: the sweep's human findings (5 below); the `loading_shot` gate's own picture
is flat and overexposed where the hand-taken one is not, which says the gate's framing (road
point nearest the spawn, sun 50° round) is not yet a photograph. The money shots:
`tools/money_shots.sh` runs the `money_shots` gate and tiles its
eight frames into `artifacts/money-shots-sheet.png`, archived per commit by `tools/history.sh`.
Every frame is derived from the terrain (`harness/money_shot_frames.gd`) and the report says which
feature placed each camera. La Paz is the default; `--terrain-dir starling-port` has road points
and a water line. Starling's `object` frame is a wall (its nearest object is a building) and its
road frame has a lamp post in the middle; both are honest and both are a person's to judge.

**3. M1's acceptance items all hold in the suite.** 2: `a_frame_reports_its_parts` (solver,
wait, deform, submit per row) and `the_solver_steps_on_its_own_thread` (threaded run bit-equal to
a synchronous one, posed positions this frame's). 4: `the_solver_is_deterministic`. 5:
`tools/fetch_corpus.sh` + `mod_corpus`, 734 actors of 205 archive resources. 1, 3, 6, 7, 8 pass.
What M1 still owes is human: 5 below.

**4. What a loaded terrain does not have yet**, each named rather than forgotten:

- ~~**Water.**~~ Built: `RorWater` reads `Water` and `WaterLine`, held by
  `a_terrain_has_the_water_its_file_declares`; it reflects the sky by Fresnel now. The ripples tile.
- ~~**Procedural roads.**~~ Built: `.tobj` road points swept into decks, shoulders and bridges;
  three `a_road_*` / `a_swept_road_*` gates hold them.
- **Hand-placed collision meshes.** A `beginmesh` hull is collided with as triangles when it is at
  least 0.25 m across its second-smallest dimension, and as derived columns when thinner — a 0.17 m
  pole tunnels as triangles under upstream's own 0.1 m slab (`ror_object_collision.gd`, `baff012`).
  Objects with no hull are solid by columns: a 40 m power line is two poles rather than a wall, and
  objects scaled to cover the map are left alone. **A pole still passes between a rig's node rows**;
  that is the node model, upstream's as much as ours, and the scenery gate aims round it.
- **Sky.** The terrn2 names a core-resources cube map no terrain ships; the scene keeps its own sky.
- **Vegetation colour maps and sway.** Read, unused: plants still and untinted.
- **The last sample row and column.** Terrain3D's regions tile on a power of two, so a 2049 sample
  page is imported as 2048 cells and La Paz is 2 m short of its stated 4000 m.
- **The traction map is nearest-sampled** at 3.9 m per pixel on La Paz, where upstream filters it
  bilinearly; surface edges are a pixel blocky.
- **The `grid` special object.** Upstream stamps `grid.odef` 100 times in a 10x10 at 50 m spacing
  (`TerrainObjectManager.cpp:602`); `simple2.tobj` asks for it and no `grid.odef` ships in the
  submodule, so the shipped map draws no objects. Upstream logs the same miss.

**5. What the human sessions found and nobody has closed.**

- **The tyres ring.** The worst tread node was 1.646 m/s at 248 Hz; using upstream's approximate
  maths took it to 0.492 m/s at 2 kHz, and the worst body node from 0.156 to 0.066 m/s. Its
  frequency matches the rim hoop beams: 3.4 MN/m on a 2.03 kg node is 206 Hz with a damping ratio
  of 0.7%. Note the tension with the 2 kHz result: the rig is *stable* at 2 kHz and not *quiet*
  there. Do not fix this by raising the rate without saying so.
  - The SHOCK1 bounds on the tyre spokes (0.66 contraction, 0.15 extension for `meshwheels2`) are
    in since `c827e40`; they did not change the ringing and were never claimed to.
- **It rolls over more easily than the numbers say it should.** The centre of mass is 0.762 m above
  the contact patch over a 1.80 m track, a 1.18 g static rollover threshold, better than a real
  lifted S10. Every surface being `concrete` was the suspected cause and that is fixed, so this
  wants re-measuring on La Paz's sand and dirt before anything else is changed.

**6. Fidelity gaps that are named rather than forgotten.**

- The hero truck declares a `fusedrag` section. Upstream gives such a rig a single fuselage drag
  vector instead of the per-node drag it currently gets.
- `contacters` (79 rows) is unparsed, so every node collides with the ground rather than the ones
  the file nominates.
- Differentials are not modelled. The hero rig's are all split, and a split differential chain
  reduces to the division `ror_wheels` already does, so this is invisible on this rig and wrong on
  one with locked or open diffs.
- `commands2` beams hold the doors but are not key-driven, so the doors do not open. They are also
  built as plain beams where upstream builds them as hydros with their own rate and travel; the
  fold hunt flagged this twice and ruled it out as the cause, and it is still a divergence.
- Traction control and ABS are not implemented; neither is declared by the hero rig.
- A vehicle that declares no `materialflarebindings` has no lit lamp glass, which is upstream's
  behaviour too — the hero truck declares none, so its lamps are the sprite and the beam and its
  lenses never change. Giving it lit glass means authoring a two-frame lens texture and four
  binding rows into a mod this project otherwise loads unmodified.

## Checking against Rigs of Rods itself

`tools/build_parity.sh` extracts a function from the pinned upstream submodule, compiles it on its
own against a shim in `tools/parity/shim/`, and `upstream_contact_parity` compares it with ours case
by case. Nothing is copied into the tree; a rename upstream fails extraction rather than comparing
against a stale copy.

**Upstream's physics is not exact arithmetic and must not be implemented as though it were.**
`approx_exp` is three integer operations on a float's bit pattern; `fast_invSqrt` is the Quake
reciprocal square root, and every beam length in a rig is divided by it. The errors are a systematic
bias the force laws were tuned against for fifteen years. Implementing the same laws with `std::exp`
measured 4.4% out on the force delivered to a node, and tens of percent on friction at low slip.
`ror_approx.h` reproduces them bit for bit; use it wherever upstream uses them, and expect any
closed-form oracle to need an allowance derived from that error.

What this can and cannot do:

- **Extractable now**: anything that is a whole function and does not reach into `Actor` —
  `primitiveCollision` is done; `Differential::CalcAxleTorque` and `TorqueCurve::getEngineTorque`
  are the obvious next ones, then `Engine::UpdateEngine` with `App::` and the sound macros stubbed.
- **Not extractable**: a whole rig stepping. That needs `Actor` plus `Terrain` plus `GameContext`
  plus OGRE, which is the coupling M1 exists to break. So parity proves the force *laws* match; it
  says nothing about integration order or emergent behaviour.

## How to work here

**A gate that is implied is not a gate that passed.** The graph's edges are claims about claims and
nothing can check them: write one only when the higher gate's procedure genuinely contains the lower
one's, and run `--all --every` before believing a green suite over a change that touched the chain.

**Gates are the only sense of sight, so they have to be honest.** Every gate declares metadata
(`name`, `proves`, `oracle`, `threshold`, `why`, `budget_s`, `needs_gpu`, `milestone`) and the
`gate_metadata` gate refuses to run one without it. Prefer an outside oracle, then a computed one,
then an invariant; goldens are a last resort and there are currently none.

**A gate may not write its own expectation.** If a threshold no longer holds, the number is a
finding — see the red gate above. Widening it to match what the code does is the one thing that
cannot be done here.

**Write the negative control before you trust a new gate, and distrust a control that changes
nothing.** Break the thing deliberately, confirm the gate fails, then restore. Both failure modes
have happened here: a gate that passed on the known-bad state, and a control wired to a copy of the
code the live path never reaches, which made a working gate look worthless.

**A place a gate stands on has to be derived, not written down.** A coordinate means something on
one map and nothing on the next, which is what every gate holding a valley coordinate discovered
when the valley went. Search the terrain's own heightmap in a fixed order and report where you went.

**Measure before changing anything.** Write a probe in `game/tools/`, get a number, then act.

**Keep the suite run and the commit as separate commands.** Committing on red has happened here.

**Standards are enforced, not aspirational.** GDScript files stay under 400 lines, C++ under 600;
everything is statically typed; `.tscn` files carry structure only and all tunables live in
`game/config/*.gd`. When a file goes over the cap the fix is extraction, never reformatting to dodge
the counter.

**The user is in the loop and only they close a milestone.** `./tools/play.sh --truck` opens a real
window; `./tools/photoset.sh` renders eight numbered views of the vehicle including the interior.
Put numbers on views so the user can point at one. `godot --headless` renders nothing, so image
gates need a real window, and `tools/gate.sh` refuses to run while one is open.

## Facts that cost time to establish — do not re-derive them

They have their own documents, because there are now over seventy of them and every file here has
a size cap:

- **`docs/guides/hard-won-facts.md`** — the solver, the terrain, the file formats, and the
  discipline the gates are held to.
- **`docs/guides/hard-won-facts-mods.md`** — how a vehicle is read, built and drawn. Almost all
  of it was learned the day a second and third pack arrived, and the pattern behind nearly every
  entry is that one test vehicle calibrates the loader to itself.
- **`docs/guides/hard-won-facts-terrain.md`** — how a terrain's own files become a world: object
  definitions, object lists, the collision its author wrote down, splat maps, and roads described
  as a line of points. Split from the mods guide when that hit its cap, and the pattern behind
  most of it is that a terrain ships far more than a heightmap and this project read half of it.
- **`docs/guides/hard-won-facts-light.md`** — light, colour, exposure and anything that measures a
  picture. Split out when the first file hit its cap, and the larger half of the two by effort:
  this is the area the project has been wrong about most often, usually by trusting an instrument
  nobody had checked.

Read the relevant one before changing anything in the solver, the compatibility shim, the terrain
or the lighting. Every entry is something that was measured, and most of them were measured twice
because the first answer was wrong.

## Licence

The project is GPL-3.0-or-later, inherited from Rigs of Rods. Third-party assets need a `LICENSES/`
record and a `THIRD_PARTY.md` entry with a version pin, and engine-locked content (Unreal
marketplace, Megascans) is rejected by name. Base Rigs of Rods content is GPL and may be
redistributed; community mods generally state no licence and cannot be — the hero vehicle's own
readme forbids it explicitly.
