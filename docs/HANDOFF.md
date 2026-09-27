# Handoff prompt

Audience: a contributor or agent picking this project up in a fresh session.

Copy everything below the line into a fresh session.

---

Continue work on the Rigs of Rods → Godot 4.x renderer rewrite in `/Users/htdguide/ror-godot`.
Read `docs/PLAN.md` first — it is the approved plan and it is authoritative. Then
`docs/architecture/bridge.md` and `docs/decisions/` for the decisions already taken.

## Where things stand

The last commit is `feat(world): a forest on the valley walls`.
`./tools/gate.sh --all` is green across 59 gates in about 55 s of gate time; run it before you
start so you know that is still true. It walks the gate graph — a gate may declare the gates its
own claim contains, so a passing gate reports those as `IMPLIED` rather than running them, and a
failing one is chased downward until the lowest failing gate names the level the fault is at.
`--all --every` ignores the graph and runs everything, which is what a release run uses;
`tools/gate.sh --why <gate>` asks the "is it this, or something under it?" question directly.
See `docs/guides/harness.md`. `tools/valley_shots.sh` renders the seven named places in
the valley as one sheet, which is what a session looking at the scene is run from. The hero asset is an unmodified
community mod at `assets/mods/ChevyS1023` (`S10offroad.truck`), loaded through the compatibility
shim with no conversion step.

**It drives.** `tools/play.sh --truck` opens a window on the valley and hands over the
controls: throttle, brakes, steering, gears, ignition, lights, respawn, chase camera and a
HUD. The solver has the force sources a driven rig needs, each a port of upstream's own law
and each in its own file: ground contact with static and Stribeck friction (`ror_ground`),
wheel torque and braking (`ror_wheels`), engine, gearbox and clutch (`ror_drivetrain`),
steering through hydro rest length (`ror_steering`), per-node air drag, travel bounds for
shocks, ropes and support beams, and a heightfield so it stands on terrain rather than a plane.

**The 2 kHz gap is closed.** The rig settles at upstream's own rate and diverges at 1.5 kHz;
`game/tools/stability_probe.gd` measures it by sweeping. Node masses did most of it (10 kHz to
3 kHz) and `set_beam_defaults_scale` the rest. Air drag was not a factor either way.

**Valley One is the 2 km valley the plan asks for, with its features in it.** See
`docs/architecture/valley.md`: a layout file of metres, a pure shape function, a water-cut file
and a builder. It has the test track it always had — nine surface lanes, level, with the tunnel
on it — plus a lake, a river that crosses the floor at a ford and drains into it, a washout, an
off-camber rock shelf, and a switchback road benched into the north wall that climbs 108 m to a
ridge at 6% with a 9.5% worst hairpin. Generating it is 22 s of GDScript, so it is cached under
`user://` and a load is checked against the shape function rather than trusted: warm is 2.5 s.

**The valley has a forest.** Conifers and shrubs, generated rather than sourced, placed by a pure
function of position — a hash per cell, no RNG and no stored list — with a stand on the north wall
where `valley_vista` and `switchback_backlit` are framed. 5,149 conifers and 15,043 shrubs, one
multimesh each.

**The water is in.** A lake at the low end, a river that crosses the floor at a ford and drains
into it, depth-faded and rippled. Its surface is derived from the valley floor rather than
declared, which is the third version and the first correct one — see
`docs/architecture/valley.md`.

**Grip is a property of the ground.** All nine of upstream's ground models are implemented and
checked against its own `ground_models.cfg`, and the terrain lays them down per lane, so ice is
ice and sand is sand rather than everything being `concrete` at 1.2.

**Beams bend and break.** Reported in a session as the truck being "too stiff and not bending as
it is supposed to", and the cause was that `set_beam_defaults`' deform and break fields were
parsed as nothing: every beam in the project was a perfect spring. Upstream's plasticity is ported
now — past its yield a beam's *rest length* moves, so the shape it returns to is the shape it was
bent into — and the hero truck crashes properly: driven into a wall at 32 m/s it bends 276 beams,
worst by 204 mm, and breaks 51 of 1,995. At 2.4 m/s it bends none.

**The suspension travels.** It was welded at 6 mm; the `beams` section's options were being read
as data and two of them are load paths. It now settles 90 to 99 mm per wheel, which is what a
lifted truck does.

