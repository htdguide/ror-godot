class_name ValleyLayout
extends RefCounted
## The layout of Valley One, as data: where every feature is, in metres of world space.
##
## PLAN §0.5 requires the scene to be built from a declarative layout rather than placed in an
## editor, so that a visual change is a text diff. This file is that layout. It holds no
## building and no maths: `ValleyShape` turns these numbers into a heightmap and a surface map,
## `ValleyTerrain` imports them, and the water and vegetation passes read the same numbers so
## that a shoreline and a riverbed cannot disagree about where the water is.
##
## Axes: +x runs along the valley, +z across it. The rig spawns at the origin, which is why the
## test track sits there and every feature is placed away from it.
##
## Heights are metres above the world origin and are negative at the lake end: the valley
## drains west, so the floor descends away from the spawn point in that direction.

## --- The across-valley profile -------------------------------------------------------------
##
## Four bands either side of the centre line: a flat floor carrying the surface lanes, a
## shoulder, a wall, and the ridge above it. The wall is where the climbing road is benched, so
## its slope is a *constant* 24% over most of its height rather than the quadratic curve a
## simple valley generator gives. A quadratic wall is gentle at the toe and near-vertical at
## the top, which spaces a contour road's switchback legs 100 m apart at the bottom and 10 m
## apart at the top: the legs collide with each other before the road reaches the ridge.

## Half the width of the flat floor. Nine surface lanes at 20 m each.
const FLOOR_HALF_WIDTH_M: float = 90.0
## The shoulder runs from the floor edge to here, rising quadratically so it leaves the floor
## tangentially instead of at a crease the suspension would read as a kerb.
const SHOULDER_END_M: float = 130.0
const SHOULDER_RISE_M: float = 2.5
## The wall runs from the shoulder to here at WALL_GRADE, with a rounded toe.
const WALL_END_M: float = 610.0
const WALL_GRADE: float = 0.24
## Over how much of the wall's start the grade eases in from the shoulder's slope.
const WALL_TOE_M: float = 40.0
## Above the wall: a plateau, so a camera on the ridge has somewhere to stand.
const RIDGE_UNDULATION_M: float = 3.0
const RIDGE_WAVELENGTH_M: float = 220.0

## --- The along-valley profile --------------------------------------------------------------

## The test track: flat except for the ripple, and the only part of the valley that is. The
## driving gates spawn inside it, so its shape is deliberately unchanged from the track that
## came before Valley One had features.
const TRACK_WEST_M: float = -250.0
const TRACK_EAST_M: float = 350.0
## Outside the track the floor falls to the west and climbs to the east, so the lake end is the
## low end and the rock traverse is the high one. 2% is a road grade: drivable in any gear.
const VALLEY_GRADE: float = 0.02
## Gentle undulation along the floor, so it is drivable but not a table.
const RIPPLE_HEIGHT_M: float = 1.2
const RIPPLE_WAVELENGTH_M: float = 90.0

## --- The climbing road, benched into the north wall ----------------------------------------
##
## Control points across the wall, in metres, as (x, z). The road's *height* is not declared:
## it is the wall's own height at the point on the centre line, which makes the road a contour
## traverse by construction, so its cut and fill are bounded by the corridor width times the
## wall grade — about 1.2 m — instead of being whatever the numbers in a table happened to say.
## The grade the road actually achieves is therefore a property of this path, and
## `road_is_drivable` measures it rather than trusting it.
const ROAD_POINTS: Array[Vector2] = [
    Vector2(320.0, -130.0),
    Vector2(-160.0, -250.0),
    Vector2(-196.0, -262.0),
    Vector2(-160.0, -274.0),
    Vector2(320.0, -394.0),
    Vector2(356.0, -406.0),
    Vector2(320.0, -418.0),
    Vector2(-160.0, -538.0),
    Vector2(-196.0, -550.0),
    Vector2(-160.0, -562.0),
    Vector2(300.0, -592.0),
    Vector2(340.0, -598.0),
]
## A lane and a half: wide enough to turn a truck in a hairpin, narrow enough that the bench
## cut into the wall stays shallow.
const ROAD_HALF_WIDTH_M: float = 5.0
## Outside the corridor the road blends into the wall over this distance.
const ROAD_BLEND_M: float = 6.0
const ROAD_SURFACE: String = "gravel"

## --- The river, the ford and the lake -------------------------------------------------------
##
## The river crosses the valley floor, which is what makes the ford a crossing rather than a
## decoration: driving the length of the valley means driving through it. It then drains west
## along the floor's north edge into the lake at the low end.

