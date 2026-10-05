# Hard-won facts: terrains and the world they describe

Audience: a contributor or agent working on how a Rigs of Rods terrain is read and built.

What a terrain ships is not only a heightmap. It is object definitions, object lists, collision
the author wrote down, splat maps, and roads described as a line of points — each its own format,
each with a convention that is obvious once it is known and invisible until then. Everything here
was paid for once.

Its companion is `hard-won-facts-mods.md`, which covers how a vehicle is read, built and drawn.

- **`beginlodmesh` is distance geometry the terrain's author already made, and upstream throws it
  away.** A block of `<distance>, <mesh>` lines says which mesh to draw from how far: Starling
  Island ships twelve across ten objects — firehouse, police department, hospital, three stores,
  office block, warehouse, bus stop and a road sign — and every one of them is on the disk.
  Upstream's current parser reads the block and does nothing with it, so nobody has drawn them for
  years. The header mesh is drawn to the first stated distance, each level from its own to the
  next, the last to the horizon, and 7788 triangles go at the furthest level.
- **Eight of those levels are no simpler than the mesh they stand in for.** A fact about the
  content rather than about the loader, so `an_object_draws_its_own_distance_mesh` counts them
  instead of failing: a level that costs more than it saves is the author's decision to have made.
- **`.odef` files are CRLF.** Chasing the LOD meshes, a shell `[ -f ]` test reported eleven of the
  twelve as missing — the names carried a trailing `\r`. The readers here strip it and the gates
  prove they do, but a one-off check that does not will lie, and it very nearly got recorded as a
  fact about the content.
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
- **A blend map is a gradient and was being read as a classification.** Ogre hands a terrain's
  splat map to the GPU, which filters it; this project read the nearest pixel, so the map's own
  resolution became hard edges on the ground. La Paz's is 1024 squared over 4000 m — 3.9 m a pixel
  with full 0-to-1 steps between neighbours — against a lattice spacing of 1.95 m, so a boundary
  moved the whole way in one vertex. Bilinear halves that, and `a_blend_map_is_a_gradient` bounds
  it by arithmetic over the terrain's own two numbers: the largest step between neighbouring
  pixels times (vertex spacing / metres per pixel). Nothing in that bound is a number this project
  chose. A terrain's **traction** map is still read nearest and should be: it names which ground
  model is underfoot, and halfway between gravel and asphalt is not a surface.
- **That is not what makes Starling Island's hillsides look terraced.** Measured rather than
  assumed, and the first guess was wrong: its blend map is 64 by 64 but reads r = 1.00 in every
  pixel, so there is no boundary in it to be blocky. Its heightmap is not quantised either — 483
  distinct heights over 600 samples along one line, with steps down to 15 mm. What is left is the
  terrain's own layer 0, `starling.dds`, a 2048-square aerial photograph of the island stretched
  over 3000 m at 1.46 m a texel. Unproven, and the next thing to measure.
- **A composite is not bounded the way its source is.** A first draft of that gate measured
  *coverage* rather than the map as it is read, and failed La Paz: Ogre multiplies each layer's
  weight through what the layers above it left, so with four layers one layer's share can move
  faster than any single channel did. The smoothness that matters is the source's, and everything
  downstream inherits it.
- **A `begin_procedural_roads` block is a line of cross-sections, not a list of objects.** Each
  line is ten fields — `ProcessProceduralLine`: position, rotation, carriageway width, border
  width, border height, and a kind (`flat`, `left`, `right`, `both`, `bridge`, `monorail`) — and
  upstream sweeps the section along the line into one mesh drawn with the single material `road2`,
  whose texture is an atlas with a band for each part of the section. Eight points make the
  section; the road runs along the point's local x and the section spans its local z. Port
  Starling describes 374 of its 1502 object lines that way, which is most of its road network,
  and all of it was missing. 351 points in 50 blocks build 3976 triangles there, and 23,712
  across the library once bridges and monorails are built too.
- **A shoulder's foot is pinned to the ground, not to the road.** `baseOf` puts it on the
  heightmap, or just under the road where the road already sits below ground, so a road laid over
  a dip closes itself against the terrain instead of floating over it.
