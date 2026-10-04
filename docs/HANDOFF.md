# Handoff prompt

Audience: a contributor or agent picking this project up in a fresh session.

Copy everything below the line into a fresh session.

---

Continue work on **an alternative Rigs of Rods client**, built on Godot 4.x, in
`/Users/htdguide/ror-godot`. Read `docs/PLAN.md` first — it is the approved plan and it is
authoritative. It was re-scoped on 2026-09-30 from a renderer rewrite to a client: §0.5, §0.7–§0.10
and §1's ordering are the new parts and the decisions table records what was superseded. Then
`docs/architecture/bridge.md` and `docs/decisions/`.

**Next milestone is D0, the dev environment** (§0.8), and all seven of its acceptance items are
done: the §0.7 folder mirror, the one-window container runner, order independence, no leaks, the
`static_state` lint, one command table behind three front ends, and one JSONL line per command.
`tools/gate.sh` is a client of that table too: `--gate a,b,c` is sugar for `gate run a b c`, so
the path CI uses is the path a person uses, and `tools/gate.sh --cmd "<line>"` runs any console
command from a shell.

**M2 is next** — PBR ground and HDRI sky.

**Two sections were decided on 2026-10-01 and nothing in them is built.** §0.10 is now
client-authoritative state replication on this project's own wire at 64 players, and **RoRnet
compatibility is retired** — it records the oracle that cost and the four things that have to
replace it. §0.12 is the scale design: float32 gives 11.9 mm at 100 km and beam forces are
differences of positions, so the fix is per-actor frames that follow the actor, with islands,
sleeping, and a causality bound from a 1000 km/h v_max. **Its first prerequisite does not exist: a
hard node-velocity clamp.** Without one the bound is an assumption rather than a theorem. Read
§0.12's order-of-work before starting any of it — step 2 is two cheap measurements that decide
whether the rest is urgent at all, because at La Paz scale the relative beam error is ~5e-4, which
is coarser than this project's own tolerances.

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
`gate run rig_steers` in an open session is under a second where a fresh engine pays startup,
shader compilation and terrain import first. The whole suite is `gate all` — one window, 77 s.
`tools/gate.sh --all` does the same thing in one launch; the scheduling that used to live in bash
and cost an engine per tier is `harness/gate_suite.gd` now.

`tools/gate.sh --order-check` runs every gate twice **in one session**, once in the graph's order
and once in a seeded shuffle, comparing verdicts and measured values. Worst drift across the
suite is 1.1e-7. Use `tools/gate.sh --all --every` for a number that goes in a commit message: it
starts fresh, which a session kept open all day does not. The order after it is: M2, M2b, C1 GUI+audio, C2 format coverage+AngelScript, M3–M8,
C3 airplanes+boats, C4 repository, C5 multiplayer. Local milestones first; the two networked ones
last, deliberately. The UI's design is settled in §0.11: recognisably RoR and refreshed, with the
in-vehicle instruments under glass that reflects, backlights warm from below with the lights, and
carries a bounded inertia against the vehicle's own acceleration.

## Where things stand

`./tools/gate.sh --all` is green except for one gate, named below. Run it before you start so you
know that is still true. It walks the gate graph — a gate may declare the gates its own claim
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
map Rigs of Rods itself opens with: `simple2-terrain`, three terrains over one set of files
(`simple2` gravel, `simple2_a` asphalt, `simple2_w` flooded), 1024 m, `Flat=1`. It is what
`tools/play.sh --truck` opens with no arguments, and `a_shipped_map_drives_from_a_fresh_clone` holds
it. Before this, every terrain gate skipped on a clean checkout, because the terrains and the hero
vehicle are gitignored for licensing reasons.

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
skinned to solver nodes, rigid props, generated wheel tread that spins, flares as real lamps
drawn as additive sprites, a reflection probe per actor, a terrain's own objects as solid columns,
a terrain's own vegetation in a ring that follows the driver, and recovery from a roll.

Sessions open at golden dusk unless `--weather` says otherwise: a window is not a gate, and the low
sun is the hour that shows a vehicle off. `Esc` opens the settings panel — weather, gravity, sun,
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

123 gates, `--all --every`, all passing, and `tools/gate.sh --order-check` runs every one of them
twice in one session with a worst measured drift of zero.

