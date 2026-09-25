# Handoff prompt

Audience: a contributor or agent picking this project up in a fresh session.

Copy everything below the line into a fresh session.

---

Continue work on the Rigs of Rods → Godot 4.x renderer rewrite in `/Users/htdguide/ror-godot`.
Read `docs/PLAN.md` first — it is the approved plan and it is authoritative. Then
`docs/architecture/bridge.md` and `docs/decisions/` for the decisions already taken.

## Where things stand

HEAD is `6a8913f`. `./tools/gate.sh --all` is green across 44 gates; run it before you start
so you know that is still true. The hero asset is an unmodified community mod at
`assets/mods/ChevyS1023` (`S10offroad.truck`), loaded through the compatibility shim with no
conversion step.

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

**Terrain3D is in and used.** Pinned at `v1.0.2-stable`, built by `tools/build_terrain3d.sh`
— a fresh checkout has no terrain until that is run, and the terrain gates skip cleanly.
There is a generated valley, collision mode `Disabled`, and the solver collides against the
same surface the renderer draws, checked to 0.0 mm.

Also working: OGRE `.mesh` reading, DDS textures, PBR materials from `managedmaterials`,
flexbodies skinned to solver nodes, rigid props, generated wheel tread that now spins,
flares as real lamps, and a reflection probe per actor.

## What to do next

**1. Valley One v2 content.** The valley is a generated shape with no materials, no
vegetation and no features. Six of the eight money shots name content that does not exist —
a conifer stand, a river, a tunnel, a rock traverse, a lake — so the shot list is blocked on
this rather than on the shots. PLAN §0.5 stages it; §0.6 names the seams:
`tools/import_dem.gd` for real elevation data, `res://shaders/terrain3d_override.gdshader`
for the material, `Terrain3DInstancer` for vegetation. Anything third-party needs its own ask.

**2. The drivability scenarios.** PLAN M1 acceptance 7 wants `switchback_climb`,
`ford_crossing` and `rut_traverse` completing without the actor falling through, getting
stuck or exploding. The rig drives and the terrain queries work, so these are now writable.

**3. Fidelity gaps that are named rather than forgotten.**

- The hero truck declares a `fusedrag` section. Upstream gives such a rig a single fuselage
  drag vector instead of the per-node drag it currently gets.
- `contacters` (79 rows) is unparsed, so every node collides with the ground rather than the
  ones the file nominates.
- Differentials are not modelled. The hero rig's are all split, and a split differential
  chain reduces to the division `ror_wheels` already does, so this is invisible on this rig
  and wrong on one with locked or open diffs.
- `commands2` beams hold the doors but are not key-driven, so the doors do not open.
- Beam deformation and breaking are not implemented.
- Traction control and ABS are not implemented; neither is declared by the hero rig. At full
  throttle it breaks traction and the wheels run away, which is what a 4WD truck with 11 kNm
  at the wheels does on concrete, but with no aerodynamic drag on the body to bound it the
  spin is unphysical.
- Flares are placed and lit but not animated: indicators do not blink, brake lights do not
  follow the pedal, and reversing lights do not follow the gear.

## How to work here

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
- **Every gate in the suite can be green while something is visibly broken.** Missing vertex
  normals, tyres buried 0.34 m in the ground, and a door hanging a metre off its hinges all
  passed every check that existed at the time, because each measured nodes and the nodes were
  right. When the user reports something, believe them and go find the number that shows it.

## Licence

The project is GPL-3.0-or-later, inherited from Rigs of Rods. Third-party assets need a
`LICENSES/` record and a `THIRD_PARTY.md` entry with a version pin, and engine-locked content
(Unreal marketplace, Megascans) is rejected by name.
