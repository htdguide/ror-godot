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
## How far a lifted deck is held above the ground, so it is drawn rather than fighting it.
const DECK_CLEARANCE_M: float = 0.05
## And how far a deck may be lifted at all.
##
## **A metre is authoring slop; a hundred is a different fault wearing its clothes.** On Port
## Starling 25 of 336 road points want a lift and none wants more than 0.6 m — a spline laid
## close to the ground and missing it. On North St Helens 601 of 1363 want one and 87 want more
## than 5 m, the worst 148.9 m, which is not a road that sank into a hillside but a road and a
## heightmap that disagree about where the world is. Lifting those would hang a road over a
## mountain and hide the question. They are left where the file puts them and counted by
## `a_road_rests_on_the_ground_it_crosses`.
const MAX_LIFT_M: float = 1.0
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
    # **A road that is not a bridge rests on the ground it crosses.** The deck's height is the
    # author's own spline and the ground is a heightmap neither of them agreed with: 867 of Port
    # Starling's 8688 road vertices sit below the terrain, the worst of them 5.26 m down, and a
    # road under a hillside is a road nobody can see. Reported from a window as "some roads are
    # missing". Lifted by the most any part of its own deck needs, so a crossing stays level
    # rather than twisting, and never lowered — where the spline is already clear of the ground
    # it is left exactly as the file has it. Bridges and monorails are the point of being above
    # the ground and are not touched.
    if not RAISED.has(kind):
        at.y += lift_for(terrain, at, basis, width)
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


## Measured at each sample's own height rather than at the centre's: a banked section's downhill
## edge sits below its middle, and lifting by what the middle needs leaves that edge in the
## ground. Two corners on North St Helens, 0.10 and 0.14 m under, found by the gate.
static func lift_for(terrain: RorTerrain, at: Vector3, basis: Basis, width: float) -> float:
    var wanted: float = 0.0
    for across: float in [-0.5, 0.0, 0.5]:
        var edge: Vector3 = at + basis * Vector3(0.0, 0.0, width * across)
        var ground: float = terrain.height_at_world(edge.x, edge.z)
        wanted = maxf(wanted, ground + DECK_CLEARANCE_M - edge.y)
    # All or nothing. Clamping to the cap was tried and moves a section that wants metres into
    # the band the gate judges, which makes a gross mismatch look like a near miss; a section one
    # of whose samples wants more than the cap is a section this rule has nothing to say about.
    return 0.0 if wanted > MAX_LIFT_M else wanted


## What a section would need to clear the ground, uncapped, so a caller can tell a near miss from
## a mismatch the builder refuses to touch.
static func lift_wanted(terrain: RorTerrain, point: Dictionary) -> float:
    var at: Vector3 = point["position"] as Vector3
    if (point["kind"] as String) == "monorail":
        at.y += MONORAIL_LIFT_M
    var basis: Basis = frame(point["rotation"] as Vector3)
    var width: float = point["width"] as float
    var wanted: float = 0.0
    for across: float in [-0.5, 0.0, 0.5]:
        var edge: Vector3 = at + basis * Vector3(0.0, 0.0, width * across)
        wanted = maxf(wanted, terrain.height_at_world(edge.x, edge.z) + DECK_CLEARANCE_M - edge.y)
    return wanted


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
