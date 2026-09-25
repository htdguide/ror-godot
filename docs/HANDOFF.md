# Handoff prompt

Audience: a contributor or agent picking this project up in a fresh session.

Copy everything below the line into a fresh session.

---

Continue work on the Rigs of Rods → Godot 4.x renderer rewrite in `/Users/htdguide/ror-godot`.
Read `docs/PLAN.md` first — it is the approved plan and it is authoritative. Then
`docs/architecture/bridge.md` and `docs/decisions/` for the decisions already taken.

## Where things stand

HEAD is `581f8b8`. `./tools/gate.sh --all` is green across 40 gates; run it before you start
so you know that is still true. The hero asset is an unmodified community mod at
`assets/mods/ChevyS1023` (`S10offroad.truck`), loaded through the compatibility shim with no
conversion step.

Working today: OGRE `.mesh` reading, DDS textures, PBR materials derived from
`managedmaterials`, flexbodies skinned to solver nodes through `RenderingServer` skeletons,
rigid props, generated wheel tread, and a node/beam solver in a C++ GDExtension that the
truck actually drives on. `tools/play.sh --truck` opens a window and hands over the
controls: throttle, brakes, steering, gears, a chase camera and a HUD.

The solver has the force sources a driven rig needs, each a port of upstream's own law and
each in its own file: ground contact with static and Stribeck friction (`ror_ground`), wheel
torque and braking (`ror_wheels`), engine, gearbox and clutch (`ror_drivetrain`), steering
through hydro rest length (`ror_steering`), per-node air drag, and travel bounds for shocks,
ropes and support beams.

**The 2 kHz gap is closed.** The rig settles at upstream's own rate and diverges at 1.5 kHz;
`game/tools/stability_probe.gd` measures it by sweeping. Neither suspect named in the last
handoff was the cause. Node masses did most of it (10 kHz to 3 kHz): the hero truck states a
weight on all 250 of its nodes and they were all being floored to minimass. Applying
`set_beam_defaults_scale` did the rest (3 kHz to 2 kHz). Air drag changed the stability floor
not at all, though it halves the residual ringing.

Terrain3D is adopted, pinned at `v1.0.2-stable`, built by `tools/build_terrain3d.sh` and
proven to load on Godot 4.7. There is no terrain yet — only an infinite checkerboard ground
plane.

## What to do next

**1. Build the terrain.** Terrain3D is installed but nothing uses it. A bare `Terrain3D` node
has a null `data` and a null collision object until its data directory is set, so start
there. Then `tools/import_dem.gd` (DEM to height/control/colour images through
`Terrain3DData.import_images`), collision mode `Disabled`, and
`res://compat/terrain3d_collision_bridge.gd` wrapping `get_height` / `get_normal` behind the
height-query interface the solver's ground contact needs — bulk region access, not per-wheel
scalar calls. `ror_ground` already takes a surface normal per node, so a sloped terrain needs
no new force law, only a real height and normal to hand it. Valley One's layout is in
PLAN §0.5.

**2. M2 leftovers.** Per-actor `ReflectionProbe`, a ground material worth looking at, and the
eight money shots under the weather presets.

**3. Small and visible.** The `flares` section (12 entries on the hero truck) is unparsed, so
headlights and tail lights are texture only with no actual lamps.

**4. Fidelity gaps that are named rather than forgotten.**

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
  at the wheels does on concrete, but with no drag or TC to bound it the spin is unphysical.

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