Also working: OGRE `.mesh` reading, DDS textures, PBR materials from `managedmaterials`,
flexbodies skinned to solver nodes, rigid props, generated wheel tread that now spins,
flares as real lamps, a reflection probe per actor, a tunnel that is a lighting rig, generated
per-surface ground textures with detiling, and recovery from a roll.

## What to do next

**0. What a session opens now.** `tools/play.sh --truck` opens the flat test park: a straight
road with eight surface patches let into it, a washboard, ruts, dips, a ramp yard, a rock garden,
a crash yard and an ice skid pad, all within a few seconds of each other. Valley One is
`--valley`, and a shipped Rigs of Rods terrain is `--map <name>`.

Sessions open at golden dusk unless `--weather` says otherwise: a window is not a gate, and the
low sun is the hour that shows a vehicle off.

Controls: `G` drive, `B` reverse, `H` neutral, `I` ignition, `N` or `L` lights, `R` recover
upright, Backspace respawn, `Z`/`C`/`X` indicators, `F5`/`F6`/`F7` chase, free and driver's seat.
`Esc` opens the settings panel — weather, gravity, sun, shadows, sky brightness, exposure, cloud
cover and density, wind, view distance, fog, grass distance, lamps — with Resume and Quit in it.

The cab works: the wheel turns on its own column by the ratio the mod's file declares, the dials
sit ahead of the wheel and read the drivetrain, and the lamps light by what the vehicle is doing.
Rigs bend and break: `a_crash_bends_the_rig` drives the hero truck into a wall at 32 m/s and 276
beams take a permanent set.

**0b. Rigs of Rods terrains load, and any of them can be opened.** `tools/import_terrain.sh
<zip>` puts a terrain in the library under `assets/terrains/`, `--list` says what is there, and
`tools/play.sh --truck --map <name>` drives it. La Paz is the one this was built against: its
heightmap, traction map, ground models, splat textures, 101 objects and two vegetation layers all
come from the files its author shipped, and five gates hold that — `ror_terrain_matches_its_files`,
`ror_terrain_is_drivable`, `ror_terrain_objects_are_placed`, `ror_terrain_grows_its_vegetation`
and `terrain_library_loads_what_it_holds`, with `ror_terrain_photoset` for the sheet.

What a loaded terrain does **not** have yet, each named rather than forgotten:

- **Hand-placed collision meshes.** A terrain can ship them and La Paz does not. Its objects are
  solid: `world/ror_object_collision.gd` turns each mesh into columns — a cell of ground plane
  and the height of the geometry in it — so a pole is a pole and a 40 m power line is two poles
  rather than a wall. Objects scaled to cover the map, like the ground skirt and the horizon
  card, are left alone.
- **Procedural roads.** `.tobj` road/road2 sections are reported as unread lines. La Paz has none.
- **Water.** A terrain's `Water` and `WaterLine` are read and ignored; La Paz has water off.
- **Sky.** The terrn2 names a cube map from Rigs of Rods' core resources, which a terrain does
  not ship, so the scene keeps its own physical sky.
- **Vegetation colour maps and sway.** The layer's colour map and its sway numbers are read and
  unused; plants are still and untinted.
- **The last sample row and column.** Terrain3D's regions tile on a power of two, so a 2049
  sample page is imported as 2048 cells and the map is 2 m short of its stated 4000 m.
- **The traction map is nearest-sampled** at 3.9 m per pixel on La Paz, where upstream filters
  it bilinearly; surface edges are a pixel blocky.

**1. The ground material.** Water and vegetation tier 1 are in (see
`docs/architecture/valley.md`); what is left of PLAN §0.5's M2 staging is the PBR ground material
through `res://shaders/terrain3d_override.gdshader`, and vegetation tiers 2 and 3.

**1b. Why the valley reads dark — measured, and partly still open.** Two gates now hold what was
established. `daylight_shadows_are_readable` puts a mid-grey quad in the noon light and reads it
twice: sunlit 0.378 against sky-lit 0.119 scene-referred, which displays as 0.307 and 0.069, so
the pipeline does keep a sky-lit surface readable and the grading is not the fault. The same gate
records that the scene's sun-to-sky balance is about 3:1 where clear-sky daylight is nearer 14:1
— the sky is roughly three times too strong relative to the sun — which belongs with M2's HDRI
sky rather than with a knob here.

