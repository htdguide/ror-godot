class_name CockpitCfg
extends RefCounted
## The driver's own instruments and where the driver sits. Tunables only.
##
## The gauges are drawn by this project rather than taken from the mod. The hero truck's dials are
## painted into its dashboard texture — `S10speedoOR.dds`, `S10tachoOR.dds` — with no needle mesh
## and no animator rows, which is how upstream's own renderer gets away with drawing them: it has
## a dashboard overlay of its own. So a cluster is built here, in the cab, from the dashboard
## prop's own frame, and it is 3D geometry in the world rather than an overlay on the screen —
## which is what makes it move with the truck, tilt with it, and be lit by what lights the cab.

## Where the cluster sits, relative to the dashboard prop's own frame, in metres.
const OFFSET_M: Vector3 = Vector3(0.0, 0.10, 0.26)
## Turned to face the driver: the dashboard's frame is the prop's, and the driver is behind it.
const TILT_DEG: Vector3 = Vector3(-14.0, 0.0, 0.0)
## Dial size and spacing.
const DIAL_RADIUS_M: float = 0.075
const DIAL_SPACING_M: float = 0.185
const DIAL_DEPTH_M: float = 0.012

## The sweep of a needle: where zero sits and how far the needle travels, measured clockwise from
## the top of the dial. A car's dials sweep about 240 degrees from lower left to lower right.
const SWEEP_START_DEG: float = -120.0
const SWEEP_DEG: float = 240.0
## What the ends of each dial mean.
const TACHO_MAX_RPM: float = 6000.0
const SPEEDO_MAX_KMH: float = 160.0

## Colours. Dark faces with a light needle: the cab is a dark place and a gauge has to be legible
## in it without being a lamp.
const FACE_COLOUR: Color = Color(0.06, 0.06, 0.07)
const RIM_COLOUR: Color = Color(0.18, 0.18, 0.19)
const NEEDLE_COLOUR: Color = Color(0.86, 0.22, 0.16)
const TICK_COLOUR: Color = Color(0.62, 0.62, 0.60)
const WARNING_COLOUR: Color = Color(0.92, 0.55, 0.12)
## How brightly the faces glow when the lights are on, and when they are not.
const BACKLIGHT_ON: float = 1.4
const BACKLIGHT_OFF: float = 0.0
## How many ticks are drawn around a dial.
const TICK_COUNT: int = 9
const TICK_LENGTH_M: float = 0.016
const NEEDLE_WIDTH_M: float = 0.004

## The driver's eye. A rig declares several cinecams and only some are in the cab; the hero
## truck's second is the driver's, so this is an index into the file's own list with a fallback.
const DRIVER_CINECAM_INDEX: int = 1
## Nudges the eye from the cinecam itself: upstream's cinecam is where the camera hangs, and a
## driver's head is a little above and behind it.
const EYE_OFFSET_M: Vector3 = Vector3(0.0, 0.06, 0.10)
## How far the view may be turned by the mouse before it stops, in degrees: a driver can look
## around the cab but not through the seat.
const LOOK_YAW_LIMIT_DEG: float = 120.0
const LOOK_PITCH_LIMIT_DEG: float = 60.0
## The field of view from the driver's seat. Narrower than the chase camera's, because a cab is
## close quarters and a wide lens makes it look like a bus.
const FOCAL_MM: float = 30.0
