class_name FacingViews
extends RefCounted
## Camera angles taken from a mesh's own authored normals, one per group of faces that point the
## same way.
##
## **A fixed six-sided photoset cannot decide whether a surface faces the right way.** Stand to
## the left of a building and the frame holds the near wall, the far wall, the roof, the ground
## skirt and the back of whatever is turned away — and a painted back face in that frame may be a
## fault or may be perfectly correct, because a road slab is one sheet and from underneath you
## are *supposed* to be looking at its back. Three different bounds on "how much paint is too
## much" were tried against the six fixed views and each of them was falsified by real content.
##
## The bound is not the problem. The frame is. Asked for from a window, in those words: make the
## camera angle and the object angle right, so only the surfaces under test face the camera.
##
## So the views are derived rather than fixed. The faces of a mesh are grouped by the direction
## the author's own vertex normals point, each group is drawn **alone**, and the camera stands on
## that group's normal looking back along it. Nothing else is in the frame, and every triangle
## that is in it is one whose author said it faces the camera. Then any paint at all is a face
## drawn back-to-front, and the verdict needs no judgement.
##
## **The normals are the oracle and they are not derived from the winding.** `ARRAY_NORMAL` is
## what the `.mesh` file shipped; the winding is what the reader produced. Asking whether they
## agree is a question with an answer, which is why this can carry a threshold where counting
## paint in a six-sided set could not.
##
## Cut-out surfaces are excluded and photographed by their own gate: see `two_sided`.

## How far apart two face normals may point and still be one group. Wide enough that a slightly
## bevelled wall is one view rather than five, narrow enough that the group is still flat enough
## to photograph head-on.
const GROUP_DEGREES: float = 25.0
## How much of a mesh's area a group needs before it earns a capture. A chamfer is not worth two
## frames.
const MIN_AREA_SHARE: float = 0.02
## How far to stand back, as a multiple of the object's bounding diagonal.
const DISTANCE_SCALE: float = 1.5
## When the view direction is this close to vertical, `Vector3.UP` is no use as an up vector.
const NEAR_VERTICAL: float = 0.95


## The face groups of a mesh, largest first, as
## `{"surface", "normal", "centre", "area", "indices", "label"}`.
##
## `normal` and `centre` are in the mesh's own space; the caller applies whatever transform the
## object is placed with. `limit` caps how many groups come back, because each one costs two
## captures. `cut_out` selects the other half of the mesh: the two-sided card surfaces, for the
## gate that photographs those.
static func groups(mesh: ArrayMesh, limit: int, cut_out: bool = false) -> Array[Dictionary]:
    var found: Array[Dictionary] = []
    var total: float = 0.0
    for surface: int in mesh.get_surface_count():
        if two_sided(mesh, surface) != cut_out:
            continue
        var arrays: Array = mesh.surface_get_arrays(surface)
        var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
        var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
        var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
        # No authored normals, no oracle. A mesh like that is reported by the caller rather than
        # judged against a direction this file would have had to invent.
        if normals.size() != positions.size() or indices.size() < 3:
            continue
        var here: Array[Dictionary] = []
        for at: int in range(0, indices.size() - 2, 3):
            var a: int = indices[at]
            var b: int = indices[at + 1]
            var c: int = indices[at + 2]
            var face: Vector3 = (normals[a] + normals[b] + normals[c])
            if face.length() < 0.001:
                continue
            var area: float = (
                (positions[b] - positions[a]).cross(positions[c] - positions[a]).length() * 0.5
            )
            if area <= 0.0:
                continue
            total += area
            _assign(
                here, surface, face.normalized(), area,
                (positions[a] + positions[b] + positions[c]) / 3.0,
                PackedInt32Array([a, b, c])
            )
        found.append_array(here)
    found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return (a["area"] as float) > (b["area"] as float)
    )
    var out: Array[Dictionary] = []
    for group: Dictionary in found:
        if out.size() >= limit:
            break
        if total <= 0.0 or (group["area"] as float) / total < MIN_AREA_SHARE:
            break
        group["normal"] = (group["normal"] as Vector3).normalized()
        group["centre"] = (group["centre"] as Vector3) / (group["weight"] as float)
        group["label"] = "%s %d" % [_axis(group["normal"] as Vector3), out.size() + 1]
        out.append(group)
    return out