`terrain_takes_the_light` compares the ground with a Lambertian patch laid on it, switching the
sun off in the same frame: the sun multiplies the patch by 2.63 and the terrain by 3.19, 21%
apart, which means **the terrain takes a smaller share of its light from the sky than anything
standing on it does**. That is the part that is still open, and it is the reason a shaded wall
reads darker than a truck parked against it.

While chasing it, something worth knowing surfaced: **Terrain3D is drawing the ground from the
colour map and the heightmap, and the texture assets attached to it reach nothing.** Darkening a
surface's albedo texture to a third, setting its `albedo_color` to white, and taking the normal
map's depth to zero each changed the render by nothing at all, to four decimal places. The
surface textures are generated, attached (nine of them, with the right names and images) and
apparently unused; what is visible as "surface" is the per-texel tint in the colour map. Both this
and the ambient share are the M2 ground material's to settle, since that replaces Terrain3D's
shading with `res://shaders/terrain3d_override.gdshader`, which this project owns.

**2. The money shots are now unblocked, and named anchors exist.** `ValleyLayout.ANCHORS` holds
`ridge_vista`, `switchback`, `ford`, `lake`, `ruts` and `rock_traverse`; nothing consumes them
yet. Wiring the eight shots to anchors gives the before-image the whole project is measured
against, which PLAN M1 asks for as visual verification.

**3. The drivability scenarios.** PLAN M1 acceptance 7 wants `switchback_climb`, `ford_crossing`
and `rut_traverse` completing without the actor falling through, getting stuck or exploding. All
three features now exist and `road_is_drivable` says the road is within the rig's traction, so
what remains is driving them: `harness/scenarios.gd` still has only `static`.

**4. What the human sessions found and nobody has closed.**

- **The tyres ring.** Improved by the parity work, not yet resolved. The worst tread node was
  1.646 m/s at 248 Hz; using upstream's approximate maths took it to 0.492 m/s at the same
  2 kHz, and the worst body node from 0.156 to 0.066 m/s. Its frequency matches the rim hoop
  beams: 3.4 MN/m on a 2.03 kg node is 206 Hz with a damping ratio of 0.7%. Note the tension
  with the 2 kHz result: the rig is *stable* at 2 kHz and not *quiet* there. Do not fix this
  by raising the rate without saying so.
  - Known parity gap that has not been tried yet: upstream gives a meshwheels2 wheel's
    `axis1-outer` and `axis2-inner` tyre beams SHOCK1 bounds with a 0.66 shortbound and a 0.15
    max extension. The bounded beam laws exist now; the wheel rig does not use them.
- **It rolls over more easily than the numbers say it should.** The centre of mass is 0.762 m
  above the contact patch over a 1.80 m track, a 1.18 g static rollover threshold, better than a
  real lifted S10. Every surface being `concrete` was the suspected cause and that is now fixed,
  so this wants re-measuring on gravel and sand before anything else is changed.

**5. Fidelity gaps that are named rather than forgotten.**

- The hero truck declares a `fusedrag` section. Upstream gives such a rig a single fuselage
  drag vector instead of the per-node drag it currently gets.
- `contacters` (79 rows) is unparsed, so every node collides with the ground rather than the
  ones the file nominates.
- Differentials are not modelled. The hero rig's are all split, and a split differential
  chain reduces to the division `ror_wheels` already does, so this is invisible on this rig
  and wrong on one with locked or open diffs.
- `commands2` beams hold the doors but are not key-driven, so the doors do not open.
- Traction control and ABS are not implemented; neither is declared by the hero rig. At full
  throttle it breaks traction and the wheels run away, which is what a 4WD truck with 11 kNm
  at the wheels does on concrete, but with no aerodynamic drag on the body to bound it the
  spin is unphysical.
- Flares are placed and lit but not animated: indicators do not blink, brake lights do not
  follow the pedal, and reversing lights do not follow the gear.
- The tunnel is a lighting rig with no collision: the solver collides against the terrain and
  nothing else, so a vehicle drives through its walls.

## Checking against Rigs of Rods itself

