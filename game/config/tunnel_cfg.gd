class_name TunnelCfg
extends RefCounted
## The tunnel on the test track: a place where the sun stops and lamps take over.
##
## It exists to make lighting measurable while moving. Driving into it takes the scene from
## one directional light plus sky ambient to several local lights and no sky at all, and back
## out again, which is the transition that shows up shadow acne, ambient that is too flat,
## missing bounce light, and lights that do not travel with the vehicle properly.
##
## It is a lighting rig, not a structure: the solver collides nodes against the terrain and
## nothing else, so a vehicle drives through the walls. Mesh collision is a named gap.

## Along the valley, in metres. Long enough that the vehicle is fully inside with the ends far
## away, which is when sky contribution is actually gone rather than merely reduced.
const LENGTH_M: float = 70.0
## Wide enough for two of the surface lanes, so a driver can cross a surface boundary inside.
const WIDTH_M: float = 24.0
const HEIGHT_M: float = 7.0
const WALL_THICKNESS_M: float = 1.5
const ROOF_THICKNESS_M: float = 1.5
## Where its centre sits along the valley. Off to one side of the spawn point, so it is
## somewhere to drive to rather than something to start inside.
const CENTRE: Vector3 = Vector3(-90.0, 0.0, 0.0)

## Interior lamps, spaced along the roof.
const LAMP_SPACING_M: float = 14.0
const LAMP_HEIGHT_M: float = 6.2
const LAMP_ENERGY: float = 12.0
const LAMP_RANGE_M: float = 22.0
## Sodium-ish, so the change on the bodywork is a colour change as well as a level change and
## a white-balance error has something to show up against.
const LAMP_COLOUR: Color = Color(1.0, 0.76, 0.45)

const STRUCTURE_COLOUR: Color = Color(0.32, 0.31, 0.30)
const STRUCTURE_ROUGHNESS: float = 0.9
