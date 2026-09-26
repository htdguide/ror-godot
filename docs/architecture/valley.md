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

## The water

    world/valley_water.gd   the lake, the crossing and the drain as meshes
    config/water_cfg.gd     what water looks like
    shaders/water.gdshader  depth fade and ripples

The surfaces come from `ValleyWaterCut`, which also carved the bed, so the water and the ground
under it cannot disagree about where the shoreline is.

**The river's surface is derived, not declared.** It is the valley's own profile — without the
ripple — less the ripple's amplitude and a freeboard, so it sits under the lowest the ground gets
at every point and descends wherever the valley does. Two declared versions came before it and
both were wrong in ways that read as reasonable numbers in a layout file. A constant-depth cut
follows the floor down from the shoulder and back up, so the surface humps and the water runs
uphill into the ford. Elevations interpolated between an inlet and a junction descend smoothly
while the floor around them descends faster, so the river climbs out of its channel and lies in a
sheet over the valley floor — which is what the ford's first rendering showed: a 44 m wide pane of
water over dry ground. `water_runs_downhill` is the gate for both.

The ford is a bar: a rise in the bed toward a surface that is still descending. Its depth is
declared, the bed follows from it, and the river begins at zero depth at its inlet so that the
mesh thins out instead of ending at a straight edge in the open.

Two details of the meshes matter. The depth of the water under each vertex is baked into the mesh
as vertex colour and the shader fades the surface out with it — as a *fraction* of the fade
depth, because vertex colour is eight bits a channel and a depth baked in metres is clamped at one
metre, which drew an 11 m lake as shallows. And the meshes extend past the shoreline, under the
ground: trimming a water mesh to its own shoreline is the obvious thing to do and it shows an edge
as soon as the ripples move, because the ground is what hides the water.

Refraction and reflection are M6's work; this surface is the staged one PLAN §0.5 asks for, and
M8 replaces its generation behind the same interface.

## What grows on it

    world/valley_vegetation.gd   conifers and shrubs: meshes, placement, multimeshes
    config/vegetation_cfg.gd     species, density, and the rules about where anything may grow

Placement is a pure function of position. Each cell of a 6 m grid is hashed, and the hash decides
whether something grows there, which species, how big and which way it faces — no random number
generator and no stored list, so the valley grows the same forest on any machine and a gate can
check a plant by recomputing it rather than by trusting a record of what was planted.

The rules are applied where a plant *stands*, not at the centre of its cell. The jitter that keeps
a forest from reading as a lattice is up to half a cell, which is enough to put a tree inside the
road clearance it was checked as being outside of — measured, and it is what
`vegetation_obeys_its_rules` caught first.

**This does not use `Terrain3DInstancer`, which PLAN §0.6 named for scattering.** The instancer
stores instances inside Terrain3D's region files, which are what `ValleyCache` keeps between runs:
the forest would become cached data rather than a consequence of the layout, and the cache's
verification only samples heights. It also wants a `PackedScene` per species, which means assets
on disk, where the CLI-only rule prefers generated. One multimesh per species, built from the
placement function, keeps a single source of truth and costs one draw call each.

The conifer stand is a feature with a place in the layout, because two money shots are lit through
it: `valley_vista` has the sun behind it and `switchback_backlit` shoots the climbing road through
it. Measured, it holds 143 conifers a hectare against 8.4 in the rest of the plantable valley.

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

    tools/valley_shots.sh

renders the seven named places and tiles them into `artifacts/valley-sheet.png`, which is what a
human session is run from. The views are numbered so a person can point at one, and they are named
after the anchors in the layout, so moving a feature moves the view that frames it.

The gates that hold it: `valley_has_its_features` (each feature exists at a size worth
photographing), `road_is_drivable` (the road is continuous, wide enough, and no steeper than the
rig's traction), `water_runs_downhill` (the river descends, stays in its channel and meets the
lake), `water_is_drawn` (the lake renders and fades with depth rather than being a flat slab),
`vegetation_obeys_its_rules` (every plant on the ground, off the road, out of the water, and a
stand that is denser than the valley around it),
`valley_photoset` (every named place has a world in frame), `terrain_collision_agreement` (the
solver and the renderer agree about the ground), `rig_settles_on_terrain`,
`surfaces_are_visible`, and the three drivability scenarios — `ford_crossing`, `rut_traverse`
and `switchback_climb` — which drive the features rather than measuring them.

## Driving it

    harness/drive_route.gd     the driver: steer at the next waypoint, hold a speed, change gear
    harness/drive_scenario.gd  terrain, rig, spawn, handover
    world/valley_routes.gd     the three routes, derived from the layout

PLAN M1 acceptance 7 asks for three scenarios completed without the actor falling through the
terrain, getting stuck or exploding, with solver energy bounded. Those are four different failures
and the driver watches for all four, reporting numbers rather than a verdict: each gate decides
what its own route was supposed to do.

Two details are load-bearing. The fall-through check measures the rig against the terrain the
*renderer* draws, not against the heightfield the solver was handed — asking the solver whether
its own ground is where it thinks it is cannot fail, and a heightfield handed over five metres low
was driven quite happily until the check was changed. The same check looks for the rig floating
above that ground, held for a couple of seconds so that a wheel lifting over a crest does not
count.

The spawn heading is measured rather than assumed: the rig is placed at two known headings, its
own heading is read back, and the placement angle that points it along the route is solved from
those. A guess at the convention sent it 431 m down the valley away from its first waypoint.

## Still to come

The PBR ground material via `res://shaders/terrain3d_override.gdshader`, and vegetation tiers 2
and 3 — the rest of the M2 staging in PLAN §0.5. The
valley's shaded walls currently render near-black under `noon_clear`: the sky does light them,
measured with the sun turned off, but AgX at the project's exposure crushes what it gives them.
That is the tonemap and exposure work in M2b rather than a terrain fault, and it is why four of
the seven views in the sheet are dark.
Real elevation data replaces the generator through `tools/import_dem.gd` when it arrives; the
seam is the same either way, because everything downstream reads heights from Terrain3D rather
than from the generator.
