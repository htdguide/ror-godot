class_name DriveCfg
extends RefCounted
## Everything tunable about driving a rig in the play window.
##
## The substep rate is the one number here that is not a preference: the solver needs it to
## stay stable on a real rig, and it is measured rather than chosen. See
## `solver_settles_vehicle` for what it currently is and why.

## Solver substeps per second: upstream's own rate. Measured rather than chosen — the hero
## rig diverges at 1.5 kHz and settles from 2 kHz up. See `game/tools/stability_probe.gd`.
const SUBSTEP_HZ: float = 2000.0
## A frame never steps more than this, so a stall in the window slows the simulation down
## instead of spending minutes catching up and locking the process.
const MAX_SUBSTEPS_PER_FRAME: int = 400
## How far above the ground the rig starts, so it drops onto its springs rather than
## starting inside them.
const SPAWN_HEIGHT_M: float = 0.05
## And how far above it a recovered rig is set down. Higher than a spawn, because a recovery
## happens wherever the vehicle rolled and the ground there may be uneven.
const RECOVER_CLEARANCE_M: float = 0.4

## Which way the driver's steering input goes.
##
## The solver's hydro law is upstream's and says nothing about which way is left: it shortens
## and lengthens the rams a rig's own file asks it to, and where that points the wheels
## depends on the handedness of the space the rig is described in. Measured on the hero truck,
## a positive command steers it to its own right, which is the third place this project's rig
## space has turned out to differ from upstream's by a handedness — after the steering wheel's
## 121 degree rake and the flare normals.
##
## So the project states its own convention — a positive intent means left — and converts
## once, here. Everything that steers goes through this, so the play window and the gates
## cannot disagree about it, which is how an inverted control reached a human session.
const STEER_INTENT_TO_COMMAND: float = -1.0

## How hard the driver's controls ramp. The steering ramp itself is upstream's and lives in
## the solver; these are the pedals, which upstream takes from an analogue axis.
const THROTTLE_RATE: float = 4.0
const BRAKE_RATE: float = 6.0

## Chase camera, in the vehicle's own frame: back, up, and where it aims relative to the
## actor origin.
const CHASE_OFFSET: Vector3 = Vector3(0.0, 2.0, 7.0)
const CHASE_AIM: Vector3 = Vector3(0.0, 0.8, 0.0)
## Fraction of the gap the camera closes each frame at 60 fps. Below 1 it lags, which is
## what makes a turn readable.
const CHASE_SMOOTHING: float = 0.15


## The keys the driver uses. Named so the help text and the handling cannot disagree.
const HELP: String = (
    "DRIVE  Up throttle, Down brake, Left/Right steer, Space handbrake\n"
    + "DRIVE  G drive, B reverse, H neutral, I ignition, N or L lights\n"
    + "DRIVE  R recover upright where you are, Backspace respawn at the start\n"
    + "DRIVE  Z/C indicators, X off, F5 chase camera, F6 free camera, F7 driver's seat"
)


## Turns "positive means left" driver intent into the command the solver takes.
static func steer_command(intent: float) -> float:
    return intent * STEER_INTENT_TO_COMMAND
