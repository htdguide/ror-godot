class_name SceneryRange
extends RefCounted
## How far a terrain's scenery is drawn, and the one thing that is never subject to it.
##
## Split out of `RorObjects` when that file went over the source cap. It is a seam rather than a
## slice: everything here is about what a session chooses not to draw, and nothing in it builds
## anything.


## How much of the draw distance a surface fades out over, as a fraction of it. A thing that
## vanishes between one frame and the next is a thing a driver sees vanish.
const FADE_SHARE: float = 0.12


## Stops drawing a terrain's scenery past `metres`, leaving its backdrop alone. Returns how many
## surfaces were given the limit.
##
## **A backdrop is not scenery and a view distance is not a far plane.** The setting used to move
## the camera's far plane, which clips everything: pulling it in to look at the near ground took
## the mountains with it, and a terrain whose own horizon is ten kilometres out has nothing behind
## them to show instead. The camera now reaches as far as the terrain draws — see
## `PhysicalCamera.build` — and this is what the setting moves. The passes that state their own
## fog are the horizon rings and ground skirts, which are painted *as* a distance and are the one
## thing that must never go.
static func set_draw_distance(root: Node, metres: float) -> int:
    var limited: int = 0
    for node: Node in _descendants(root):
        var instance: VisualInstance3D = node as VisualInstance3D
        if instance == null or is_backdrop(instance):
            continue
        instance.visibility_range_end = maxf(metres, 0.0)
        instance.visibility_range_end_margin = maxf(metres, 0.0) * FADE_SHARE
        instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
        limited += 1
    return limited


## Whether a drawn thing is a terrain's painted horizon rather than something standing on it.
static func is_backdrop(instance: VisualInstance3D) -> bool:
    var geometry: GeometryInstance3D = instance as GeometryInstance3D
    if geometry == null:
        return false
    var mesh: Mesh = _mesh_of(geometry)
    if mesh == null:
        return false
    for surface: int in mesh.get_surface_count():
        var material: Material = mesh.surface_get_material(surface)
        if material != null and material.has_meta(RorObjects.ASKED_FOR_NO_FOG):
            return true
    return false


static func _mesh_of(node: GeometryInstance3D) -> Mesh:
    if node is MultiMeshInstance3D:
        var multimesh: MultiMesh = (node as MultiMeshInstance3D).multimesh
        return null if multimesh == null else multimesh.mesh
    if node is MeshInstance3D:
        return (node as MeshInstance3D).mesh
    return null


static func _descendants(node: Node) -> Array[Node]:
    var out: Array[Node] = [node]
    for child: Node in node.get_children():
        out.append_array(_descendants(child))
    return out
