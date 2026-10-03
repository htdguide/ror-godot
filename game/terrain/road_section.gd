class_name RoadSection
extends RefCounted
## What a procedural road looks like in cross-section, and which kind of road a point is.
##
## Eight points, outer to outer, in the point's own frame — the road runs along its local x and
## the section spans its local z. Upstream's `ProceduralRoad::computePoints`:
##
##     0  the far shoulder's foot          4  the carriageway's right edge
##     1  the far shoulder's top           5  the near kerb's top
##     2  the near kerb's top (far side)   6  the near shoulder's top
##     3  the carriageway's left edge      7  the near shoulder's foot
##
## A kerb rises by the border height and a shoulder falls away by it; which side does which is
## what the kind names. On a bridge or a monorail both sides are kerbed and the outer points drop
## to a wall instead of to the ground — 0.4 m for a bridge, 1.4 m for a monorail, whose deck also
## sits two metres higher than its points state.
##
## Split from the sweep because they are different questions: this says what the road is, and the
## sweep says how one cross-section joins the next.

## How far a bridge's and a monorail's wall hangs below the deck.
const BRIDGE_WALL_M: float = 0.4
const MONORAIL_WALL_M: float = 1.4
## A monorail's deck stands this far above the points that describe it.
const MONORAIL_LIFT_M: float = 2.0
## How far under the ground a shoulder's foot is sunk, so it never z-fights the terrain.
const FOOT_SINK_M: float = 0.01
## Every kind this knows how to shape.
const KINDS: Array[String] = ["flat", "left", "right", "both", "bridge", "monorail", "automatic"]
## The kinds that carry a wall and an underside rather than meeting the ground.
const RAISED: Array[String] = ["bridge", "monorail"]
## What `automatic` compares the drop either side against, from `ProceduralRoad::addBlock`.
const AUTOMATIC_WIDTH_M: float = 10.0
const AUTOMATIC_BORDER_W_M: float = 1.4
const AUTOMATIC_BORDER_H_M: float = 0.2
const AUTOMATIC_MAX_DROP_M: float = 4.0


## The eight points of one cross-section, in world space.
static func points(terrain: RorTerrain, point: Dictionary) -> PackedVector3Array:
    var kind: String = point["kind"] as String
    var at: Vector3 = point["position"] as Vector3
    if kind == "monorail":
        at.y += MONORAIL_LIFT_M
    var basis: Basis = frame(point["rotation"] as Vector3)
    var width: float = point["width"] as float
    var bw: float = point["bwidth"] as float
    var bh: float = point["bheight"] as float
    var raised: bool = RAISED.has(kind)
    # A kerb rises; a shoulder falls away.
    var left_up: bool = raised or kind == "both" or kind == "right"
    var right_up: bool = raised or kind == "both" or kind == "left"
    var out: PackedVector3Array = PackedVector3Array()
    out.resize(8)
    out[1] = at + basis * Vector3(0.0, bh if left_up else -bh, bw + width * 0.5)
    out[2] = at + basis * Vector3(
        0.0, bh if left_up else -bh * 0.25,
        width * 0.5 if left_up else bw / 3.0 + width * 0.5
    )
    out[3] = at + basis * Vector3(0.0, 0.0, width * 0.5)
    out[4] = at + basis * Vector3(0.0, 0.0, -width * 0.5)
    out[5] = at + basis * Vector3(
        0.0, bh if right_up else -bh * 0.25,
        -width * 0.5 if right_up else -bw / 3.0 - width * 0.5
    )
    out[6] = at + basis * Vector3(0.0, bh if right_up else -bh, -bw - width * 0.5)
    if raised:
        var drop: float = MONORAIL_WALL_M if kind == "monorail" else BRIDGE_WALL_M
        out[0] = at + basis * Vector3(0.0, -drop, bw + width * 0.5)
        out[7] = at + basis * Vector3(0.0, -drop, -bw - width * 0.5)
    else:
        out[0] = foot(terrain, out[1])
        out[7] = foot(terrain, out[6])
    return out


## How a point is turned. Upstream composes the rotation about x, then y, then z.
static func frame(degrees: Vector3) -> Basis:
    return (
        Basis(Vector3.RIGHT, deg_to_rad(degrees.x))
        * Basis(Vector3.UP, deg_to_rad(degrees.y))
        * Basis(Vector3.BACK, deg_to_rad(degrees.z))
    )


## Where a shoulder meets the ground: the heightmap, or just under the road where the road is
## already below it.
static func foot(terrain: RorTerrain, p: Vector3) -> Vector3:
    var y: float = terrain.height_at_world(p.x, p.z) - FOOT_SINK_M
    if y > p.y:
        y = p.y - FOOT_SINK_M
    return Vector3(p.x, y, p.z)


## `automatic` resolved the way upstream resolves it: by how far the ground falls away either
## side of where the road would go.
static func resolved(terrain: RorTerrain, point: Dictionary) -> Dictionary:
    if (point["kind"] as String) != "automatic":
        return point
    var out: Dictionary = point.duplicate()
    out["width"] = AUTOMATIC_WIDTH_M
    out["bwidth"] = AUTOMATIC_BORDER_W_M
    out["bheight"] = AUTOMATIC_BORDER_H_M
    var at: Vector3 = point["position"] as Vector3
    var reach: float = AUTOMATIC_BORDER_W_M + AUTOMATIC_WIDTH_M * 0.5
    var left: float = at.y - terrain.height_at_world(at.x, at.z + reach)
    var right: float = at.y - terrain.height_at_world(at.x, at.z - reach)
    var lip: float = AUTOMATIC_BORDER_H_M + 0.1
    var left_clear: bool = left >= lip and left < AUTOMATIC_MAX_DROP_M
    var right_clear: bool = right >= lip and right < AUTOMATIC_MAX_DROP_M
    if left < lip and right < lip:
        out["kind"] = "flat"
    elif left < lip and right_clear:
        out["kind"] = "left"
    elif left_clear and right < lip:
        out["kind"] = "right"
    elif left_clear and right_clear:
        out["kind"] = "both"
    else:
        # Upstream falls back to a bridge where the ground drops away on both sides.
        out["kind"] = "bridge"
        out["bwidth"] = 0.4
        out["bheight"] = 0.5
    return out
