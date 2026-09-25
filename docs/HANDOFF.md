# Handoff prompt

Audience: a contributor or agent picking this project up in a fresh session.

Copy everything below the line into a fresh session.

---

Continue work on the Rigs of Rods → Godot 4.x renderer rewrite in `/Users/htdguide/ror-godot`.
Read `docs/PLAN.md` first — it is the approved plan and it is authoritative. Then
`docs/architecture/bridge.md` and `docs/decisions/` for the decisions already taken.

## Where things stand

HEAD is `d34619e`. `./tools/gate.sh --all` is green across 34 gates; run it before you start so
you know that is still true. The hero asset is an unmodified community mod at
`assets/mods/ChevyS1023` (`S10offroad.truck`), loaded through the compatibility shim with no
conversion step.

Working today: OGRE `.mesh` reading, DDS textures, PBR materials derived from
`managedmaterials`, flexbodies skinned to solver nodes through `RenderingServer` skeletons,
rigid props, generated wheel tread, and a symplectic-Euler node/beam solver in a C++
GDExtension. The truck loads, renders, skins, deforms, settles on its tyres and keeps its
doors on.

Not working yet: nothing drives. The solver never runs in the interactive window, there is no
engine, no wheel torque, no steering actuation, and no terrain beyond an infinite checkerboard
ground plane.

## What to do next

**1. Make it drive.** This is M1's human gate and it blocks judging anything visual, because
everything visual gets judged in motion. Needed:

- Step the solver per frame in `game/harness/play_rig.gd`, driving the mesh through
  `VehicleBuilder.apply_pose`.
- Torque on the propelled wheels' tread nodes, brakes, and steering from the `hydros` factor.
  `hydros` and `commands2` are parsed as plain beams today — structurally correct, functionally
  inert, so the steering rams hold the rack but do not steer it.
- Controls and a HUD readout in the play window.

**2. Close the 2 kHz gap.** The hero rig needs 10 kHz to stay stable; at 2 kHz it goes NaN,
and upstream runs 2 kHz. The suspects, in order: node mass is the minimass floor everywhere
instead of being derived from beam volume; there is no air drag; and shocks, ropes, supports
and command beams are modelled as plain springs rather than with their own force laws and
travel bounds. Until this closes every gate pays five times the substeps it should.

**3. Terrain.** Terrain3D (asset library #3892, MIT) is approved in the plan but not installed.
Ask the user before pulling it in — the approval-before-adoption rule in `docs/PLAN.md` §0 is
procedural and applies even to things the plan already names.

**4. M2 leftovers.** Per-actor `ReflectionProbe`, a ground material worth looking at, and the
eight money shots under the weather presets.

**5. Small and visible.** The `flares` section (12 entries on the hero truck) is unparsed, so
headlights and tail lights are texture only with no actual lamps.

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