- **The first sweep came out face-down on all 1638 of its horizontal faces.** Ogre's quad winding
  is the reverse of what Godot draws front-facing, the same way a mesh file's is. A carriageway
  wound the other way is invisible from the only place anybody looks at it from, and nothing
  errors. `a_road_of_points_is_swept_into_a_road` checks the sign of every near-horizontal face
  for that reason, and checks every vertex against the half-width its own points state, which is
  the bound that catches a sweep landing somewhere else: shifting the section 40 m sideways
  reports "a vertex sits 40.2 m from the line its points describe, over the 9.0 m their own
  widths allow".
- **107 of Port Starling's road lines state a width of 0.** With a 2 m border either side,
  upstream's cross-section collapses the carriageway to a line and draws two 2 m strips: it is a
  footpath, written in the road format. Collision built from the carriageway alone gave those a
  box of no width at all, and the drop test landed 14 m under a deck it should have rested on.
  The box spans the section's outer edges instead, which covers the carriageway and its kerbs
  together, with its top at the carriageway's own height — a kerb is something a wheel rides
  over, and a box as tall as one would hold a vehicle up at its lip.
- **A road point is not a road.** A block's outermost point, or one whose neighbours are kinds
  this does not build, has no carriageway through it. A drop test that picked the highest *point*
  landed on a jetty's end 135 m from the nearest road and reported the road as not solid; it
  picks the highest **segment** now, which is two points and therefore a thing that exists.
- **A bridge and a monorail are the same sweep with a floor.** Their outer points drop to a wall
  rather than to the ground — 0.4 m for a bridge, 1.4 m for a monorail, whose deck also sits two
  metres above the points that describe it — and the segment carries an underside as well as two
  walls. Without the floor the deck is a sheet seen from below and the map has a hole in it.
- **Upstream counts pillars in a file-scope `static int`.** It builds one column per raised
  segment, leaning to whichever side the ground is higher on where the column is short enough for
  that to matter, standing in the middle where it is tall, and as wide as it is tall over thirty.
  A monorail's is thin, central, built one segment in five, and skipped where it would stand over
  20 m. The every-fifth counter is per road here rather than per process, because `static_state`
  refuses the other kind — and per road is the behaviour anybody would have expected anyway.