`tools/build_parity.sh` extracts a function from the pinned upstream submodule, compiles it
on its own against a shim in `tools/parity/shim/`, and `upstream_contact_parity` compares it
with ours case by case. Nothing is copied into the tree; a rename upstream fails extraction
rather than comparing against a stale copy. Terrain never enters, because both sides are
handed a surface normal and a penetration depth directly.

**Upstream's physics is not exact arithmetic and must not be implemented as though it were.**
`approx_exp` is three integer operations on a float's bit pattern; `fast_invSqrt` is the Quake
reciprocal square root, and every beam length in a rig is divided by it. The errors are a
systematic bias the force laws were tuned against for fifteen years. Implementing the same
laws with `std::exp` measured 4.4% out on the force delivered to a node, and tens of percent
on friction at low slip. `ror_approx.h` reproduces them bit for bit; use it wherever upstream
uses them, and expect any closed-form oracle to need an allowance derived from that error.

What this can and cannot do:

- **Extractable now**: anything that is a whole function and does not reach into `Actor` —
  `primitiveCollision` is done; `Differential::CalcAxleTorque` and `TorqueCurve::getEngineTorque`
  are the obvious next ones, then `Engine::UpdateEngine` with `App::` and the sound macros
  stubbed, which would check the whole drivetrain.
- **Not extractable**: a whole rig stepping. That needs `Actor` plus `Terrain` plus
  `GameContext` plus OGRE, which is the coupling M1 exists to break. So parity proves the
  force *laws* match; it says nothing about integration order, per-substep sequencing, or
  emergent behaviour like the suspension travelling 6 mm.

## How to work here

**A gate that is implied is not a gate that passed.** The graph's edges are claims about claims
and nothing can check them: write one only when the higher gate's procedure genuinely contains the
lower one's, and run `--all --every` before believing a green suite over a change that touched the
chain.

**Gates are the only sense of sight, so they have to be honest.** Every gate declares metadata
(`name`, `proves`, `oracle`, `threshold`, `why`, `budget_s`, `needs_gpu`, `milestone`) and the
`gate_metadata` gate refuses to run one without it. Prefer an outside oracle, then a computed
one, then an invariant; goldens are a last resort and there are currently none.

**Write the negative control before you trust a new gate.** Break the thing deliberately,
confirm the gate fails, then restore. This session wrote a gate that passed on the known-bad
state — a prop flung out beside the front tyre was still inside the body's bounding box — and
it was worthless until the subject was narrowed to the cab. A gate that passes on the fault it
was written for is worse than no gate.

**Measure before changing anything.** Every fault this session took more turns than it should
have because reasoning ran ahead of measurement. Write a probe in `game/tools/`, get a number,
then act. Three separate wrong steering-wheel rakes each looked right in code review.

**Keep the suite run and the commit as separate commands.** Committing on red has happened
here more than once.

**Standards are enforced, not aspirational.** GDScript files stay under 400 lines, C++ under
600; everything is statically typed; `.tscn` files carry structure only and all tunables live
in `game/config/*.gd`. When a file goes over the cap the fix is extraction, never reformatting
to dodge the counter — `MeshAssembler`, `WheelRig`, `PlacementRows`, `CabRows`, `BeamRows` and
`NodeIdRanges` all exist for that reason and each is a real responsibility.

**The user is in the loop and only they close a milestone.** `./tools/play.sh --truck` opens a
real window; `./tools/photoset.sh` renders eight numbered views of the vehicle including the
interior. Put numbers on views so the user can point at one. Take a photoset after any change
to model or material work, and send it to them. `godot --headless` renders nothing, so image
gates need a real window, and `tools/gate.sh` refuses to run while one is open.

## Facts that cost time to establish — do not re-derive them

They have their own document, because there are now fifty of them and this one has a size cap:
**`docs/guides/hard-won-facts.md`**. Read it before changing anything in the solver, the
compatibility shim, the terrain or the lighting. Every entry is something that was measured, and
most of them were measured twice because the first answer was wrong.

## Licence

The project is GPL-3.0-or-later, inherited from Rigs of Rods. Third-party assets need a
`LICENSES/` record and a `THIRD_PARTY.md` entry with a version pin, and engine-locked content
(Unreal marketplace, Megascans) is rejected by name.
