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

## Where the cluster sits, and how it is found.
##
## Three attempts, and the first two are worth writing down because each was wrong in a
## different way. An offset in the *dashboard prop's* frame is an offset in no direction a person
## can name — the hero truck turns that prop by -95, 0, 180 degrees — so the dials ended up in
## the driver's face. Measured from the driver's eye instead, the direction was right and the
## distance was not: an eye is a cinecam, which hangs where a camera hangs, and a session
## reported the dials "flying in the air". And the dashboard prop's own mesh turns out to be a
## 0.8 mm placeholder on this rig — its dashboard is painted into the cab — so there is no
## dashboard surface to sit on either.
##
## What there is, on every rig with a cab, is the steering wheel. So the cluster goes just ahead
## of it, and its height is chosen so that the dials sit this far below the driver's sightline:
## a glance rather than a look down. 16 degrees against a 44 degree lens puts them 86% of the way
## down the frame — low, and in it.
const GLANCE_DEG: float = 16.0
## How far ahead of the steering wheel's own front face the dials stand.
const DIALS_AHEAD_OF_WHEEL_M: float = 0.05
## And where they go on a rig with no steering wheel to measure from: from the eye, forward and
## down.
const EYE_TO_DIALS_M: Vector3 = Vector3(0.0, -0.20, -0.65)
## Tilted back to face the driver's eye rather than the windscreen.
const TILT_DEG: Vector3 = Vector3(-18.0, 0.0, 0.0)
## Dial size and spacing.
const DIAL_RADIUS_M: float = 0.062
const DIAL_SPACING_M: float = 0.150
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
const TICK_COLOUR: Color = Color(0.86, 0.86, 0.84)
const WARNING_COLOUR: Color = Color(0.92, 0.55, 0.12)
## How brightly the faces glow when the lights are on, and when they are not.
const BACKLIGHT_ON: float = 1.6
## Not zero: a dial has to be readable in daylight too, and the cab is a dark place at noon.
const BACKLIGHT_OFF: float = 0.35
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
