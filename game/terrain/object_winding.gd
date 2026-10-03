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
## **What is left is content whose author wound part of it inward — a part, not a whole.**
## `haus4.mesh` is an A-frame whose roof slopes are right and whose two gable ends show their
## backs. `hospital.mesh` is a helipad slab whose one face looks down. No per-mesh decision fixes
## either: turning the first turns its roof as well, and the second has nothing to compare itself
## against. Both were found by photographing every object a map places from outside and looking at
## the stills, which is what `tools/mapcheck.sh` is for.
##
## **The test is a ray, and it needs no normal and no convention.** Step off a face along the way
## it is drawn to look and count the crossings with the rest of the mesh. Even means it looks at
## open air, which is what a surface anybody can see looks like. Odd means it looks into the body
## of its own object and is drawn back to front. It is the point-in-polygon argument.
##
## **Three rays, not one, and that is not a refinement.** A single ray lands on the seam between
## two triangles often enough to decide the question wrongly: aimed from the middle of a box at
## the middle of the opposite face it crosses the shared diagonal and is counted twice, so a solid
## that is inside out reads as even and passes. A reversed `BoxMesh` was missed entirely, which is
## how this was found. Three directions spread off the normal, and a majority, have no single seam
## to land on.
##
## **Per surface, not per face.** One vote is three passes over the mesh and a session loads
## several hundred meshes. Triangles are grown into surfaces first — touching, and looking within
## `GROUP_DEGREES` of each other — and one vote decides a whole surface, which also keeps one bad
## triangle from putting a hole in a wall. Touching matters as much as direction: grouping by
## direction alone put the outside of one roof slope and the inside of the opposite slope in the
## same group, and one ray then spoke for both. Corners are matched by rounded position rather
## than by vertex index, because an Ogre export splits a vertex per face as often as not.
##
## An open shell is left exactly as its file has it, deliberately: `store08.mesh` is two parallel
## facades with no end walls and no roof, every face of it looks at open air, and from the end you
## are correctly seeing the inside of a facade.

## How much of its own bounding box a mesh has to enclose before its signed volume is taken as a
## statement about the whole of it.
const CLOSED_SHARE: float = 0.05
## How far apart two faces may look and still be one surface.
const GROUP_DEGREES: float = 25.0
## How finely a corner is rounded when deciding whether two triangles touch, as a share of the
## mesh's own size.
const WELD: float = 0.001
## Over this many triangles a mesh is left alone: a vote is three passes over the mesh per surface
## and the cost is the product. The library's mean is 436 triangles and its largest is 13,214.
const MAX_RAY_TRIANGLES: int = 4000
## How far off a surface a ray starts, as a share of the mesh's own size, so the face it came from
## is never the first thing it hits.
const RAY_OFFSET: float = 0.0005
## How far off the normal the voting rays are aimed. Wide enough to miss a seam the straight ray
## lands on, narrow enough to stay on the same side of the surface.
const SPREAD_DEGREES: float = 11.0
## How level a lone sheet has to be before "it lies on the ground" is a statement about it.
const LEVEL: float = 0.85
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
        for at: int in submeshes.size():
            var every: PackedInt32Array = PackedInt32Array()
            for triangle: int in (
                (submeshes[at]["indices"] as PackedInt32Array).size() / 3
            ):
                every.append(triangle)
            out[at] = every
        return out
    var faces: Array[Dictionary] = faces_of(submeshes)
    var span: float = span_of(submeshes)
    if faces.is_empty() or faces.size() > MAX_RAY_TRIANGLES or span <= 0.0:
        return out
    for surface: Array in surfaces_of(faces, span):
        var widest: Dictionary = surface[0] as Dictionary
        for face: Dictionary in surface:
            if (face["area"] as float) > (widest["area"] as float):
                widest = face
        if not looks_into_itself(faces, widest, span):
            continue
        for face: Dictionary in surface:
            var at: int = face["submesh"] as int
            var indices: PackedInt32Array = out[at]
            indices.append(face["triangle"] as int)
            out[at] = indices
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


## Whether the way a face looks runs into the body of its own mesh.
##
## **A lone sheet crosses nothing either way and the ray has nothing to say about it.**
## `hospital.mesh` is a helipad: one level quad with open air above and below, whose one face
## looks down, and no geometry in the file distinguishes that from the same quad looking up. What
## distinguishes it is how a terrain object is used — it stands on the ground and is looked at
## from above, never from below — so a level sheet with nothing either side of it is turned to
## face up. The guard is the second set of rays: a bridge deck's underside has its own structure
## above it, crosses something, and is left alone.
static func looks_into_itself(
    faces: Array[Dictionary], face: Dictionary, span: float
) -> bool:
    var direction: Vector3 = face["out"] as Vector3
    var rays: Array[Vector3] = _spread(direction)
    var inside: int = 0
    var crossed: int = 0
    for along: Vector3 in rays:
        var crossings: int = _crossings(faces, face, direction, along, span)
        if crossings > 0:
            crossed += 1
        if crossings % 2 == 1:
            inside += 1
    if crossed > 0:
        return inside * 2 > rays.size()
    for along: Vector3 in _spread(-direction):
        if _crossings(faces, face, -direction, along, span) > 0:
            return false
    return (PITCH * direction).y < -LEVEL


## Three directions about a normal: the normal itself and two tilted off it. No seam catches all
## three.
static func _spread(normal: Vector3) -> Array[Vector3]:
    var sideways: Vector3 = normal.cross(
        Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
    ).normalized()
    var other: Vector3 = normal.cross(sideways).normalized()
    var tilt: float = tan(deg_to_rad(SPREAD_DEGREES))
    return [
        normal,
        (normal + sideways * tilt).normalized(),
        (normal + other * tilt).normalized(),
    ]


## How many of a mesh's own triangles one ray crosses. It starts off `face` along `offset` and
## travels along `along`, which is tilted off it.
static func _crossings(
    faces: Array[Dictionary], face: Dictionary, offset: Vector3, along: Vector3, span: float
) -> int:
    var from: Vector3 = (face["centre"] as Vector3) + offset * span * RAY_OFFSET
    var crossings: int = 0
    for other: Dictionary in faces:
        if other["submesh"] == face["submesh"] and other["triangle"] == face["triangle"]:
            continue
        var corners: Array = other["corners"] as Array
        if _hit(
            from, along, corners[0] as Vector3, corners[1] as Vector3, corners[2] as Vector3
        ):
            crossings += 1
    return crossings


## Moller-Trumbore, for a ray with no far end. Whether it crosses the triangle ahead of its origin.
static func _hit(from: Vector3, along: Vector3, a: Vector3, b: Vector3, c: Vector3) -> bool:
    var edge1: Vector3 = b - a
    var edge2: Vector3 = c - a
    var sideways: Vector3 = along.cross(edge2)
    var determinant: float = edge1.dot(sideways)
    if absf(determinant) < 1e-9:
        return false
    var inverse: float = 1.0 / determinant
    var offset: Vector3 = from - a
    var u: float = inverse * offset.dot(sideways)
    if u < 0.0 or u > 1.0:
        return false
    var across: Vector3 = offset.cross(edge1)
    var v: float = inverse * along.dot(across)
    if v < 0.0 or u + v > 1.0:
        return false
    return inverse * edge2.dot(across) > 1e-6


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
