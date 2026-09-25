class_name SkinnedFlexbody
extends RefCounted
## Drives a real vehicle's flexbody mesh through Godot's GPU skinning.
##
## This is ADR 0002 applied to an actual truck rather than a synthetic lattice: one bone
## per locator triad, the full affine triad frame written through RenderingServer because
## Skeleton3D's pose API would discard its shear, and an explicit custom AABB because a
## server-driven skeleton has no node tracking its deformed bounds.
##
## The mesh also carries the CPU reference position per vertex in CUSTOM0, so the same
## error shader that verified the spike can verify a real vehicle.

const AABB_EXTENT: float = 100.0

var mesh: ArrayMesh
var mesh_instance: MeshInstance3D
var skeleton_rid: RID
var triads: Array[Vector3i] = []
var binding: Dictionary = {}
var bind_inverse: Array[Transform3D] = []
var vertex_count: int = 0


## `vertices` are the mesh's placed rest positions in rig space.
func build(
    parent: Node3D,
    nodes: PackedVector3Array,
    forset: PackedInt32Array,
    vertices: PackedVector3Array,
    indices: PackedInt32Array,
    material: Material
) -> String:
    vertex_count = vertices.size()
    binding = FlexbodyBinder.bind(nodes, forset, vertices)
    triads = binding["triads"] as Array[Vector3i]
    if triads.is_empty():
        return "no locator triads: the mesh bound to no nodes"
    for frame: Transform3D in FlexbodyBinder.bone_transforms(nodes, triads):
        bind_inverse.append(frame.affine_inverse())

    mesh = ArrayMesh.new()
    _add_surface(vertices, indices, vertices)

    mesh_instance = MeshInstance3D.new()
    mesh_instance.name = "SkinnedFlexbody"
    mesh_instance.mesh = mesh
    if material != null:
        mesh_instance.material_override = material
    mesh_instance.custom_aabb = AABB(
        -Vector3.ONE * AABB_EXTENT, Vector3.ONE * AABB_EXTENT * 2.0
    )
    parent.add_child(mesh_instance)

    skeleton_rid = RenderingServer.skeleton_create()
    RenderingServer.skeleton_allocate_data(skeleton_rid, triads.size())
    RenderingServer.instance_attach_skeleton(mesh_instance.get_instance(), skeleton_rid)
    set_pose(nodes)
    return ""


## Writes one pose: the skinning matrix per bone, and the CPU reference per vertex.
func set_pose(nodes: PackedVector3Array) -> void:
    var frames: Array[Transform3D] = FlexbodyBinder.bone_transforms(nodes, triads)
    for bone: int in frames.size():
        RenderingServer.skeleton_bone_set_transform(
            skeleton_rid, bone, frames[bone] * bind_inverse[bone]
        )


## Replaces the reference stream, so the error shader compares against this pose.
func set_reference(nodes: PackedVector3Array, rest: PackedVector3Array, indices: PackedInt32Array) -> void:
    mesh.clear_surfaces()
    _add_surface(rest, indices, FlexbodyBinder.reference_positions(nodes, binding, triads))


func free_resources() -> void:
    if skeleton_rid.is_valid():
        RenderingServer.free_rid(skeleton_rid)
        skeleton_rid = RID()
    if mesh_instance != null and is_instance_valid(mesh_instance):
        mesh_instance.queue_free()
        mesh_instance = null


func _add_surface(
    vertices: PackedVector3Array, indices: PackedInt32Array, reference: PackedVector3Array
) -> void:
    var bone_of_vertex: PackedInt32Array = binding["bone_of_vertex"] as PackedInt32Array
    var bones: PackedInt32Array = PackedInt32Array()
    var weights: PackedFloat32Array = PackedFloat32Array()
    var custom: PackedFloat32Array = PackedFloat32Array()
    bones.resize(vertices.size() * 4)
    weights.resize(vertices.size() * 4)
    custom.resize(vertices.size() * 4)
    for i: int in vertices.size():
        bones[i * 4] = bone_of_vertex[i]
        weights[i * 4] = 1.0
        custom[i * 4] = reference[i].x
        custom[i * 4 + 1] = reference[i].y
        custom[i * 4 + 2] = reference[i].z

    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_BONES] = bones
    arrays[Mesh.ARRAY_WEIGHTS] = weights
    arrays[Mesh.ARRAY_CUSTOM0] = custom
    arrays[Mesh.ARRAY_INDEX] = indices
    mesh.add_surface_from_arrays(
        Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
        Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
    )
