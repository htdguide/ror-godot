# Hard-won facts: vehicles and their mods

Audience: anyone changing how a Rigs of Rods vehicle is read, built or drawn. Split out of
`hard-won-facts.md` when that file hit the project's 400-line cap.

Most of these were learned the day a second and third vehicle pack arrived. The pattern behind
almost all of them is one sentence: **one test vehicle calibrates the loader to itself.** A
convention cannot be shown wrong by the example it was calibrated on, and the hero truck agrees
with the wrong answer in at least three places where a second car does not.

See `hard-won-facts.md` for the solver, the terrain, the formats and the gate discipline, and
`hard-won-facts-light.md` for anything that measures a picture.

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
- **The vehicle renders in rig space.** `VehicleBuilder.build` computes the actor frame and puts
  it on the root, and poses bones in actor-local space, so the two compose back to rig space.
  Wiring the frame through properly makes two wheels render out on open ground; see the comment
  in `vehicle_builder.gd` and `docs/architecture/bridge.md`. Mixing the two spaces is what put
  the interior camera outside the cab.
- **The hero truck's `cab`/`submesh` sections are collision only** — zero `texcoords`, material
  `tracks/trans`, every triangle flagged `c`. ADR 0003's FlexObj path is not what is missing
  here, and the cab roof that looked absent was the lit-through bodywork instead.
- **A rig declares several cinecams** and only some are inside the cab. The hero truck's first
  is 0.22 m above its own roof; its second is the driver's eye.
- **Steering wheel rake is 121°, not upstream's −59°.** The mesh's thinnest axis is the column
  and on this wheel it runs along the stalk rather than the face, so flipping the sign trades
  one fault for the other. 121 = 180 − 59: the 180 is this project's prop chain differing from
  upstream's by a handedness, the sign is the stalk. `game/tools/prop_axis_probe.gd` measures it.
- **Orphan count is the exact leak signal; node count is not.** The engine adds nodes of its own
  during a run — overlay and tooltip scaffolding — so a container that leaves a few nodes behind
  has not necessarily leaked. A node with no parent that did not exist before has no innocent
  explanation, so that is the counter with no slack on it.
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
- **An unshaded material draws its albedo and ignores emission**, so a lamp built that way is the
  same brightness on and off. And a lens standing proud of the bodywork as a lit quad is a square
  on the front of the truck, which is what a session called an ugly rectangle. Lamps are additive
  sprites with a radial falloff now, which is also what upstream draws: off adds nothing.
- **A QuadMesh faces its own +Z**, and a lamp holder is built with -Z along the lamp's normal, so
  a lens added without a half turn shows its back to the world: culled from outside the vehicle,
  visible from inside it.
- **Braking distance does not separate two surfaces on this rig**: the brakes run out before the
  tyres do, so both stop in the same distance. Cornering does not either — the outside wheels
  load up enough to grip on both. Leaning on a parked rig with tilted gravity does, and it is the
  same test `surfaces_change_grip` uses for a single node.
- **A rig's aerodynamics depend on one section in its file.** Upstream drags a rig that declares
  `fusedrag` as a single flat plate from the fuselage's width, and every other rig node by node
  with a turbulent model. Given the wrong one the hero truck stopped accelerating at 63 km/h in
  fourth gear at full throttle; given its own — a 0.1 m fuselage, which is almost no drag — it
  reaches 288 km/h in top gear. Upstream's own fuselage code also sets the fuselage's back node
  to its front node, which zeroes the airfoil term; the port keeps that.
- **A cab's cluster belongs on the steering wheel, not on the dashboard prop or the eye.** The
  eye is a cinecam and hangs where a camera hangs; the hero truck's dashboard prop is a 0.8 mm
  placeholder because its dashboard is painted into the cab mesh. The wheel is the one thing in
  a cab that is always where the cab is.
