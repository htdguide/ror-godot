class_name PlaySolid
extends RefCounted
## What a terrain is solid as, in a session: the overlay a key turns on, and where a vehicle may
## stand without being inside it.
##
## Split from `PlayRig` when that file went over the source cap, and it is a real seam — both of
## these are about the collision set rather than about driving, and both only exist because that
## set stopped being a handful of boxes around corners.

## How far above whatever is solid beneath it a vehicle is placed. `RigBuilder.place` adds its
## own small clearance on top of this and drops the rig from there, so this only has to clear the
## surface itself rather than leave room for the suspension to settle.
const SPAWN_CLEAR_M: float = 0.05
## And how far above the start height a box may reach and still count as the thing being stood
## on rather than a roof over it.
const SPAWN_REACH_M: float = 2.0

var _terrain: RorTerrain = null
var _view: Node3D = null


func setup(terrain: RorTerrain) -> void:
    _terrain = terrain


## Whether the overlay is on screen.
func shown() -> bool:
    return _view != null and _view.visible


## Draws what the terrain is solid as, or hides it. Built on first use: the boxes are one
## multimesh, but working them out walks every object the map places.
func show_boxes(world: Node3D, on: bool) -> String:
    if _terrain == null:
        return ""
    if _view == null:
        if not on:
            return ""
        _view = CollisionView.build(_terrain)
        world.add_child(_view)
        return "collision shown: %d solid boxes" % CollisionView.count(_terrain)
    _view.visible = on
    return "collision %s" % ("shown" if on else "hidden")


## Where a vehicle starts, lifted clear of whatever is solid under it.
##
## **A start position is a place on the ground, and the ground there may now be an object.** Port
## Starling's is a quay pad, and once that pad had collision the rig was placed inside its top box
## rather than on it: it sat in the surface and shot upwards on every reset. The terrain's own
## height is no longer the whole answer, so the highest solid thing under the start is found and
## the rig put above it.
static func clear_spawn(terrain: RorTerrain) -> Vector3:
    var at: Vector3 = terrain.start_position()
    var highest: float = at.y
    for box: Dictionary in RorObjectCollision.boxes(terrain):
        var frame: Transform3D = box["transform"] as Transform3D
        var half: Vector3 = box["half"] as Vector3
        var reach: Vector3 = (frame.basis.x.abs() * half.x + frame.basis.y.abs() * half.y
            + frame.basis.z.abs() * half.z)
        if at.x < frame.origin.x - reach.x or at.x > frame.origin.x + reach.x:
            continue
        if at.z < frame.origin.z - reach.z or at.z > frame.origin.z + reach.z:
            continue
        # What is under the start, not a gantry over it.
        var top: float = frame.origin.y + reach.y
        if top <= at.y + SPAWN_REACH_M:
            highest = maxf(highest, top)
    return Vector3(at.x, highest + SPAWN_CLEAR_M, at.z)
