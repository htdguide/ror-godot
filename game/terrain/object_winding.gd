class_name ObjectWinding
extends RefCounted
## Which way round a terrain object's triangles go, decided one surface at a time.
##
## **Godot's front faces are wound clockwise**, and every rule this file used to carry had that
## backwards. Measured against the engine's own primitives, which it draws correctly by
## definition: `BoxMesh`, `SphereMesh` and `CylinderMesh` all score 0.0% under
## `cross(b - a, c - a) · normal >= 0`, and all three enclose a *negative* signed volume under
## `a · (b × c) / 6` — -1.0, -0.52 and -0.78 of their own bounding boxes. See ADR 0005.
##
## `OgreMeshReader`'s reversal is therefore the Ogre-to-Godot conversion, for a truck and a
## building alike, and nothing here undoes it.
##
## What is left after that is content, and `tools/mapcheck.sh` photographs it while
## `tools/review.sh` asks a person about it.
##
## **Two rules, and a ray was tried for a third and withdrawn.** A mesh that encloses a positive
## volume is a solid wound inward and is turned whole. A mesh whose faces all look the same way
## is a sheet, and a sheet lying face-down is turned, because a terrain object stands on the
## ground and is looked at from above, never from below — that is `hospital.mesh`, a helipad
## whose one quad looked down.
##
## **The withdrawn rule was ray parity, and it was wrong for a reason worth writing down.** Step
## off a face the way it is drawn to look, count the crossings with the rest of the mesh, and an
## odd count means the face looks into its own object. That is the point-in-polygon argument, it
## passes a two-way control on `BoxMesh`, `SphereMesh` and `CylinderMesh` — and **parity needs a
## closed manifold**, which almost no object in this library is. On an open shell any overhang,
## partition or L-shaped wing puts an odd count under a surface that was perfectly correct, and
## the surface is turned and vanishes. A review session found it: of the surfaces a person
## pointed at and called transparent or missing, most came back `turned=true`, meaning this file
## had broken them. `GROUP_DEGREES`, `WELD`, `surfaces_of` and `hit_distance` remain because
## `ReviewPick` needs them to find what the mouse is over.
##
## An open shell is therefore left exactly as its file has it, which also honours the author:
## measured, the winding of every one of those marked surfaces already agreed with the vertex
## normals the file carries for it.

## How much of its own bounding box a mesh has to enclose before its signed volume is taken as a
## statement about the whole of it.
const CLOSED_SHARE: float = 0.05
## How far apart two faces may look and still be one surface.
const GROUP_DEGREES: float = 25.0
## How finely a corner is rounded when deciding whether two triangles touch, as a share of the
## mesh's own size.
const WELD: float = 0.001
## How much of a mesh's area has to look the same way before it is one sheet rather than a shape
## with an inside. A single slab is 1.0; a box is 0.0.
const SHEET_AGREEMENT: float = 0.5
## The turn every terrain object is placed with, which is what makes a mesh axis into a world one.
## `RorObjects.transform_of` applies it unconditionally for every object on every terrain.
const PITCH: Basis = Basis(
    Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0), Vector3(0.0, 1.0, 0.0)
)


## Which triangles of each submesh are drawn back to front, as one index list per submesh.
##
## Indices are triangle numbers within the submesh, not vertex indices. An empty list for every
## submesh — the common case — means the mesh is drawn exactly as its file has it.
static func plan(submeshes: Array) -> Array[PackedInt32Array]:
    var out: Array[PackedInt32Array] = []
    for _submesh: Dictionary in submeshes:
        out.append(PackedInt32Array())
    # **A solid that is inside out is inside out as a whole, and the volume says so without any
    # ray.** `haus3`, `haus4` and La Paz's ground skirt enclose a positive volume — outward is
    # negative, see ADR 0005 — and the surface-by-surface test cannot see it: every one of their
    # surfaces has open air on the side it looks at, because the inside of a shell is open air
    # too. The two measures answer different questions and the cheaper one goes first.
    if enclosed_share(submeshes) > CLOSED_SHARE:
        return _every_triangle(submeshes, out)
    # **A lone sheet has no inside, and the only thing that decides it is how it is used.**
    # `hospital.mesh` is a helipad: one level quad with open air above and below, whose one face
    # looks down, and no geometry in the file distinguishes that from the same quad looking up. A
    # terrain object stands on the ground and is looked at from above, never from below.
    var level: Dictionary = facing(submeshes)
    if (level["agreement"] as float) > SHEET_AGREEMENT and (level["up"] as float) < 0.0:
        return _every_triangle(submeshes, out)
    return out