- **A steering wheel turns about y after its rake** — upstream's chain is
  `Quaternion(rake, UNIT_X) * Quaternion(steer, UNIT_Y)` — and the mesh agrees: 0.207 m through
  the column against a 0.371 m rim. Composed as a single Euler triple it turns about an axis that
  is not the column, and an Euler *reading* of the result drifts with the rake: 175.71 degrees
  for a turn of 175.
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
- **Damage to a rig is six beam fields and a per-node count, not one.** A hit changes a beam's
  `rest_length` (the bend), both yield stresses, the recomputed `minmax_stress`, the `strength`
  where upstream softens a beam instead of snapping it, and `broken` — and breaking a beam also
  decrements `active_beams` on both of its nodes, which upstream consults before it will break the
  last beams holding a cab node. `RigBuilder.place` restored node positions, velocities and rest
  lengths and its own documentation called that "undeformed": true of bends, false of breaks. A
  reset truck came back on its wheels still holding every snapped beam and shed its doors and
  wheels again on the next step. Measured: a crash leaves 45 of 1995 beams broken and 500 bent.
  Repair restores a snapshot of the beams as built rather than recomputing them — recomputing
  would be a second implementation of rig building, free to drift from the first.
- **A Rigs of Rods vehicle is not always a `.truck`.** The extension says what the actor is meant
  to be — `.car`, `.load`, `.airplane`, `.boat`, `.trailer`, `.train`, `.fixed` — and the format
  inside is identical. Measured across four packs from the repository: `mazda626gf` ships only
  `mazda626sd18i-mt.car`, Starling Island ships five actors as `.truck` and `.boat`, NhelensGrass
  ships a bridge and a crane as `.fixed`. A library looking for trucks finds a third of them.
- **One content folder is routinely several maps and several vehicles, and it does not respect the
  root it was unpacked into.** Starling Island is four `.terrn2` and five actors in one download;
  the Chevy pack is four variations of one truck. Both content roots have to be searched for both
  kinds, or six of this checkout's nine downloaded actors are invisible — unpacked under
  `assets/terrains/` because the same folder also ships maps.
- **`Image.load_from_file` does not read DDS at run time.** Godot's DDS support is an import-time
  path, and every texture in this project already goes through the extension's `DdsReader` — the
  traction map was the one exception, so NhelensGrass failed to load at all over a 1024x1024 DXT1
  with eleven mipmaps. A traction map also has to be *decompressed* after loading, unlike every
  other texture here, because it is read back a pixel at a time rather than handed to the GPU.
- **A wheel section is not always `meshwheels`.** The Mazda's wheels are all `flexbodywheels`,
  which carries the same row as `meshwheels2` and differs only in that its tyre deforms with the
  body. Unparsed, the vehicle built 14 parts and zero wheels and sat on the road looking flat.
- **The flexbody rotation order is an open question, and upstream's answer is not the answer.**
  Upstream composes Z, then Y, then X (`FlexFactory.cpp:91-93`, and `ActorSpawner.cpp:1681-1683`
  for props); this project uses `Basis.from_euler`, whose default is YXZ. They agree whenever only
  one axis is turned, which covers the hero truck. Changing to upstream's order was tried and
  reverted: it does not fix the Mazda 626 — whose `270, 180, 180` draws along the wrong axis under
  either order — and it breaks the hero truck, whose steering column stops pointing down and fails
  `props_sit_in_the_vehicle`. So a second convention in this pipeline cancels YXZ, and finding it
  is the real task. Measured: the Mazda's nodes span 4.54 x 1.62 x 1.70 m, which is a car; its
  drawn meshes span 4.26 x 2.33 x 4.54 under YXZ and 4.26 x 1.76 x 5.85 under ZYX. Every flexbody
  frame has determinant +1, so it is not the mirrored-basis fault.
