# Valley One

Audience: contributors working on the scene, the terrain, or anything that stands on it.

Valley One is the showcase scene and the only scene. It is 2.0 km square at a metre per terrain
vertex, generated from code every run, and it is where every milestone is judged. What it has to
contain and why is PLAN §0.5; the terrain layer it is built on is PLAN §0.6.

## The four files

    world/valley_one_layout.gd   where every feature is, in metres. Data, no maths.
    world/valley_shape.gd        the height and the surface at any point. Pure and static.
    world/valley_water_cut.gd    the parts of the shape the water dug: crossing, drain, basin.
    world/valley_terrain.gd      builds the Terrain3D, imports the maps, hands them to a solver.

The split is the point. The layout is reviewable as a text diff, which is what a CLI-only
workflow needs instead of an editor session. The shape is a function of grid coordinates with no
state and no seed, so the renderer, the solver's heightfield and every gate can ask it
independently and get the same answer — the heightmap Terrain3D draws and the surface map the
tyres grip on are two reads of one function, not two copies of a result.

Features compose in a fixed order: the valley profile, then what modifies the floor (the
washout, then the water cuts), then what cuts into a wall (the rock shelf, then the road). A cut
wins over what it cuts into, which is why the road is last.

## What is in it

The numbers live in the layout file and are not restated here. What matters structurally:

- **The test track** is the middle of the valley floor, level apart from the ripple, carrying nine
  surface lanes. It is deliberately the same track that existed before the valley had features:
  the driving gates spawn on it, so a hill under them would be measured as a solver fault.
- **The floor** falls west of the track and climbs east of it, so the lake is at the low end and
  the rock traverse at the high one.
- **The climbing road** is benched into the north wall as a contour traverse: its height is the
  wall's own height at the nearest point of the centre line, so the cut and fill are bounded by
  the corridor width times the wall grade rather than by a table of heights, and the grade it
  achieves is a consequence of the path. `road_is_drivable` measures it.
- **The wall's slope is constant** over most of its height instead of the quadratic curve a
  simple valley generator gives. A quadratic wall is gentle at the toe and near-vertical at the
  top, which spaces a contour road's switchback legs a hundred metres apart at the bottom and ten
  at the top: the legs collide before the road reaches the ridge.
- **The river crosses the floor** rather than running beside it, so driving the length of the
  valley means driving through the ford. It drains west along the floor's north edge into the
  lake.
- **The lake's water level is the valley floor's own height at the shore**, so the shoreline lands
  where the basin starts and the floor's ripple gives it a wobble rather than a drawn straight
  line. Water is flat; a river is not, so the river's surface follows its bed at a fixed depth.

## The cache, and why it is allowed to exist

Generating the valley is 4.2 M cells of GDScript: about 10 s of heights, 7 s of surfaces and 2 s
of painting, measured by `tools/terrain_cost_probe.gd` at several map sizes before the map was
grown to 2 km. Every gate that stands something on the terrain paid it, and so did every window
opened for a human session.

So `world/valley_cache.gd` keeps the built valley under `user://`, keyed by a hash of the files
that decide the shape. Terrain3D saves and loads its own regions; the surface map is written
beside them. Cold is about 22 s, warm about 2.5 s.

A cache is a golden artifact, which this project does not otherwise allow, so it is not trusted
on its key alone: a load samples the terrain against `ValleyShape` itself and one disagreement
throws the cache away and regenerates. That keeps the live function the authority. The negative
control for it — pinning the key, then changing the layout — is how the discard path was
checked, and `VALLEY_NO_CACHE=1` skips the load entirely.

## Where the solver gets its ground

`ValleyTerrain.give_to_solver` reads the terrain's own lattice through
`compat/terrain_heightfield.gd` and hands the solver the heights and the surface map together.
The grid is the terrain's, unresampled, because `terrain_collision_agreement` measures the two
against each other and any resampling here would show up there as a disagreement.

The surface map arrives as data rather than being generated in the bridge. Which surface is where
is a property of the world, and the pass that tints the terrain builds the map already: a second
copy computed in the bridge would be a second thing to keep in agreement, and it cost 7 s a run.
It is stored row by row — z outer, x inner — because that is the order the solver reads a
heightfield in. Stored the other way round the map is transposed, which reads as the right
surfaces in the wrong places.

## Measuring it

    godot --path game --headless --script res://tools/valley_probe.gd
    godot --path game --headless --script res://tools/terrain_cost_probe.gd

The first prints what the shape actually is, feature by feature: the road's grade leg by leg, the
ford's depth against the floor beside it, where the shoreline lands, the shelf's crossfall. The
second prints what a map of a given size costs to generate. A layout edit is reviewed by running
the first one, because every number a layout change moves is a consequence rather than a setting.

The gates that hold it: `valley_has_its_features` (each feature exists at a size worth
photographing), `road_is_drivable` (the road is continuous, wide enough, and no steeper than the
rig's traction), `terrain_collision_agreement` (the solver and the renderer agree about the
ground), `rig_settles_on_terrain` and `surfaces_are_visible`.

## Still to come

Water surfaces for the lake and the river, vegetation through `Terrain3DInstancer`, and the PBR
ground material via `res://shaders/terrain3d_override.gdshader` — the M2 staging in PLAN §0.5.
Real elevation data replaces the generator through `tools/import_dem.gd` when it arrives; the
seam is the same either way, because everything downstream reads heights from Terrain3D rather
than from the generator.