## Which way a mesh looks as a whole, and how much of it agrees: `{"agreement", "up"}`.
##
## `agreement` is the length of the area-weighted sum of the drawn outward directions over the
## total area — 1.0 for a flat sheet, near 0 for anything closed, because a closed shape's faces
## point every way at once. `up` is that sum's world height once the -90 degree pitch every
## terrain object is placed with has been applied, so it is "up" as a person standing on the map
## means it rather than as the file's axes have it.
static func facing(submeshes: Array) -> Dictionary:
    var sum: Vector3 = Vector3.ZERO
    var area: float = 0.0
    for face: Dictionary in faces_of(submeshes):
        var piece: Vector3 = (face["out"] as Vector3) * (face["area"] as float)
        sum += piece
        area += face["area"] as float
    if area <= 0.0:
        return {"agreement": 0.0, "up": 0.0}
    return {"agreement": sum.length() / area, "up": (PITCH * sum).y}


## Every triangle of every submesh, for the cases that turn a whole mesh.
static func _every_triangle(
    submeshes: Array, out: Array[PackedInt32Array]
) -> Array[PackedInt32Array]:
    for at: int in submeshes.size():
        var every: PackedInt32Array = PackedInt32Array()
        for triangle: int in ((submeshes[at]["indices"] as PackedInt32Array).size() / 3):
            every.append(triangle)
        out[at] = every
    return out


## How much of its own bounding box a mesh encloses, signed, in the order the reader hands it
## over. Near zero for an open shape, negative for one wound outward.
static func enclosed_share(submeshes: Array) -> float:
    var volume: float = 0.0
    var low: Vector3 = Vector3.INF
    var high: Vector3 = -Vector3.INF
    var triangles: int = 0
    for submesh: Dictionary in submeshes:
        var points: PackedVector3Array = submesh["positions"] as PackedVector3Array
        var indices: PackedInt32Array = submesh["indices"] as PackedInt32Array
        for point: Vector3 in points:
            low = low.min(point)
            high = high.max(point)
        for at: int in range(0, indices.size() - 2, 3):
            if indices[at + 2] >= points.size():
                continue
            volume += points[indices[at]].dot(
                points[indices[at + 1]].cross(points[indices[at + 2]])
            ) / 6.0
            triangles += 1
    if triangles < 8:
        return 0.0
    var box: Vector3 = high - low
    var capacity: float = box.x * box.y * box.z
    return 0.0 if capacity <= 0.0 else volume / capacity


## Every triangle of a mesh, as `{"submesh", "triangle", "centre", "out", "area", "corners"}`.
static func faces_of(submeshes: Array) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for at: int in submeshes.size():
        var submesh: Dictionary = submeshes[at] as Dictionary
        var points: PackedVector3Array = submesh["positions"] as PackedVector3Array
        var indices: PackedInt32Array = submesh["indices"] as PackedInt32Array
        var triangle: int = 0
        for first: int in range(0, indices.size() - 2, 3):
            # **A triangle may name a vertex that is not there.** Resynchronising past a chunk
            # length that lies recovers submeshes whose index buffer was read correctly and whose
            # vertex buffer the same bad length cut short. Such a triangle cannot be drawn and is
            # not geometry; `RorObjects.mesh_of` drops the submesh, and this skips it so that the
            # measurement never reads off the end of an array.
            if indices[first + 2] >= points.size():
                triangle += 1
                continue
            var a: Vector3 = points[indices[first]]
            var b: Vector3 = points[indices[first + 1]]
            var c: Vector3 = points[indices[first + 2]]
            # Clockwise is forward in Godot, so the way a drawn face looks is the negated cross.
            var face: Vector3 = -(b - a).cross(c - a)
            var area: float = face.length() * 0.5
            if area > 0.0:
                out.append({
                    "submesh": at, "triangle": triangle, "area": area,
                    "centre": (a + b + c) / 3.0, "out": face.normalized(),
                    "corners": [a, b, c],
                })
            triangle += 1
    return out


