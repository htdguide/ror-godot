class_name ObjectWinding
extends RefCounted
## Which way round a terrain object's triangles go, and the geometry that decides it.
##
## Split from `RorObjects` when that file went over the source cap, and it is a seam worth having:
## placing an object on a map and orienting its faces are different questions, and this one is
## settled by the mesh alone.

## How much of its own bounding box a mesh has to enclose before its signed volume is taken as a
## statement about winding rather than as the noise an open shape produces.
const CLOSED_SHARE: float = 0.05
## And how many triangles it takes before the measure means anything.
const MIN_CLOSED_TRIANGLES: int = 8


## Whether a mesh is wound the wrong way round for the way it is drawn, decided by its own
## geometry.
##
## **The content is not consistent and a blanket rule cannot fix it.** `OgreMeshReader` reverses
## every triangle, which is right for the vehicle path and wrong for an object, so objects were
## un-reversed wholesale — and that is right for 75 of Port Starling's 90 distinct meshes and
## wrong for four of them. `store02`, `haus3`, `firehouse` and `haus4` are authored the other way
## round: their own vertex normals agree with their reversed winding, so a check against the
## normals passes them, and from outside they are still a hole. Reported from a window as "the
## outside texture is facing inside".
##
## The signed volume of a closed triangle soup says which way it is wound without reference to any
## normal: sum `a . (b x c) / 6` over the triangles, and a mesh whose faces wind outward encloses
## a positive volume. An open mesh — a sidewalk, a sign, a road slab — encloses nothing in
## particular, so the measure is only trusted when it is a real share of the mesh's own bounding
## box, and anything ambiguous is left exactly as its file has it.
static func is_inside_out(submeshes: Array) -> bool:
    return enclosed_share(submeshes) > CLOSED_SHARE


## Whether a mesh encloses nothing in particular: a wall, a roof, a sign, a road slab.
##
## Its signed volume cannot say which way it is wound either. The divergence theorem applies to a
## closed surface; for an open one the figure depends on where the origin happens to sit, and
## `haus3.mesh` is two slanted planes that "enclose" 0.66 of their own box. Seeing the back of
## such a surface is also often correct — a road slab is one sheet and from underneath you are
## looking at its back — so an open mesh is left exactly as its file has it and judged by a
## person looking at a photograph rather than by a rule.
static func is_open(submeshes: Array) -> bool:
    return absf(enclosed_share(submeshes)) < CLOSED_SHARE


## How much of its own bounding box a mesh encloses, signed, in the order the reader hands it
## over. Near zero for an open shape.
##
## The reader has already reversed these, so the sign here is the opposite of the sign the drawn
## mesh will have: a *positive* volume in the file's own order means the drawn mesh would enclose
## a negative one.
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


## One submesh's geometry, as Godot's array format wants it.
static func arrays(submesh: Dictionary, keep_reader_order: bool = false) -> Array:
    var positions: PackedVector3Array = submesh["positions"] as PackedVector3Array
    var indices: PackedInt32Array = submesh["indices"] as PackedInt32Array
    if positions.is_empty() or indices.is_empty():
        return []
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = positions
    var normals: PackedVector3Array = submesh["normals"] as PackedVector3Array
    if normals.size() == positions.size():
        if keep_reader_order:
            # A mesh whose geometry encloses the wrong sign is inside out in both senses: its
            # authored normals point the same way its reversed faces do. Turning the faces round
            # without turning the normals would leave it drawn from the right side and lit from
            # the wrong one.
            var turned: PackedVector3Array = PackedVector3Array()
            turned.resize(normals.size())
            for at: int in normals.size():
                turned[at] = -normals[at]
            normals = turned
        arrays[Mesh.ARRAY_NORMAL] = normals
    var uvs: PackedVector2Array = submesh["uvs"] as PackedVector2Array
    if uvs.size() == positions.size():
        arrays[Mesh.ARRAY_TEX_UV] = uvs
    # **Wound back the way the file has it.** `OgreMeshReader` reverses every triangle, for a
    # vehicle: loaded in file order a truck is culled from outside and drawn from inside, and the
    # reader's own note says something in the pose path mirrors the geometry and has never been
    # isolated. A terrain object goes through no such path — `transform_of` is a rotation and a
    # positive scale — so the same reversal turns a building inside out. Measured: after the
    # reader, 0.0% of `store08.mesh`'s 160 triangles agree with the normals the file carries for
    # them, and the same for `warehouse01` and `firehouse`. Reported from a window as walls
    # visible from one side only.
    var forward: PackedInt32Array = indices.duplicate()
    if not keep_reader_order:
        for at: int in range(0, forward.size() - 2, 3):
            var swap: int = forward[at + 1]
            forward[at + 1] = forward[at + 2]
            forward[at + 2] = swap
    arrays[Mesh.ARRAY_INDEX] = forward
    return arrays