## Puts one triangle in the group it belongs to, or starts a group for it. Area-weighted, so the
## group's normal and centre are those of the surface it stands for rather than of its smallest
## sliver.
static func _assign(
    into: Array[Dictionary], surface: int, normal: Vector3, area: float, centre: Vector3,
    corners: PackedInt32Array
) -> void:
    var tolerance: float = cos(deg_to_rad(GROUP_DEGREES))
    for group: Dictionary in into:
        if (group["normal"] as Vector3).normalized().dot(normal) < tolerance:
            continue
        group["normal"] = (group["normal"] as Vector3) + normal * area
        group["centre"] = (group["centre"] as Vector3) + centre * area
        group["area"] = (group["area"] as float) + area
        group["weight"] = (group["weight"] as float) + area
        var indices: PackedInt32Array = group["indices"] as PackedInt32Array
        indices.append_array(corners)
        group["indices"] = indices
        return
    into.append({
        "surface": surface, "normal": normal * area, "centre": centre * area,
        "area": area, "weight": area, "indices": corners,
    })


## A mesh holding one group's triangles and nothing else, with that surface's own material.
##
## The vertex arrays are kept whole and only the index array is narrowed: a subset of indices is
## a subset of the geometry, and reindexing would be work with nothing to show for it.
static func isolate(mesh: ArrayMesh, group: Dictionary) -> ArrayMesh:
    var surface: int = group["surface"] as int
    var arrays: Array = mesh.surface_get_arrays(surface)
    arrays[Mesh.ARRAY_INDEX] = group["indices"] as PackedInt32Array
    var out: ArrayMesh = ArrayMesh.new()
    out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    out.surface_set_material(0, mesh.surface_get_material(surface))
    return out


## Where to stand to look a group in the face: on its own normal, aimed at its own centre.
##
## Aimed at the group rather than at the object's middle, because a group is often off to one
## side — a roof plane of a long building is not centred on the building — and a frame centred on
## the object can hold the group at its edge where a few pixels of it fall outside.
static func placement(group: Dictionary, at: Transform3D, size: float) -> Dictionary:
    var normal: Vector3 = (at.basis * (group["normal"] as Vector3)).normalized()
    var centre: Vector3 = at * (group["centre"] as Vector3)
    var reach: float = maxf(size * DISTANCE_SCALE, 1.0)
    var up: Vector3 = (
        Vector3.BACK if absf(normal.dot(Vector3.UP)) > NEAR_VERTICAL else Vector3.UP
    )
    return {"pos": centre + normal * reach, "look_at": centre, "up": up}


## Whether a surface is drawn from both sides by the terrain's own material, which makes the
## facing paint meaningless for it.
##
## **These are the cut-outs, and they are a different question.** A material that declares
## `alpha_rejection` is a card with a shape punched out of it — foliage, a chain-link fence, a
## railing — and `RorObjects` gives those `CULL_DISABLED`, because a leaf card seen from behind
## is a leaf card and not a fault. Painting their backs is what made a tree report 18% of its
## frame marked while being drawn exactly right. Asked for from a window: a tree is half
## transparent, so it needs a separate method. It has one.
static func two_sided(mesh: ArrayMesh, surface: int) -> bool:
    var material: StandardMaterial3D = mesh.surface_get_material(surface) as StandardMaterial3D
    return material != null and material.cull_mode == BaseMaterial3D.CULL_DISABLED


## Which surfaces of a mesh are cut-out cards, for the gate that photographs those.
static func cut_outs(mesh: ArrayMesh) -> PackedInt32Array:
    var out: PackedInt32Array = PackedInt32Array()
    for surface: int in mesh.get_surface_count():
        if two_sided(mesh, surface):
            out.append(surface)
    return out


## Which way a normal mostly points, as two characters for a label stamped in the frame.
static func _axis(normal: Vector3) -> String:
    var axis: Vector3 = normal.abs()
    if axis.x >= axis.y and axis.x >= axis.z:
        return "+X" if normal.x > 0.0 else "-X"
    if axis.y >= axis.z:
        return "+Y" if normal.y > 0.0 else "-Y"
    return "+Z" if normal.z > 0.0 else "-Z"