- **One test vehicle calibrates the loader to itself.** The hero truck's flexbody rotation is
  `180, -90, 0`, for which upstream's Z-Y-X composition and Godot's default YXZ are *identical* —
  measured in the engine, not argued. So the order could be wrong for every mod ever made and
  that truck would never say so. The Mazda's `270, 180, 180` differ by exactly 180 degrees about
  X, which is why it loaded upside down. Three loader faults surfaced the day a second and third
  pack arrived, all silent: no error, no warning, just less vehicle than the file describes.
- **Not every vehicle draws, and the reasons differ.** NhelensGrass's bridge, crane and monorail
  and the Daf semi trailer have their geometry in `submesh` sections, which this project reads
  for collision and never renders. Starling Island's vehicles name `seat.mesh` and
  `dashboard-small.mesh` from Rigs of Rods base content that is not installed here. A gate that
  demands geometry from either is demanding a feature or inventing an asset; both are reported
  and neither fails.
- **`flexbodywheels` is not a `meshwheels2` row.** They share eleven fields and then diverge: a
  mesh wheel carries `spring, damping, side, mesh, material`, a flexbody wheel carries
  `tyre spring, tyre damp, rim spring, rim damp, side, rim mesh, tyre mesh`
  (`RigDef_Parser.cpp`: `_ParseBaseMeshWheel` against `ParseFlexBodyWheel`). Read with the wrong
  layout the Mazda took its side from a rim stiffness of 320000, its rim mesh from a damping of
  40, and its material from the letter `l` — white tyres, no rims, and a car on its bump stops.
  Three symptoms, one misread row, and the row was misread by this project rather than by the mod.
- **A flexbody wheel's tyre is a mesh, not a material.** A mesh wheel names a material and the
  tyre is swept procedurally and painted with it; a flexbody wheel names two meshes, rim and tyre.
  Treating the second as a material leaves the tyre white with nothing in the log.
- **A flexbody wheel is a two-ring rig, not a mesh wheel with different fields.** Upstream builds
  it with `num_rays * 4` nodes and `num_rays * 20` beams — rim 8, tyre 10, support 2 per ray —
  against a mesh wheel's `num_rays * 2` and `num_rays * 8` (`ActorSpawner.cpp` spawn budget). The
  rim ring and the tyre ring are separate and the tyre is sprung against the rim, which is why the
  row states two spring/damping pairs. Parsed as a mesh wheel it gets half the nodes and two
  fifths of the beams: the wheel wobbles and does not sit on its suspension. Reading the row
  correctly is not the same as building the rig correctly, and only the first is done.
