# Handoff prompt

Audience: a contributor or agent picking this project up in a fresh session.

Copy everything below the line into a fresh session.

---

Continue work on the Rigs of Rods → Godot 4.x renderer rewrite in `/Users/htdguide/ror-godot`.
Read `docs/PLAN.md` first — it is the approved plan and it is authoritative. Then
`docs/architecture/bridge.md` and `docs/decisions/` for the decisions already taken.

## Where things stand

The last commit is `feat(world): the valley has the features the shot list names`.
`./tools/gate.sh --all` is green across 54 gates in about 60 s of gate time; run it before you
start so you know that is still true. The hero asset is an unmodified
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

**Grip is a property of the ground.** All nine of upstream's ground models are implemented and
checked against its own `ground_models.cfg`, and the terrain lays them down per lane, so ice is
ice and sand is sand rather than everything being `concrete` at 1.2.

**The suspension travels.** It was welded at 6 mm; the `beams` section's options were being read
as data and two of them are load paths. It now settles 90 to 99 mm per wheel, which is what a
lifted truck does.

Also working: OGRE `.mesh` reading, DDS textures, PBR materials from `managedmaterials`,
flexbodies skinned to solver nodes, rigid props, generated wheel tread that now spins,
flares as real lamps, a reflection probe per actor, a tunnel that is a lighting rig, generated
per-surface ground textures with detiling, and recovery from a roll.

## What to do next

**1. Water surfaces, then vegetation.** The valley's shape has a lake basin, a river bed and a
ford, and `ValleyLayout` declares the water levels for all three (`LAKE_WATER_Y_M`,
`RIVER_WATER_DEPTH_M`) — but nothing draws water yet, so `ford_crossing` and `lake_dusk` are
still shots of a dry hole. PLAN §0.5 stages a reflective, refractive, depth-faded plane here and
replaces its surface generation at M8 behind the same interface. Then vegetation: the conifer
stand for `valley_vista` and `switchback_backlit`, through `Terrain3DInstancer`, generated rather
than sourced unless a third-party kit is worth its own ask. The PBR ground material
(`res://shaders/terrain3d_override.gdshader`) is the third of the three M2 content seams.

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
- Beam deformation and breaking are not implemented.
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
- **A surface map is stored row by row, z outer and x inner**, because that is the order the
  solver reads a heightfield in. Stored the other way round it is transposed, and a transposed
  map is not obviously wrong: the right surfaces appear, in the wrong places, and the first
  symptom was the terrain drawing sand where the solver gripped concrete.
- **A gate that measures the wrong quantity passes on the fault it was written for.** The first
  version of `valley_has_its_features` measured how deep the lake's water was, which is mostly
  the valley floor descending under a flat water level: it passed with the basin set to half a
  metre. It measures the basin's carve against the floor now, and the negative control is the
  layout constant set to 0.5.
- **A contour road cannot be declared as a table of heights.** Give each control point a height
  and the road floats: the wall it is benched into is 3.9 m high where the table said 30 m. The
  road's height is read from the wall at the nearest point of its own centre line instead, so
  cut and fill are bounded by construction — 1.20 m measured — and the grade becomes a property
  of the path, which a gate can then measure.
- **A valley wall wants a constant slope where a road is benched into it, not a quadratic
  curve.** A quadratic wall is gentle at the toe and near-vertical at the top, so the contours a
  switchback road follows are 100 m apart at the bottom and 10 m apart at the top and the legs
  collide before reaching the ridge.
- **Feature bounds have to be derived from the feature, not written down.** The road corridor was
  clipped to a hand-written band of z and the apron lost 2.5 m of its width as soon as a control
  point moved; the band comes from the control points now.
- **Generating 4.2 M cells of terrain in GDScript costs 22 s, and it is the suite's runtime.**
  Measure with `tools/terrain_cost_probe.gd` before growing a map. The cache in
  `world/valley_cache.gd` is what makes the size affordable, and it verifies itself against the
  shape function on load because a cache is otherwise a golden artifact.
- **Every gate in the suite can be green while something is visibly broken.** Missing vertex
  normals, tyres buried 0.34 m in the ground, and a door hanging a metre off its hinges all
  passed every check that existed at the time, because each measured nodes and the nodes were
  right. When the user reports something, believe them and go find the number that shows it.

## Licence

The project is GPL-3.0-or-later, inherited from Rigs of Rods. Third-party assets need a
`LICENSES/` record and a `THIRD_PARTY.md` entry with a version pin, and engine-locked content
(Unreal marketplace, Megascans) is rejected by name.