## Where the crossing channel cuts the floor, and how wide it is.
const RIVER_CROSS_X_M: float = -400.0
const RIVER_CROSS_HALF_WIDTH_M: float = 22.0
## How deep the channel is away from the ford.
const RIVER_DEPTH_M: float = 2.6
## The ford: the shallow band a vehicle crosses at, and how far the bed ramps up into it.
const FORD_HALF_WIDTH_M: float = 14.0
const FORD_DEPTH_M: float = 0.7
const FORD_RAMP_M: float = 10.0
## The drain, running west from the crossing to the lake along the floor's north edge.
const DRAIN_Z_M: float = -70.0
const DRAIN_HALF_WIDTH_M: float = 15.0
const DRAIN_DEPTH_M: float = 2.2
const RIVER_SURFACE: String = "sand"

## The lake fills the west end. Its shore ramps from here down to its floor.
const LAKE_SHORE_X_M: float = -760.0
const LAKE_FLOOR_X_M: float = -900.0
## How far the basin is dug below the valley floor. The lake ends up deeper than this, because
## the floor it is dug into is itself descending at VALLEY_GRADE while the water is flat.
const LAKE_DEPTH_M: float = 6.0
## Water is flat, so its level is one number rather than a function of x, and the number is the
## valley floor's own height at the shore: the shoreline then lands exactly where the basin
## starts, and the floor's ripple gives it a wobble instead of a drawn straight line.
const LAKE_WATER_Y_M: float = -10.2
## The river is a stream rather than a body: its surface follows its bed at this depth, so the
## ford is crossable by construction and the water pass has one number to build both from.
const RIVER_WATER_DEPTH_M: float = 0.35

## --- The washout, and the rock traverse -----------------------------------------------------

## Transverse corrugations across the floor: the suspension-articulation section. The
## wavelength is chosen to be near the wheelbase, which is the case that pitches a vehicle
## instead of merely shaking it.
const RUTS_WEST_M: float = 380.0
const RUTS_EAST_M: float = 620.0
const RUTS_AMPLITUDE_M: float = 0.16
const RUTS_WAVELENGTH_M: float = 7.0
## The corrugations fade in and out over this distance, so neither end is a step.
const RUTS_FADE_M: float = 20.0
const RUTS_SURFACE: String = "gravel"

## An off-camber shelf cut into the south wall: the articulation close-up, where one side of
## the vehicle is always higher than the other.
const ROCK_WEST_M: float = 650.0
const ROCK_EAST_M: float = 950.0
const ROCK_INNER_Z_M: float = 140.0
const ROCK_OUTER_Z_M: float = 300.0
## The shelf's crossfall. Off-camber enough to load one side of the suspension, well short of
## the 1.18 g the hero rig rolls over at.
const ROCK_CROSSFALL: float = 0.12
## Bumps on the shelf, so it is rock rather than a ramp.
const ROCK_BUMP_M: float = 0.35
const ROCK_BUMP_WAVELENGTH_M: float = 11.0
const ROCK_SURFACE: String = "rock"

## --- What the walls and the ridge are made of -----------------------------------------------

const WALL_SURFACE: String = "rock"
const RIDGE_SURFACE: String = "grass"


## Named places, for cameras and for scenarios to drive between. A money shot names an anchor
## rather than carrying coordinates of its own, so moving a feature moves its shots with it.
##
## Each is {"position": Vector3, "look_at": Vector3}; y is metres above the terrain at that
## point, resolved by the caller, because the terrain's height is the shape's business.
const ANCHORS: Dictionary = {
    "spawn": {"position": Vector3(0.0, 2.0, 0.0), "look_at": Vector3(60.0, 1.0, 0.0)},
    "ridge_vista": {
        "position": Vector3(320.0, 12.0, -640.0), "look_at": Vector3(0.0, -6.0, 0.0),
    },
    "switchback": {
        "position": Vector3(80.0, 14.0, -300.0), "look_at": Vector3(-60.0, 8.0, -215.0),
    },
    "ford": {"position": Vector3(-360.0, 4.0, 40.0), "look_at": Vector3(-400.0, 0.0, 0.0)},
    "lake": {"position": Vector3(-700.0, 8.0, 120.0), "look_at": Vector3(-900.0, -9.0, 0.0)},
    "ruts": {"position": Vector3(470.0, 3.0, 60.0), "look_at": Vector3(500.0, 1.0, 0.0)},
    "rock_traverse": {
        "position": Vector3(800.0, 22.0, 90.0), "look_at": Vector3(800.0, 26.0, 220.0),
    },
}