- **A flexbody wheel is a rim ring sprung inside a tyre ring, and the port is structural.**
  Upstream's `ProcessFlexBodyWheel` lays `rays * 4` nodes — rim outer, rim inner, tyre outer, tyre
  inner, each ring stepped half a ray so they interleave — and `rays * 20` beams: eight rim (axle
  to rim both ways, plus the rim ring's hoop and diagonals), ten tyre (each rim node to three
  tyre nodes, reaching back one ray, which is the sidewall; plus four tread beams at the rig's
  *structural* rates rather than the tyre's), and two support beams from the axle to the tread
  that carry nothing until the tyre is squashed to within 5% of the rim radius. Every rim-to-tyre
  beam gets half the stated tyre rate because each tyre node is held by two of them.
- **A vehicle declares its materials in two places, and a mesh does not know which.** Some are in
  the truck file's `managedmaterials`, the rest in an Ogre `.material` script beside it. The
  Mazda 626 declares thirteen in the first and ten more in the second — its paint, headlights,
  indicators, brake and fog lights — and this project read only the first for vehicles, so every
  mesh asking for one of the others got a plain grey material. Terrain objects have read these
  scripts since they were written; vehicles never did.
- **`anim_texture <base> <frames> <duration>` does not name a file.** Ogre expands it to
  `base_0.ext`, `base_1.ext` and so on, so taking the name as written finds nothing. The Mazda
  declares four of its lights this way — naming `mazda626gf-sd-lights.dds` while shipping
  `mazda626gf-sd-lights_0.dds` and `_1.dds` — and all four drew untextured. The first frame is
  what a still picture should show.
- **Rigs of Rods resolves content by name, not by path, and the base content was never missing.**
  Ogre's resource groups pool every registered directory, so a mod may name `seat.mesh` or the
  material `tracks/master` and get the game's own copy without saying where it is. This project
  looked only in the folder a mod was unpacked into, so 56 named meshes across the library
  resolved to nothing and 48 object surfaces drew untextured — and every one of those files was
  already in the checkout, under `vendor/rigs-of-rods/resources`, in a submodule that has been
  pinned since the beginning. Searching the mod's own directory first and the game's after took
  the library from 345 drawn parts and 47 textures to 405 and 89.
- **Half the materials in Rigs of Rods' content have no `texture` line.** A managed material is an
  abstract template that declares the `texture_unit` and leaves the file to the leaf:
  `resources/managed_materials/managed_mats.material` has `texture_unit Diffuse_Map { texture_alias
  diffuse_tex }`, and a leaf fills the hole with `set_texture_alias diffuse_tex master.dds`. 328 of
  the 670 materials in this checkout inherit from one of those templates and 23 are textured only
  this way — `tracks/master`, and with it RoR's `road`, `road2`, `roadturn`, `roadcross`, `roadtee`,
  `asphalt`, `runway` and `chp`, which is most of the road surface on every map ever made. The
  alias name is not a convention to guess at: it is written in the template, in the pinned
  submodule, which is why `a_materials_own_words_reach_the_surface` reads it from there.
- **A material with no texture is not a material with no appearance.** A fixed-function Ogre pass
  may be a flat colour, and 21 materials here are: Starling Island's `rey_si_dark` is `diffuse
  0.130303` and drew at the loader's placeholder 0.72, five and a half times too bright, which is a
  large part of what "the map is all white" looked like from the driver's seat. Ogre's alpha lives
  in the same line's fourth component, so `train_rails`' `invisible` is `diffuse 0 0 0 0` and drew
  as an opaque grey box standing where nothing should be.
- **A bare `LOD` line in an `.odef` is obsolete and must be thrown away**, which upstream does
  explicitly — `ODefFileFormat.cpp`: `if (strcmp(m_cur_line, "LOD") == 0) return true; // 'LOD
  line' = obsolete`. The header is a name, then a mesh, then a scale, so reading that line as the
  mesh name shifts everything by one: the mesh became `LOD`, the real mesh was eaten by the scale
  slot, and seven Starling Island objects — its firehouse, police department, store, warehouse,
  office block, bus stop and a road sign — drew only their collision box. A skipped mesh warns and
  the object draws whatever else it had, so nothing in the log said a building was missing. The
  cheap check that catches the whole class is counting named meshes against the disk:
  `an_object_definition_names_a_real_mesh` finds 550 and requires all 550 to be there.
- **Those same files carry the map's own LOD data.** `beginlodmesh` / `endlodmesh` lists a mesh per
  distance — `300, firehouse_lod1.mesh` — which is upstream's per-object detail reduction, authored
  by the terrain's author and shipped with the terrain. Upstream's current parser ignores the
  block; it is read by nothing here either. It is the first thing to reach for in PLAN 0.13, because
  it is distance geometry that already belongs to the content rather than something this project
  would have to invent.
- **An `.odef`'s `beginmesh` block is a collision mesh, not more geometry to draw.** Upstream puts
  it straight into `collision_meshes` — `ODefFileFormat.cpp`, at `endmesh`:
  `m_def->collision_meshes.emplace_back(m_ctx.cbox_mesh_name, m_ctx.header_scale,
  m_ctx.cbox_groundmodel_name);` — so the only thing an object renders is its header mesh. Read as
  drawn geometry, those hulls were rendered: Starling Island's `firehousebox.mesh`,
  `store02box.mesh`, `townhouse01box.mesh`, `haus5Kol.mesh` and `haus6Kol.mesh` stood over their
  buildings as untextured shells, which is a house with no texture, or half of one where the hull
  covered only part. 522 of Port Starling's 1189 object instances were hulls; La Paz drew 99 of
  them, one per pole. Their materials are `Material.001`, `Material.004` and `default` — Blender's
  defaults, declared in no script, because nobody was ever meant to see them, and chasing those
  names through the material scripts was chasing a texture that does not exist for a surface that
  should not be drawn.
- **Those hulls are the right collision geometry.** They are the building author's own statement
  about what is solid, which is strictly better than voxelising the visual mesh, and taking them
  where they exist cut La Paz from 396 derived boxes to 297 while the 70 km/h crash test stopped
  0.53 m short of the far side instead of 0.91 m. The fallback to the visual mesh stays, because
  La Paz declares neither a box nor a hull for anything and its poles were scenery a truck drove
  through.
- **A block-compressed image cannot have its mipmaps regenerated, and the DDS reader was throwing
  away the ones the files ship.** Godot's `generate_mipmaps` fails on a compressed image — "Cannot
  generate mipmaps from compressed image formats" — and the extension's reader returned only level
  0, on the written-down grounds that "Godot regenerates the rest more cheaply than they can be
  parsed out". It cannot. Every DXT texture in the project had exactly one level, and no filter
  makes a single 256×256 level look right on a wall 500 m away: Starling Island's distant brickwork
  aliased into speckle and its roofs dissolved into the sky. The authors stored the levels — 217 of
  that terrain's 248 DDS files carry a full chain, and `2af11UID-mc_tree1.dds` is an 87,536-byte
  file of which 65,536 bytes were being read. 429 compressed files across the checkout were
  affected.
- **It looked like a transparency fault and was a sampling one.** The first guesses were alpha
  scissor, a corrupt alpha channel, a material wrongly marked transparent — all of them wrong, and
  all of them plausible from the picture. What settled it was reading `dwMipMapCount` out of the
  file header and comparing it against what the reader returned, which is what
  `a_texture_keeps_the_chain_its_file_ships` now does on every DDS in the checkout.
- **An uncompressed file's header may claim a chain it does not contain.** The hero truck's
  `S1024.dds` declares eleven levels in a file exactly one level long. It does not matter for an
  uncompressed image, which can have its mipmaps generated, which is why only block-compressed
  files are held to their header.
- **An object definition is content like any other, and must be looked for the way all content
  is.** `.odef` lookup went to the terrain's own folder alone, and a map names a great many it
  does not ship: Port Starling places `road-slab` 189 times and `road-park` 139, plus signs,
  traffic lights and dock sections, every one of them in `resources/meshes`. That alone is why
  "some of the roads are visible and some are not".
- **A `.tobj` is not a list of buildings.** It mixes scenery with actor spawn points and with
  blocks of procedural road points, and upstream sorts them before anything else happens —
  `TObjFileFormat.cpp` reads each line as `odef`, `type`, `instance_name` with one `sscanf`
  (`"%f, %f, %f, %f, %f, %f, %s %s %s"`), then asks `IsRoad()` and `IsActor()` over its own name
  lists: `truck`, `truck2`, `load`, `machine`, `boat` are actors; `road`, `roadborderleft/right/
  both`, `roadbridge`, `roadbridgenopillar` are roads. Read as scenery, a road point asks for an
  object definition named `0`, `8` or `10`, and a marina asks for one named `marina sale
  Marina_Wells`.
- **Together those two cost 56% of Port Starling.** 835 of its 1502 placements drew nothing: 374
  road points inside `begin_procedural_roads` blocks, 8 actor spawns written with a type and an
  instance name, and the rest definitions the map names and does not ship. 1117 draw now, and the
  27 still missing are `2af11UID-mc_tree01`, whose `.odef` the tree pack does not contain while it
  ships `mc_tree02` through `mc_tree06` — upstream draws nothing for it either, `FetchODef`
  returns null.
- **A managed material's specular map is not always in the same slot.** `RigDef_Parser.cpp`:
  `mesh_standard` and `mesh_transparent` read it from argument 3, `flexmesh_standard` and
  `flexmesh_transparent` from argument 4, because a flexmesh carries a damaged diffuse between the
  two. Counted from the first texture that is slot 1 and slot 2. This project read 2 for both, so
  every `mesh_standard` material lost its specular map — 11 across this library, among them the
  hero truck's rims, steering wheel, tacho, speedo and flares, which drew as flat matte shapes.
  Reported as "the rims are just black plate caps": the rim texture really is near-black, 128 x 64
  of dark steel with two bolt heads, so the colour was right and the highlight was missing.
- **A mesh file can simply be truncated.** NhelensGrass's `a1da0UID-kwhale.mesh` declares 110,924
  bytes in its own M_MESH chunk and is 106,944 bytes long: 3,980 short. It reads as 988 shared
  vertices and no submeshes. That is a broken file, not a misread line, and the two look identical
  from the outside — which is why `every_object_line_is_read_as_what_it_is` counts them apart.
- **A specular map read for the first time is a specular map that has never been decompressed.**
  Putting `mesh_standard`'s specular map in the slot upstream puts it in meant those maps reached
  `roughness_from_specular` for the first time, block-compressed, and `get_pixel` on a compressed
  image returns black and logs "Can't get_pixel() on compressed image, sorry." — **per pixel**. A
  single 512-square map is a quarter of a million lines; one suite run wrote 72 MB of it and bash
  died collecting the output with `xrealloc: cannot allocate 18446744071562067968 bytes`, which is
  a negative 32-bit size cast to `size_t`. The derived roughness would have been uniformly wrong
  rather than absent, which no gate asking "is there a roughness texture" can see. Decompress
  first.
- **`beginbox` is the collision the author wrote down, and it was counted and thrown away.** Its
  `boxcoords` line is six numbers paired by axis — `minx, maxx, miny, maxy, minz, maxz` — so
  `road-slab.odef`'s `-5.01, 5.01, -3, 0.3, -5.01, 5.01` is a 10 m slab 3.3 m thick whose top is
  0.3 m above the object's origin. Collision for scenery was derived instead by voxelising the
  visual mesh into columns, discarding any column under half a metre as drawn detail rather than
  structure — right for wires and kerb lips, exactly wrong for a road, whose whole shape is flat.
  Every raised road on every map was drawn and not solid. Port Starling: 358 placements declare
  boxes, 357 of them solid, and its scenery went from 2365 solid parts to 4595.
- **A collision box is not in the mesh's frame.** Upstream turns an object's visual node by the
  placement rotation and then pitches it -90 degrees because object meshes are authored Z-up
  (`TerrainObjectManager::LoadTerrainObject`); the box gets the placement rotation and **no pitch**
  (`Collisions::addCollisionBox`). So `boxcoords` reads Y-up, which is the only way `road-slab`'s
  `-3 .. 0.3` is a thickness rather than a 10 m wall. The header scale multiplies the coordinates
  in the box's own axes before the rotation — upstream's `coll_box.relo = l * sc`.
- **A `virtual` box is an event zone, not a solid.** Every solid response upstream is gated on
  `!cbox->virt`. Port Starling declares 31 of them and Russia 8, all of them spawn and sale zones,
  and making them solid would put invisible walls across the map.
- **A drop test has to land on the middle of what it is testing.** The first run of
  `a_raised_road_holds_a_vehicle_up` dropped the truck on the placement's origin, which on a crane
  whose box starts a metre away left most of the rig hanging over the edge, and read as 0.91 m of
  penetration into a box that was working perfectly. Dropped on the box's own centre it rests at
  exactly the declared top — the same figure, to a centimetre, as it rests on open ground.
