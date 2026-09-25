class_name Photoset
extends RefCounted
## Camera placements for photographing a vehicle from every side.
##
## One angle is not enough. Parts have been correct in one view and obviously wrong in
## another more than once in this project: a door that looked open from the front, a
## tailgate that looked missing, panels that vanish when seen from their back face. The
## views are derived from the subject's own bounds, so they frame any vehicle.

const VIEWS: Array[String] = [
    "front", "back", "left", "right", "top", "bottom", "three_quarter", "interior"
]
## How far back to stand, as a multiple of the subject's size. Enough to hold the whole
## vehicle with room around it.
const DISTANCE_SCALE: float = 1.5
const FOCAL_MM: float = 50.0


## Camera position and target for one view of a subject.
static func placement(view: String, bounds: AABB, interior: Vector3) -> Dictionary:
    var centre: Vector3 = bounds.position + bounds.size * 0.5
    var reach: float = maxf(bounds.size.length() * DISTANCE_SCALE, 1.0)
    match view:
        "front":
            return {"pos": centre + Vector3(-reach, 0.0, 0.0), "look_at": centre}
        "back":
            return {"pos": centre + Vector3(reach, 0.0, 0.0), "look_at": centre}
        "left":
            return {"pos": centre + Vector3(0.0, 0.0, -reach), "look_at": centre}
        "right":
            return {"pos": centre + Vector3(0.0, 0.0, reach), "look_at": centre}
        "top":
            return {"pos": centre + Vector3(0.0, reach, 0.01), "look_at": centre}
        "bottom":
            # From below, which is where suspension, frame and floor pans are, and where
            # nothing else in the set ever looks.
            return {"pos": centre + Vector3(0.0, -reach, 0.01), "look_at": centre}
        "three_quarter":
            return {
                "pos": centre + Vector3(-reach * 0.6, reach * 0.35, reach * 0.6),
                "look_at": centre,
            }
        "interior":
            # At the driver's eye, looking forward along the vehicle. The vehicle's own
            # frame has already been applied to `interior`, so forward is -X in world
            # terms only because the rig is placed unrotated for these shots.
            return {"pos": interior, "look_at": interior + Vector3(-1.0, -0.2, 0.0)}
        _:
            return {"pos": centre + Vector3(reach, reach, reach), "look_at": centre}
