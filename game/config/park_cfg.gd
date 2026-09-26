class_name ParkCfg
extends RefCounted
## The test park: a flat site with one segment per thing worth testing.
##
## It exists beside Valley One rather than instead of it. The valley is the showcase the plan is
## measured in; this is the workshop — flat, close together, and arranged so that a person can
## drive from one test to the next in seconds instead of crossing two kilometres of scenery.
##
## Everything here is metres in world space, and the origin is where the vehicle spawns.
##
## The ground is flat except where a segment deliberately is not: a heightfield can carry a
## washboard, a rut and a dip, and everything with a face — ramps, walls, kerbs, rocks — is a
## static box the solver contacts with the same ground law. See `world/park_props.gd`.

## --- The road ---------------------------------------------------------------------------------

## The main straight runs along x, through the spawn point. Wide enough to turn a truck on.
const ROAD_HALF_WIDTH_M: float = 6.0
const ROAD_WEST_M: float = -320.0
const ROAD_EAST_M: float = 320.0
const ROAD_SURFACE: String = "asphalt"
## What the site is made of away from the road and the segments.
const GROUND_SURFACE: String = "grass"

## Small squares of other surfaces let into the road, so grip changes under a vehicle that is
## already moving. One per surface, in the order they are laid out west to east, each this long
## along the road and as wide as the road is.
const PATCH_LENGTH_M: float = 14.0
const PATCH_GAP_M: float = 26.0
const PATCH_FIRST_X_M: float = -260.0
const PATCH_SURFACES: Array[String] = [
    "gravel", "sand", "ice", "snow", "metal", "rock", "concrete", "grass",
]

## --- The washboard, the ruts and the dips ------------------------------------------------------
##
## The shaped ground: the part of the park a heightfield can describe.

const WASHBOARD_WEST_M: float = 150.0
const WASHBOARD_EAST_M: float = 210.0
const WASHBOARD_AMPLITUDE_M: float = 0.07
const WASHBOARD_WAVELENGTH_M: float = 1.4

## A pair of ruts, one wheel track apart, for articulation at low speed.
const RUTS_WEST_M: float = 220.0
const RUTS_EAST_M: float = 280.0
const RUT_DEPTH_M: float = 0.28
const RUT_HALF_WIDTH_M: float = 0.45
const RUT_TRACK_M: float = 1.6

## Two bowls to drop a wheel into, and a hump between them.
const DIP_CENTRES_X: Array[float] = [-160.0, -120.0]
const DIP_RADIUS_M: float = 6.0
const DIP_DEPTH_M: float = 0.55
const HUMP_X_M: float = -140.0
const HUMP_RADIUS_M: float = 5.0
const HUMP_HEIGHT_M: float = 0.45

## How far outside a shaped segment its effect fades to nothing, so nothing is a step.
const FEATURE_FADE_M: float = 3.0

## --- The segments made of boxes ----------------------------------------------------------------

## The ramp yard, north of the road's west end. Each entry is [angle in degrees, width, length].
const RAMP_YARD_X_M: float = -240.0
const RAMP_YARD_Z_M: float = 40.0
const RAMP_SPACING_M: float = 26.0
const RAMPS: Array = [
    [8.0, 8.0, 14.0],
    [15.0, 8.0, 14.0],
    [22.0, 8.0, 12.0],
    [30.0, 8.0, 10.0],
]
## The split ramp: one side only, so one wheel climbs and the other does not.
const SPLIT_RAMP_ANGLE_DEG: float = 18.0
const SPLIT_RAMP_WIDTH_M: float = 2.2
## The kicker: short, steep, and there to leave the ground.
const KICKER_ANGLE_DEG: float = 14.0
const KICKER_LENGTH_M: float = 9.0

## The rock garden: boxes of assorted size and angle, for the suspension to work over.
const ROCKS_X_M: float = 180.0
const ROCKS_Z_M: float = 60.0
const ROCKS_ACROSS: int = 9
const ROCKS_ALONG: int = 7
const ROCK_SPACING_M: float = 5.0
const ROCK_MIN_M: float = 0.25
const ROCK_MAX_M: float = 0.85
const ROCK_SURFACE: String = "rock"

## The crash yard: things to hit. Each wall is [kind, x, z, width, height, thickness].
##
## Beam deformation and breaking are not implemented yet, so today these test how the rig's own
## structure responds to an impact and how the contact law handles a vertical face. When
## deformation lands they become its subject without moving.
const CRASH_YARD_Z_M: float = 120.0
const WALLS: Array = [
    ["block", -120.0, 0.0, 10.0, 2.4, 1.2],
    ["barrier", -60.0, 0.0, 12.0, 0.9, 0.4],
    ["kerb", 0.0, 0.0, 12.0, 0.18, 0.5],
    ["poles", 60.0, 0.0, 10.0, 2.6, 0.35],
    ["crates", 120.0, 0.0, 6.0, 2.4, 2.0],
]
## How many boxes a pole row and a crate stack are made of.
const POLE_COUNT: int = 6
const CRATE_ROWS: int = 3
const CRATE_COLUMNS: int = 3

## The skid pad: a disc of ice to lose the back end on, with a kerb ring around it.
const SKID_PAD_CENTRE: Vector2 = Vector2(120.0, -90.0)
const SKID_PAD_RADIUS_M: float = 34.0
const SKID_PAD_SURFACE: String = "ice"

## Named places, for a camera and for a person being told where to go. Height is metres above the
## ground at that point.
const ANCHORS: Dictionary = {
    "spawn": {"position": Vector3(-30.0, 9.0, 22.0), "look_at": Vector3(20.0, 0.0, 0.0)},
    "patches": {"position": Vector3(-210.0, 14.0, 30.0), "look_at": Vector3(-120.0, 0.0, 0.0)},
    "ramps": {"position": Vector3(-250.0, 16.0, 6.0), "look_at": Vector3(-190.0, 2.0, 48.0)},
    "dips": {"position": Vector3(-190.0, 12.0, 28.0), "look_at": Vector3(-135.0, 0.0, 0.0)},
    "washboard": {"position": Vector3(120.0, 9.0, 24.0), "look_at": Vector3(200.0, 0.0, 0.0)},
    "rocks": {"position": Vector3(170.0, 16.0, 35.0), "look_at": Vector3(210.0, 0.0, 78.0)},
    "crash_yard": {"position": Vector3(-30.0, 18.0, 80.0), "look_at": Vector3(40.0, 1.0, 125.0)},
    "skid_pad": {"position": Vector3(70.0, 22.0, -50.0), "look_at": Vector3(125.0, 0.0, -92.0)},
}

## --- How it is drawn ----------------------------------------------------------------------------

## Colours for the boxes, by what they are. Plain: the park is a workshop, not a showcase.
const PROP_COLOURS: Dictionary = {
    "ramp": Color(0.42, 0.40, 0.38),
    "block": Color(0.55, 0.54, 0.52),
    "barrier": Color(0.72, 0.62, 0.20),
    "kerb": Color(0.78, 0.30, 0.26),
    "poles": Color(0.64, 0.63, 0.61),
    "crates": Color(0.50, 0.36, 0.22),
    "rock": Color(0.36, 0.34, 0.32),
}
const PROP_ROUGHNESS: float = 0.9
