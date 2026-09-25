class_name FlexLattice
extends RefCounted
## A synthetic node/beam lattice and a skinned mesh bound to it, for the FlexBody
## equivalence spike.
##
## Synthetic rather than a real truck on purpose: the question is whether Godot's
## skinning reproduces RoR's deformation algebra, and a synthetic lattice can be driven
## into deformations far more extreme than a truck ever reaches. If the identity holds
## here it holds for a vehicle.

const NODES_X: int = 13
const NODES_Y: int = 7
const NODES_Z: int = 11
const NODE_SPACING: float = 0.8
const VERTS_PER_CELL: int = 6
## Offset along the triad normal, in metres. This is the term that makes the deformation
## non-linear in node positions, so the spike must exercise it rather than leave it zero.
const NORMAL_OFFSET_RANGE: float = 0.25

var node_rest: PackedVector3Array = PackedVector3Array()
var vert_rest: PackedVector3Array = PackedVector3Array()
## Per vertex: the locator triad (ref, nx, ny) and its bind-space coordinates.
var loc_ref: PackedInt32Array = PackedInt32Array()
var loc_nx: PackedInt32Array = PackedInt32Array()
var loc_ny: PackedInt32Array = PackedInt32Array()
var loc_coords: PackedVector3Array = PackedVector3Array()
## Unique triad -> bone index, and the reverse mapping.
var triad_of_vert: PackedInt32Array = PackedInt32Array()
var triad_ref: PackedInt32Array = PackedInt32Array()
var triad_nx: PackedInt32Array = PackedInt32Array()
var triad_ny: PackedInt32Array = PackedInt32Array()


func build(rng: RandomNumberGenerator) -> void:
    _build_nodes()
    _build_vertices(rng)


func node_count() -> int:
    return node_rest.size()


func vertex_count() -> int:
    return vert_rest.size()


func bone_count() -> int:
    return triad_ref.size()


func _build_nodes() -> void:
    for z: int in NODES_Z:
        for y: int in NODES_Y:
            for x: int in NODES_X:
                node_rest.append(
                    Vector3(float(x), float(y), float(z)) * NODE_SPACING
                )


func _node_index(x: int, y: int, z: int) -> int:
    return x + y * NODES_X + z * NODES_X * NODES_Y


## Places vertices around each lattice cell and binds each one to a triad, exactly the
## way FlexBody's spawner does: pick three nodes, then record the vertex position in the
## frame those three nodes span.
func _build_vertices(rng: RandomNumberGenerator) -> void:
    var triad_key_to_bone: Dictionary = {}
    for z: int in NODES_Z - 1:
        for y: int in NODES_Y - 1:
            for x: int in NODES_X - 1:
                var ref: int = _node_index(x, y, z)
                var nx: int = _node_index(x + 1, y, z)
                var ny: int = _node_index(x, y + 1, z)
                var key: String = "%d_%d_%d" % [ref, nx, ny]
                if not triad_key_to_bone.has(key):
                    triad_key_to_bone[key] = triad_ref.size()
                    triad_ref.append(ref)
                    triad_nx.append(nx)
                    triad_ny.append(ny)
                var bone: int = triad_key_to_bone[key] as int
                for _i: int in VERTS_PER_CELL:
                    _add_vertex(ref, nx, ny, bone, rng)


func _add_vertex(ref: int, nx: int, ny: int, bone: int, rng: RandomNumberGenerator) -> void:
    var coords: Vector3 = Vector3(
        rng.randf_range(-0.2, 1.2),
        rng.randf_range(-0.2, 1.2),
        rng.randf_range(-NORMAL_OFFSET_RANGE, NORMAL_OFFSET_RANGE)
    )
    loc_ref.append(ref)
    loc_nx.append(nx)
    loc_ny.append(ny)
    loc_coords.append(coords)
    triad_of_vert.append(bone)
    vert_rest.append(FlexReference.deform_vertex(node_rest, ref, nx, ny, coords, Vector3.ZERO))
