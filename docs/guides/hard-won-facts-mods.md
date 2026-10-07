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
- **A `submesh` is a body panel, and 18 of the 18 vehicles here declare one.** It is geometry with
  no mesh file behind it: its vertices *are* nodes, its triangles are `cab` lines over them, its
  texture coordinates come from `texcoords` lines, and it is drawn with the material the `globals`
  line names. Upstream builds a `FlexObj` per group. This project read the triangles for collision
  and drew none of it — for four vehicles that was the whole of their geometry (NhelensGrass's
  bridge and monorail, the Daf pack's two semi trailers) and for ten more it was bodywork missing
  from something that otherwise looked built. 405 drawn parts across the library became 573.
- **It deforms, so it is skinned like a flexbody.** A panel's vertices are the truck, so each one
  binds to the locator triad around the node it sits on — and because a vertex *is* a node, the
  binding is exact rather than nearest-fit. That is also the check worth having:
  `a_body_panel_is_made_of_its_own_nodes` requires every vertex to be within 1e-6 m of a node,
  which is float slack and not a tolerance. A panel built from the wrong nodes would look
  plausible.
- **`backmesh` means the panel is drawn from both sides.** A truck is looked at from inside its
  own load bed as well as from outside, and drawn one-sided the Daf trailers' walls vanish from
  within. The reversed copy is a second surface on the same mesh, so it costs one draw call and
  deforms with the first.
- **A cab with no texture coordinates is not a panel anybody meant to see.** The hero truck
  declares 242 cab triangles and the Mazda 187, both with zero `texcoords`: collision only, and
  upstream draws nothing for them either. Half a panel is worse than none, so a group with a
  triangle over a node that has no coordinates is dropped whole.

## Node numbers, and the order a file is spawned in

These four were learned together, the day the Mazda's hubcaps and every Gavril's tyres turned out
to be missing. They are one fact seen from four sides: **a file's layout is not the order it is
built in, and node numbers depend on the order it is built in.**

- **A numeric node reference is an index, not the number the node declared.** Upstream's
  `RegisterNode` throws a numbered node's own number away and keeps its order of appearance,
  warning about a duplicate if the two disagree; `ResolveNodeRef` then bounds-checks a numeric
  reference and returns it unchanged. Keying a lookup table on the declared number agrees with
  that on all 70 actors in this checkout — every one of them numbers from 0 with no gaps — and
  stops agreeing the moment a file does not, or the moment the reader drops a node row and shifts
  everything below it. A named node is the other case and keeps its name, because a name is the
  only way a file can reach it.
- **Upstream spawns keyword by keyword in a fixed order, and `ActorSpawnerFlow.cpp` is the order.**
  Declared nodes, then `cinecam`, then `wheels`, `wheels2`, `meshwheels`, `meshwheels2`,
  `flexbodywheels`, and only then everything that references a node — the file itself says
  `(may reference any generated/user-defined node)` over the beams. **30 of the 70 actors here
  write `props` or `flexbodies` above the wheel section those rows name**, so a reader that
  resolves a row where it finds it sees a node that does not exist yet and drops the row. That is
  the Mazda's four hubcaps and four brake discs, and all four tyres of every Gavril, which are
  flexbodies bound to wheel nodes. `TruckDocument` cuts the file into rows and hands them back in
  upstream's order.
- **A row's defaults follow the file even though spawning does not.** `set_beam_defaults` applies
  downwards from where it is written, so a row's rates must be captured as the row is read rather
  than looked up when it is built — upstream gives every parsed row a pointer to the defaults in
  force. Here the defaults object is replaced rather than mutated when a directive arrives, which
  is what lets the rows above keep what they were written with.
- **A cinecam is a node and eight beams, and skipping it shifts every generated node number.**
  Upstream's `ProcessCinecam` appends one node at the stated position and hangs it on eight beams
  to the nodes the row names, before any wheel node exists. The Mazda declares three cinecams and
  its hubcaps name node 332, which is the first rim node of its left front wheel **only once those
  three are counted**. The eight beams are not decoration either: a point mass with no member
  holding it is not part of the rig, it is something that falls out of it.
- **Sections upstream folds into another have to share one place in that order, not sit beside
  it.** `texcoords` and `cab` belong to the `submesh` above them. Given a place each, every
  `submesh` header sorted ahead of every `texcoords` row: 29 groups were opened and then all 210
  coordinates and 154 triangles landed in the last of them, so the Starling firetruck built one
  panel out of 29 and five more vehicles went the same way. The same applies to `flares` and
  `commands`, which upstream auto-imports into their numbered successors.
- **A `ties` row names one node, not two.** Upstream's `ProcessTie` takes the row's single root
  node, pairs it with node 0 — node 1 when the root *is* node 0 — and adds a rope beam it
  immediately disables: a tie does nothing until a player hooks it onto a ropable. Read as a
  two-node beam row the second field is the reach length, which is why 39 rows across this library
  reported an unknown node. The dangerous half is the row that would have *passed*: a reach
  written as a whole number resolves as a node index and welds the rig to it.
- **A generated beam needs its own entry in the stress tables, and an append-only array hides
  that.** The wheel generator set a spring and a damper and nothing else, so its beams had no
  deform or break figure. That was invisible for exactly as long as the tread was appended last,
  where a missing entry falls off the end of the array and the solver's own default stands in.
  Built where upstream builds it — ahead of the file's own beams — every one of those beams read
  the entry beside it instead: the hero truck's tyres came out with a 750 N yield and went flat
  against a wall at 2.4 m/s. A table with one row per beam is not optional bookkeeping.
- **An 8-bit luminance DDS is a specular map.** 37 of the 659 DDS files here are `DDPF_LUMINANCE`
  at 8 bits per pixel, and every one of them is a specular map: the map is one number per pixel
  and there is no reason to store it three times. Read as an RGB-masked file it has no
  byte-aligned green or blue mask and is rejected outright, so 94 of 287 declared specular maps
  never reached a material and those surfaces drew with their class's default roughness.
- **A wheel without its rigidity beams stands, settles, rolls, and folds the first time it is
  driven hard.** Every wheel row names a rigidity node (`9999` for none), and upstream ties one
  beam per ray from it to the ring on its side, typed `BEAM_VIRTUAL` — force like any beam, never
  drawn, no share of the mass. On a rigid axle the row names the far hub, and those beams are the
  wheel's whole camber stiffness: the axle's own nodes are collinear and a chain of collinear beams
  is a hinge. Built without them, the Burnside Drag's rear axle turned 40 degrees within 0.4 s of
  throttle and 80 by the end of the run — with the tyres' friction set to 0.1 as well as 1.95, so
  it was never the ground. 19 of 66 driveable vehicles folded; with the beams, one, and that one is
  a monorail whose guide wheels stand on vertical axles by design. Three earlier candidates were
  each measured and ruled out before this was found (reaction torque, gearing, yielding actuators),
  and bounding the tyre spokes fixed a real second fault without moving the lean at all. The tell
  was `fold_trace`: the lean arrived with the first 5 kNm, before any wheelspin, and did not care
  about grip. A fault that does not respond to the load is a stiffness fault.
- **A negative node number is that node, in a numbered file.** Upstream's `_ParseNodeRef` takes
  `node_id_num *= -1` in legacy import; the minus once meant "the other side" and now means
  nothing. It survives in the wild on exactly the field that stops a wheel folding: the Sprinter's
  and the Agora's left rear wheels name `-36` and `-65` as their rigidity node. Looked up as names,
  neither exists, so those were the only unbraced wheels on their rigs — and the only ones that
  folded, at 89 degrees, after every other wheel in the library was braced.