- **`trees` is a vegetation keyword and this project did not know it.** Six `.tobj` lines across
  the whole library go unread; three are upstream's debug `grid`, one a collision-triangle count,
  and the other two are Russia's forests: `trees 0, 360, 0.07, 0.09, 1, 100, 800, fir06_30.mesh
  none Russia-TreeMesh.png` and the same for `fir14_25.mesh`. Both meshes and the density map were
  always on the disk. That terrain has been a bare hillside for want of one word in a list of two,
  and the two lines come to **14,090 trees**.
- **The line is mixed-format, which is probably why it was missed.** Seven comma-separated numbers
  — yaw from and to, scale from and to, high density, min and max distance — and then the file
  names space-separated after them, read by upstream in a single `sscanf`. A comma split alone
  gives eight fields, the last of which is three filenames in a trench coat.
- **Placement is a 10 m grid, not a scatter over the map.** `TerrainObjectManager::ProcessTree`
  walks the grid, asks the density map how much grows at each cell, and drops that many trees
  inside it; a *positive* grid spacing means one tree per cell at its centre where density is over
  0.8, and a negative one means the scatter on a grid of that size. The distances on the line are
  what the forest is drawn to — Russia says 800 m — so no visibility range had to be invented for
  them.
- **A position decides its own tree.** Yaw and scale are hashed from where the tree stands, so a
  terrain is identical on a second build and `no_global_random` has nothing to object to. The two
  species carry different salts; without that they land on exactly the same spots, because they
  share a density map and a grid.
- **A gate that skips when nothing is built is not a gate.** The first draft of
  `a_terrain_grows_the_forest_it_paints` decided there was nothing to judge from the number of
  trees it found, so halving the density made it grow zero and report "skipped". It decides from
  what the terrain asks for now, which is the number that does not move when the builder breaks.
- **A visibility range is measured to the node, not to the instance.** Godot takes the distance
  from the camera to a `GeometryInstance3D`'s own origin and applies it to everything that node
  draws, so a `MultiMeshInstance3D` left at the world origin with its instances scattered across a
  3 km map is judged by how far the camera is from (0, 0, 0). Adding the `beginlodmesh` distance
  meshes put a range on every batch of every object that declares one, and those buildings were
  then drawn only within 100 m of the map's corner. Reported from a window as "some of the
  buildings are still missing", one commit after a gate had confirmed each of those ranges was
  exactly the distance its definition states. **The range was right and it was being measured from
  nowhere.** A batch stands at the centroid of its own instances now, which also fixes the frustum
  test and the sort order, both of which were being computed from the same wrong point.
- **A gate that checks a number is not a gate that checks the number means something.**
  `an_object_draws_its_own_distance_mesh` passed throughout that fault and was not wrong to: every
  range it inspected was the one the content asked for. `a_batch_stands_among_its_own_instances`
  is the other half — every batch's node inside the bounding box of what it draws, which is true
  by construction when the batch is built right and 1326 m false when it is not.
- **The mesh reader reverses every triangle, and that is right for a vehicle and wrong for a
  building.** `OgreMeshReader::read_submesh` flips the winding, with a note admitting the reason
  has never been isolated: in file order a truck is culled from outside and drawn from inside, so
  something between the reader and the drawn pixel mirrors the geometry. A terrain object passes
  through no such path — `transform_of` is a rotation and a positive scale — so the same reversal
  draws every building inside out. Measured: after the reader, **0.0% of `store08.mesh`'s 160
  triangles agreed with the normals its own file carries**, and the same for `warehouse01` and
  `firehouse`. Reported from a window as walls visible from one side only. Objects are wound back
  where they are built; the real repair is to isolate the mirror in the vehicle path and stop
  reversing at all.
- **"Does it face away from its own centre" is not a facing test.** It is meaningless for a
  sidewalk, a helipad or a road slab, which is a third of a terrain's objects, and a first
  attempt at this measurement flagged all of them. The normals the file carries are the oracle:
  the author stored a facing per vertex and the winding either agrees with it or does not.
- **Real content disagrees with itself by up to 18%.** 9 of 470 object meshes carry between 8%
  and 18% of their triangles wound against their own normals — `lapaz-pole.mesh` worst — and that
  is how their authors left them. So `an_object_is_wound_the_way_its_file_is` asks for a majority
  rather than for all of them: the fault it guards is wholesale, every triangle reversed, and half
  is the only line that separates the two cases without keeping an exception list.
- **Ogre scripts are written with tabs as often as spaces.** `texture\tRussia-Grass1.png` split on
  spaces is one word, matches no keyword, and the material silently has no texture: three of
  Russia's vegetation materials declared one apiece and this project found none of them, which is
  "the grass is still white textures". The same fault had already been found and fixed once that
  day in a gate's own row reader, and not in `OgreMaterial`.
- **Winding is settled by geometry, not by normals, and the content is not consistent.**
  Un-reversing every object mesh is right for 79 of Port Starling's 90 and wrong for four:
  `store02`, `haus3`, `firehouse` and `haus4` are authored the other way round **and their own
  vertex normals agree with it**, so a check against the normals passes them while from outside
  they are a hole. Reported from a window as "the outside texture is facing inside, from outside
  it looks transparent". The signed volume of a closed triangle soup — sum `a . (b x c) / 6` —
  says which way it winds without reference to any normal, and that is the divergence theorem
  rather than an opinion. 20 meshes across the library were inverted, Russia's `6a8cUID_hall`
  worst at -0.29 of its own box.
- **An inside-out mesh is inside out in both senses.** Turning its faces round without negating
  its normals leaves it drawn from the right side and lit from the wrong one. Both go together.
- **An open mesh encloses nothing in particular.** 54 of the library's object meshes — sidewalks,
  road slabs, signs, helipads — land near zero and are left exactly as their files have them. That
  is also why "do the faces point away from the object's centre" is not a facing test: it is
  meaningless for a third of a terrain's objects, and a first attempt at this measurement flagged
  every flat thing on the map.
- **A gate can check the wrong authority and pass.** `an_object_is_wound_the_way_its_file_is` was
  written against the normals the file carries, which is the right oracle for shading and the
  wrong one for culling, and it passed every one of the 20 inverted meshes. The fault was still
  reported from a window. Two gates now, one per authority.
- **Ogre states fog per pass, Godot states it per scene, and a terrain's backdrop depends on the
  difference.** A Rigs of Rods terrain paints its distance twice: once as haze, and once as a
  backdrop mesh — a horizon ring and a ground skirt standing ten kilometres out, with the
  mountains and the dust already painted into the texture. Those passes say so: `fog_override true
  exp 0.71 0.81 0.87 0.00001 2000 3000` is a density of one part in a hundred thousand, 9.5% fog
  where they stand. This project's haze is 0.0006, which is 99.8% at the same distance, so the
  backdrop was drawn as the fog colour and nothing else. `fog_override true` with nothing after it
  means the same thing — Ogre's default type is `none` — and nine passes in the library are
  written that way.
- **A backdrop fault reads as a sky fault.** La Paz's horizon ring is 10,070 m out and 1,250 m
  tall, so it is clipped away entirely until the far plane passes about 7.3 km. Reported from a
  window as "I can't see the sky with clouds on view distance 12000, it looks like there is a gray
  texture above me, and the more distance I set, the bigger is the gray thing; if I set 200 m view
  distance, I can't see it". Nothing was wrong with the sky, the clouds or the fog: a grey sheet
  was moving into the frame from ten kilometres away as the far plane reached it.
- **Those backdrops are objects, and a commented-out one stays commented out.** La Paz's `.tobj`
  places `lapaz-horizon` and `lapaz-base` and has `lapaz-sky` disabled with a leading `;`, which
  is one of the three comment markers Ogre and Rigs of Rods accept. The sky dome in that file is
  not content this project is missing.
- **A cell decides where a collision box is, not how big it is.** Rasterising a mesh into cells on
  the ground plane and making each cell a box gives every box the cell's own width, so a 0.1 m
  lamp post comes out a 0.7 m column — reported from a window as "the collision boxes are vertical
  and align with the signs, but too thick", and it was, by seven times. Keeping the extent of the
  geometry *inside* each cell, clipped to the cell so a triangle crossing four of them does not
  make all four as wide as itself, costs four floats per cell and takes La Paz's widest box from
  0.70 m to 0.10 m with the same 396 boxes.
- **Narrow boxes are only safe once the contact rule is right.** A tall thin box used to be a
  trap: a node pushed into one left by whichever face its velocity suggested, which on a thin box
  is usually the wrong one. `RorObstacles::contact` picking the nearest face a node can actually
  leave by is what made this change available at all, which is why it waited for it.
- **A cap that truncates is worse than a coarse cell.** Boxes are emitted in sorted cell order, so
  an object with more cells than `MAX_BOXES_PER_OBJECT` got its first 4096 and nothing after —
  one side of a building, cut off mid-way. `hospital` covered 43.7% of its own footprint with its
  boxes' centre 25.58 m from the mesh's; `warehouse01`, `policedepartment` and two dock corners
  sat exactly on the cap the same way. Reported from a window reviewing the overlay as "only
  pillars collision, not the house". Growing the cell until the object fits is the answer, and it
  is only available once each box hugs the geometry in its own cell: before that, a coarser cell
  meant a fatter box rather than fewer of them.
- **Judge an object's coarseness by the cell it needed, not the one it started with.** The guard
  that drops objects too coarse to approximate was reading `CELL_M`, so Starling's
  `8d25UID-chapel` — which reads as 1152 by 919 by 1355 m from 1348 vertices in 506 triangles, and
  needs a 4 m cell — passed it and produced a square kilometre of boxes.
