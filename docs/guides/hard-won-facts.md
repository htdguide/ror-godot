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
