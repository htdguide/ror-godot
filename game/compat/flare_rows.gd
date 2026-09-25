class_name FlareRows
extends RefCounted
## Parses the `flares` and `flares2` sections: the lamps on a vehicle.
##
## A row is "ref_node, x_node, y_node, offset_x, offset_y, type, control, blink_ms, size,
## material". The three nodes are a frame rather than a position: the lamp sits at
##
##     ref + offset_x * (x_node - ref) + offset_y * (y_node - ref)
##
## and faces along `(y_node - ref) x (x_node - ref)`. So the offsets are fractions of the
## vehicle's own structure, not metres, and a lamp deforms with the panel it is mounted on —
## which is the point, and why a headlight still points somewhere sensible after a shunt.
##
## Unread, a vehicle's lights are whatever its texture painted on, with nothing emitting.

## Upstream's FlareType letters, from Application.h. The letters are the file format and do
## not change; the grouping into what is on when is ours.
const HEADLIGHT: String = "f"
const HIGH_BEAM: String = "h"
const FOG_LIGHT: String = "g"
const TAIL_LIGHT: String = "t"
const BRAKE_LIGHT: String = "b"
const REVERSE_LIGHT: String = "R"
const SIDELIGHT: String = "s"
const BLINKER_LEFT: String = "l"
const BLINKER_RIGHT: String = "r"
const USER: String = "u"
const DASHBOARD: String = "d"

## Lamps that throw light down the road, rather than merely being seen.
const PROJECTING: Array[String] = [HEADLIGHT, HIGH_BEAM, FOG_LIGHT]
## Upstream's defaults for a row that states -1 or -2 for its size.
const DEFAULT_HEADLIGHT_SIZE: float = 1.0
const DEFAULT_SIZE: float = 0.5
## A blink delay of -2 means "the default for this type", which blinks only for indicators.
const DEFAULT_BLINK_MS: int = 400


static func handles(section: String) -> bool:
    return section == "flares" or section == "flares2"


## Returns {"error", "ref", "x", "y", "offset", "type", "control", "blink_ms", "size",
## "material"}. `offset` is (offset_x, offset_y); `type` is one of the letters above.
static func row(fields: PackedStringArray, id_to_index: Dictionary) -> Dictionary:
    if fields.size() < 6:
        return {"error": "row has %d fields, expected at least 6" % fields.size()}
    var ref: int = int(id_to_index.get(fields[0], -1))
    var x: int = int(id_to_index.get(fields[1], -1))
    var y: int = int(id_to_index.get(fields[2], -1))
    if ref < 0 or x < 0 or y < 0:
        return {"error": "row references an unknown node"}
    # The type letter is case-sensitive: 'r' is a right indicator and 'R' is a reversing
    # light, and they are neither the same lamp nor the same colour.
    var type: String = fields[5].substr(0, 1)
    var blink_ms: int = fields[7].to_int() if fields.size() > 7 else -2
    if blink_ms == -2:
        blink_ms = DEFAULT_BLINK_MS if type == BLINKER_LEFT or type == BLINKER_RIGHT else 0
    var size: float = fields[8].to_float() if fields.size() > 8 else -2.0
    if size < 0.0:
        size = DEFAULT_HEADLIGHT_SIZE if type == HEADLIGHT else DEFAULT_SIZE
    return {
        "error": "",
        "ref": ref,
        "x": x,
        "y": y,
        "offset": Vector2(fields[3].to_float(), fields[4].to_float()),
        "type": type,
        "control": fields[6].to_int() if fields.size() > 6 else -1,
        "blink_ms": blink_ms,
        "size": size,
        "material": fields[9] if fields.size() > 9 else "",
    }


## Where a lamp sits, in the space its nodes are given in.
static func position(nodes: PackedVector3Array, flare: Dictionary) -> Vector3:
    var ref: Vector3 = nodes[flare["ref"] as int]
    var offset: Vector2 = flare["offset"] as Vector2
    return (
        ref
        + (nodes[flare["x"] as int] - ref) * offset.x
        + (nodes[flare["y"] as int] - ref) * offset.y
    )


## Which way a lamp faces. Zero when its three nodes are collinear and define no plane.
##
## Upstream takes this cross product the other way round, as `(y - ref) x (x - ref)`. Taken
## that way here every lamp on the vehicle faces 0.98 of the way into its own bodywork,
## measured by `flares_face_outward`. This is the same handedness difference between this
## project's rig space and upstream's that the steering wheel's 121 degree rake records — see
## docs/HANDOFF.md — and it is compensated here rather than left to be rediscovered as a
## lighting fault the first time someone drives at night.
static func normal(nodes: PackedVector3Array, flare: Dictionary) -> Vector3:
    var ref: Vector3 = nodes[flare["ref"] as int]
    var across: Vector3 = (nodes[flare["x"] as int] - ref).cross(nodes[flare["y"] as int] - ref)
    return across.normalized() if across.length_squared() > 0.0 else Vector3.ZERO


## Whether this lamp throws light rather than only being seen.
static func projects(flare: Dictionary) -> bool:
    return PROJECTING.has(flare["type"] as String)
