class_name ActorProbe
extends RefCounted
## The per-actor reflection probe: local specular for the vehicle's own bodywork.
##
## Car paint, chrome and glass are defined by what they reflect, and a scene's sky alone
## reflects nothing of the vehicle itself — no wheel arch in the door, no bonnet in the
## windscreen, nothing of the ground it is standing on. A probe around the actor supplies
## that, and being local it also moves with the vehicle instead of baking a reflection of
## wherever it was parked.
##
## The update rate is deliberately low. PLAN M2 asks for one probe per actor at a low update
## rate, because a probe that re-renders every frame costs six faces of scene rendering for
## a reflection nobody is inspecting closely while the vehicle is moving.

## How much bigger than the vehicle the probe's box is.
##
## **The box is the probe's influence, not its capture**, and conflating the two is what caused a
## reported bug. This margin used to be 1.5 m "so the probe captures the ground under the
## vehicle" — but what a probe captures is set by where it stands and `max_distance`, while the
## box decides which surfaces it *lights*. Godot applies a probe to everything inside its box,
## not just the object it was added for, so a 1.5 m margin handed the probe a ring of road and
## lit it differently from the road beyond: a hard rectangle around the vehicle, reported from
## the window as the scene's colour not applying there.
##
## Small enough to bound the vehicle and little else; `MAX_DISTANCE_M` still reaches the ground,
## so the lower panels reflect it exactly as before. Measured against the road either side of the
## box, this takes the difference from 403.8% to 4.5%.
const MARGIN_M: float = 0.2
## Reflections are blended out past the box rather than ending at its face.
const BLEND_DISTANCE_M: float = 1.0
## Enough range to catch the ground, the wheels and whatever the vehicle is next to.
const MAX_DISTANCE_M: float = 40.0
const INTENSITY: float = 1.0


## Adds a probe around everything `root` draws. Returns it.
static func add(root: Node3D) -> ReflectionProbe:
    var probe: ReflectionProbe = ReflectionProbe.new()
    probe.name = "ActorReflectionProbe"
    # Measured in the root's own space rather than in the world's and converted back. An AABB
    # put through a rotation becomes the axis-aligned box *around* the rotated box, so a
    # round trip through the actor frame does not return what went in: it grows and shifts,
    # and the probe ends up beside the vehicle instead of around it.
    var local: AABB = local_bounds(root)
    probe.size = local.size + Vector3.ONE * (2.0 * MARGIN_M)
    probe.position = local.get_center()
    probe.update_mode = ReflectionProbe.UPDATE_ONCE
    # The probe lights nothing; it only reflects.
    #
    # A reflection probe also injects an ambient term by default, and with `UPDATE_ONCE` that term
    # is frozen at the moment the vehicle was built. Cycling the weather then left the enclosed
    # ground lit by a daylight ambient while everything outside the box went blue — measured, the
    # single largest contributor to the reported rectangle, worth 403.8% against 135.1% with it
    # off. Turning the probe's *intensity* to zero does not help, because intensity scales the
    # reflection and not this: with the probe contributing nothing visible it still read 243.4%.
    probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
    probe.intensity = INTENSITY
    probe.max_distance = MAX_DISTANCE_M
    probe.blend_distance = BLEND_DISTANCE_M
    # Interior probes ignore the sky, which is most of what is reflected outdoors.
    probe.interior = false
    root.add_child(probe)
    return probe


## Bounds of everything `root` draws, in `root`'s own space.
static func local_bounds(root: Node3D) -> AABB:
    var bounds: AABB = AABB()
    var started: bool = false
    for entry: Dictionary in _drawn(root, Transform3D.IDENTITY):
        var box: AABB = (entry["transform"] as Transform3D) * (entry["aabb"] as AABB)
        bounds = box if not started else bounds.merge(box)
        started = true
    return bounds


## Every drawn mesh under `node`, with its transform relative to the root it was entered at.
static func _drawn(node: Node, to_root: Transform3D) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for child: Node in node.get_children():
        var spatial: Node3D = child as Node3D
        if spatial == null:
            continue
        var accumulated: Transform3D = to_root * spatial.transform
        var mesh: MeshInstance3D = spatial as MeshInstance3D
        if mesh != null and mesh.mesh != null:
            out.append({"transform": accumulated, "aabb": mesh.get_aabb()})
        out.append_array(_drawn(spatial, accumulated))
    return out


## Takes every actor probe in a scene again.
##
## **A probe set to `UPDATE_ONCE` holds the sky it was built under.** Switch a window from noon
## to a moonlit night and the bodywork goes on reflecting a daylight sky — a white truck on a
## dark road, reported from a window as "the car starts reflecting something and also becomes
## white". Re-assigning the update mode marks the probe dirty, so it captures the hour it is
## actually in and goes back to costing nothing.
static func recapture(root: Node) -> int:
    var taken: int = 0
    for child: Node in root.get_children():
        taken += recapture(child)
        var probe: ReflectionProbe = child as ReflectionProbe
        if probe == null:
            continue
        probe.update_mode = ReflectionProbe.UPDATE_ONCE
        taken += 1
    return taken
