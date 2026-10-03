# Hard-won facts: terrains and the world they describe

Audience: a contributor or agent working on how a Rigs of Rods terrain is read and built.

What a terrain ships is not only a heightmap. It is object definitions, object lists, collision
the author wrote down, splat maps, and roads described as a line of points — each its own format,
each with a convention that is obvious once it is known and invisible until then. Everything here
was paid for once.

Its companion is `hard-won-facts-mods.md`, which covers how a vehicle is read, built and drawn.

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