## Faces grown into surfaces: triangles that touch and look the same way.
static func surfaces_of(faces: Array[Dictionary], span: float) -> Array[Array]:
    var tolerance: float = cos(deg_to_rad(GROUP_DEGREES))
    var step: float = maxf(span * WELD, 1e-6)
    var corners: Dictionary = {}
    for at: int in faces.size():
        for corner: Vector3 in (faces[at]["corners"] as Array):
            var key: String = _corner_key(corner, step)
            var touching: PackedInt32Array = corners.get(key, PackedInt32Array())
            touching.append(at)
            corners[key] = touching
    var taken: PackedByteArray = PackedByteArray()
    taken.resize(faces.size())
    var out: Array[Array] = []
    for seed: int in faces.size():
        if taken[seed] == 1:
            continue
        taken[seed] = 1
        var surface: Array = [faces[seed]]
        var frontier: PackedInt32Array = PackedInt32Array([seed])
        while frontier.size() > 0:
            var here: int = frontier[frontier.size() - 1]
            frontier.remove_at(frontier.size() - 1)
            var direction: Vector3 = faces[here]["out"] as Vector3
            for corner: Vector3 in (faces[here]["corners"] as Array):
                for next: int in (corners[_corner_key(corner, step)] as PackedInt32Array):
                    if taken[next] == 1:
                        continue
                    if (faces[next]["out"] as Vector3).dot(direction) < tolerance:
                        continue
                    taken[next] = 1
                    surface.append(faces[next])
                    frontier.append(next)
        out.append(surface)
    return out


static func _corner_key(corner: Vector3, step: float) -> String:
    return "%d,%d,%d" % [
        roundi(corner.x / step), roundi(corner.y / step), roundi(corner.z / step)
    ]


## How far along a ray a triangle is, or -1.0 when the ray misses it or it is behind the origin.
##
## The same arithmetic the winding test counts crossings with, exposed because picking a surface
## with the mouse asks exactly the same question and a second copy of it would be a second thing
## to get wrong.
static func hit_distance(
    from: Vector3, along: Vector3, a: Vector3, b: Vector3, c: Vector3
) -> float:
    var edge1: Vector3 = b - a
    var edge2: Vector3 = c - a
    var sideways: Vector3 = along.cross(edge2)
    var determinant: float = edge1.dot(sideways)
    if absf(determinant) < 1e-9:
        return -1.0
    var inverse: float = 1.0 / determinant
    var offset: Vector3 = from - a
    var u: float = inverse * offset.dot(sideways)
    if u < 0.0 or u > 1.0:
        return -1.0
    var across: Vector3 = offset.cross(edge1)
    var v: float = inverse * along.dot(across)
    if v < 0.0 or u + v > 1.0:
        return -1.0
    var distance: float = inverse * edge2.dot(across)
    return distance if distance > 1e-6 else -1.0


## How big a mesh is, as the diagonal of its own bounding box.
static func span_of(submeshes: Array) -> float:
    var low: Vector3 = Vector3.INF
    var high: Vector3 = -Vector3.INF
    for submesh: Dictionary in submeshes:
        for point: Vector3 in submesh["positions"] as PackedVector3Array:
            low = low.min(point)
            high = high.max(point)
    return 0.0 if low.x > high.x else (high - low).length()


## One submesh's geometry, as Godot's array format wants it, with the triangles `turn` names wound
## the other way round.
##
## **A turned triangle gets its own vertices.** Turning a face means the surface now looks the
## other way, so the normals the file carries for it have to be negated too — and a vertex is
## usually shared with faces that are not being turned, whose normals must not move. So the three
## corners of a turned triangle are appended as new vertices carrying the negated normal, which
## costs a handful of vertices on the handful of meshes that need any.
static func arrays(submesh: Dictionary, turn: PackedInt32Array) -> Array:
    var positions: PackedVector3Array = (submesh["positions"] as PackedVector3Array).duplicate()
    var indices: PackedInt32Array = (submesh["indices"] as PackedInt32Array).duplicate()
    if positions.is_empty() or indices.is_empty():
        return []
    var normals: PackedVector3Array = (submesh["normals"] as PackedVector3Array).duplicate()
    var uvs: PackedVector2Array = (submesh["uvs"] as PackedVector2Array).duplicate()
    var has_normals: bool = normals.size() == positions.size()
    var has_uvs: bool = uvs.size() == positions.size()
    for triangle: int in turn:
        var at: int = triangle * 3
        if at + 2 >= indices.size():
            continue
        var corners: PackedInt32Array = PackedInt32Array(
            [indices[at], indices[at + 2], indices[at + 1]]
        )
        for step: int in 3:
            var source: int = corners[step]
            positions.append(positions[source])
            if has_normals:
                normals.append(-normals[source])
            if has_uvs:
                uvs.append(uvs[source])
            indices[at + step] = positions.size() - 1
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = positions
    if has_normals:
        arrays[Mesh.ARRAY_NORMAL] = normals
    if has_uvs:
        arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices
    return arrays
