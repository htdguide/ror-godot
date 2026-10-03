class_name ObjectWinding
extends RefCounted
## Which way round a terrain object's triangles go.
##
## **Godot's front faces are wound clockwise**, and every rule this file used to carry had that
## backwards. Measured against the engine's own primitives, which it draws correctly by
## definition: `BoxMesh`, `SphereMesh` and `CylinderMesh` all score 0.0% under
## `cross(b - a, c - a) · normal >= 0`, and all three enclose a *negative* signed volume under
## `a · (b × c) / 6` — -1.0, -0.52 and -0.78 of their own bounding boxes. A mesh that satisfies
## the counter-clockwise convention is a mesh Godot draws inside out.
##
## So `OgreMeshReader`'s reversal is not a vehicle-only workaround. Ogre winds its front faces the
## other way from Godot, the reader turns every triangle once on the way in, and that is the whole
## of the conversion — for a truck and for a building alike. Objects were then wound *back* here,
## on the strength of two measurements that used the wrong sign, and every building in the library
## has been drawn inside out since. It is what "the outside texture is facing inside, from outside
## it looks transparent" was, and what the `object_photoset` gate now photographs: 14 of 20 face
## groups on Port Starling's five most-placed objects showed their backs to a camera standing on
## the normal their own file carries, while Godot's `BoxMesh` under the same camera showed none.
##
## **What is left after that is a handful of meshes whose authors wound them inward.** With the
## sign fixed, 20 of the library's 433 closed meshes enclose a *positive* volume — `store02`,
## `firehouse`, `haus3`, `haus4`, Russia's `hall`, La Paz's horizon and ground skirt — and those
## are inside out in their own files, not because of anything the reader did. They are what
## "buildings with broken textures which are visible only when being inside of the building"
## is, and they are turned here, winding and normals together, because turning only the winding
## would leave them drawn from the right side and lit from the wrong one.
##
## The signed volume is what decides it, because it needs no normal: sum `a · (b × c) / 6` over
## the triangles. An *open* mesh — a sidewalk, a sign, a road slab — encloses nothing in
## particular and the figure depends on where the origin happens to sit, so it is only read where
## it is a real share of the mesh's own bounding box, and anything ambiguous is left exactly as
## its file has it.

## How much of its own bounding box a mesh has to enclose before its signed volume is taken as a
## statement about winding rather than as the noise an open shape produces.
const CLOSED_SHARE: float = 0.05
## And how many triangles it takes before the measure means anything.
const MIN_CLOSED_TRIANGLES: int = 8


## Whether a mesh is wound inward in its own file, decided by its own geometry and no normal.
static func is_inside_out(submeshes: Array) -> bool:
    return enclosed_share(submeshes) > CLOSED_SHARE


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
    if triangles < MIN_CLOSED_TRIANGLES:
        return 0.0
    var box: Vector3 = high - low
    var capacity: float = box.x * box.y * box.z
    return 0.0 if capacity <= 0.0 else volume / capacity


## One submesh's geometry, as Godot's array format wants it, in the order the reader hands it
## over — or turned, when the mesh's own geometry says its author wound it inward.
static func arrays(submesh: Dictionary, turn: bool = false) -> Array:
    var positions: PackedVector3Array = submesh["positions"] as PackedVector3Array
    var indices: PackedInt32Array = submesh["indices"] as PackedInt32Array
    if positions.is_empty() or indices.is_empty():
        return []
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = positions
    var normals: PackedVector3Array = submesh["normals"] as PackedVector3Array
    if normals.size() == positions.size():
        if turn:
            var turned: PackedVector3Array = PackedVector3Array()
            turned.resize(normals.size())
            for at: int in normals.size():
                turned[at] = -normals[at]
            normals = turned
        arrays[Mesh.ARRAY_NORMAL] = normals
    var uvs: PackedVector2Array = submesh["uvs"] as PackedVector2Array
    if uvs.size() == positions.size():
        arrays[Mesh.ARRAY_TEX_UV] = uvs
    if not turn:
        arrays[Mesh.ARRAY_INDEX] = indices
        return arrays
    var forward: PackedInt32Array = indices.duplicate()
    for at: int in range(0, forward.size() - 2, 3):
        var swap: int = forward[at + 1]
        forward[at + 1] = forward[at + 2]
        forward[at + 2] = swap
    arrays[Mesh.ARRAY_INDEX] = forward
    return arrays