It had one red gate for most of a session — `terrain_takes_the_light`, reading 111% against a 30%
threshold — and the cause was not what it was recorded as. See the entry on
`Image.create_from_data` in `docs/guides/hard-won-facts.md`: one wrong `use_mipmaps` flag made
every ground texture blank, and four separate findings were all that one bug. The gate passes at
22.6% on its original threshold. It was worth not widening.

## What to do next

**1. M2, the renderer milestone.** Its scope is in PLAN §1 and it is mostly untouched: the
`WorldEnvironment` in code, HDRI skies per weather preset, the vehicle `.gdshader` with
metallic-roughness and clearcoat, derived roughness for legacy assets, and the Khronos
`pbr_spheres` oracle — an AI-free check of the BRDF and the IBL path against the reference image
shipped with `glTF-Sample-Assets`.

**What M2 no longer has to do:** write a ground material at all. Terrain3D's own shader is
metallic-roughness, and with the blank-texture bug fixed it draws the author's albedo and normal
maps and takes per-surface roughness as a real shader input.
`the_ground_draws_its_own_textures` holds both halves — darkening one splat layer to a third moves
the ground 0.2384 luma, and sweeping roughness mirror-to-matte moves it 0.0996. Nothing in the
Rigs of Rods `.otc` format carries roughness, so a single constant is the honest choice rather
than a number this project invents. `res://shaders/terrain3d_override.gdshader` is no longer a
prerequisite for anything.

**One of the four old findings was not collateral**, and it is worth not re-chasing: La Paz ships
`blank_NRM.dds` for all four layers, so its normal maps really are flat. "Normal depth to zero
changed nothing" was true.

Also measured and still open: `daylight_shadows_are_readable` records that the scene's sun-to-sky
balance is about 3:1 where clear-sky daylight is nearer 14:1 — the sky is roughly three times too
strong relative to the sun — which belongs with M2's HDRI sky. That one was measured against a
grey quad rather than against the ground, so the blank-texture bug did not reach it.

**2. The money shots do not exist.** PLAN §0.5 named eight, and half of them named features of the
deleted valley. Nothing renders the sheet today, so there is no before-image for the project to be
measured against — which M1 asks for. A replacement set has to place every frame from something the
*terrain* declares, or from a search over its own heightmap, never from a coordinate written down
beside it. `ror_terrain_photoset` renders La Paz and is the only photoset left.

**3. What M1 acceptance still wants**, each checked against the suite rather than remembered:

- **Acceptance 2** — `solver_ms`, `deform_ms` and `submit_ms` reported separately. `metrics.gd`
  records `frame_ms` only; none of the three names appears anywhere in the tree.
- **Acceptance 4** — a determinism gate: 600 frames, two runs, identical node-position hash. No such
  gate exists. `capture_stability` compares two captures of an image, which is not the same claim.
- **Acceptance 5** — `mod_corpus` over 200 archive mods, each either loading or reporting a named
  unsupported feature. No such gate exists; `truck_parse` reads one vehicle.

Acceptance 1, 3, 6, 7 and 8 pass.

**4. What a loaded terrain does not have yet**, each named rather than forgotten:

- **Water.** A terrain's `Water` and `WaterLine` are read and ignored, so there is no water in the
  project at all — the valley's lake and river went with it. `simple2_w` declares water at 100 m and
  renders dry. PLAN §0.5 records that water is now unscheduled rather than staged.
- **Procedural roads.** `.tobj` road/road2 sections are reported as unread lines.
- **Hand-placed collision meshes.** A terrain can ship them and La Paz does not. Its objects are
  solid by columns instead — `world/ror_object_collision.gd` turns each mesh into a cell of ground
  plane and the height of the geometry in it — so a pole is a pole and a 40 m power line is two
  poles rather than a wall. Objects scaled to cover the map are left alone.
- **Sky.** The terrn2 names a cube map from Rigs of Rods' core resources, which a terrain does not
  ship, so the scene keeps its own physical sky.
- **Vegetation colour maps and sway.** Read and unused; plants are still and untinted.
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
  - Untried parity gap: upstream gives a meshwheels2 wheel's `axis1-outer` and `axis2-inner` tyre
    beams SHOCK1 bounds with a 0.66 shortbound and a 0.15 max extension. The bounded beam laws
    exist; the wheel rig does not use them.
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
- `commands2` beams hold the doors but are not key-driven, so the doors do not open.
- Traction control and ABS are not implemented; neither is declared by the hero rig.
- Flares are placed and lit but not animated: indicators do not blink, brake lights do not follow
  the pedal, and reversing lights do not follow the gear.

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
