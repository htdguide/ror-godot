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

## How much bigger than the vehicle the probe's box is. A probe exactly the size of the body
## captures nothing of the ground under it, which is most of what a car's lower panels show.
const MARGIN_M: float = 1.5
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
