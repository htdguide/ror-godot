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
## Rest positions, kept so the rendered position of a vertex can be computed
## independently of the GPU and checked against it.
var rest_vertices: PackedVector3Array = PackedVector3Array()

var _uvs: PackedVector2Array = PackedVector2Array()


## `vertices` are the mesh's placed rest positions in rig space.
func build(
    parent: Node3D,
    nodes: PackedVector3Array,
    forset: PackedInt32Array,
    vertices: PackedVector3Array,
    indices: PackedInt32Array,
    material: Material,
    uvs: PackedVector2Array = PackedVector2Array()
) -> String:
    vertex_count = vertices.size()
    rest_vertices = vertices
    binding = FlexbodyBinder.bind(nodes, forset, vertices)
    triads = binding["triads"] as Array[Vector3i]
    if triads.is_empty():
        return "no locator triads: the mesh bound to no nodes"
    for frame: Transform3D in FlexbodyBinder.bone_transforms(nodes, triads):
        bind_inverse.append(frame.affine_inverse())

    _uvs = uvs
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


## Writes one pose. With an actor frame, bone transforms are expressed in actor-local
## space and the frame itself goes on the instance, so rigid motion of the whole vehicle
## lives in the instance transform where the renderer can see it. Without one, bones are
## written in world space and the vehicle has no orientation of its own.
func set_pose(
    nodes: PackedVector3Array,
    actor: Transform3D = Transform3D.IDENTITY,
    apply_to_instance: bool = true
) -> void:
    var to_local: Transform3D = actor.affine_inverse()
    var frames: Array[Transform3D] = FlexbodyBinder.bone_transforms(nodes, triads)
    for bone: int in frames.size():
        RenderingServer.skeleton_bone_set_transform(
            skeleton_rid, bone, to_local * frames[bone] * bind_inverse[bone]
        )
    # A part inside a vehicle leaves the frame to the vehicle root, or it would be
    # applied twice. A standalone part carries it itself.
    if apply_to_instance and mesh_instance != null:
        mesh_instance.transform = actor


## The actor-local bone transforms for a pose, without writing them. Used to check that
## rigid motion leaves them untouched, which is the property that keeps motion vectors
## meaningful.
func local_bone_transforms(
    nodes: PackedVector3Array, actor: Transform3D
) -> Array[Transform3D]:
    var to_local: Transform3D = actor.affine_inverse()
    var out: Array[Transform3D] = []
    var frames: Array[Transform3D] = FlexbodyBinder.bone_transforms(nodes, triads)
    for bone: int in frames.size():
        out.append(to_local * frames[bone] * bind_inverse[bone])
    return out


## Replaces the reference stream, so the error shader compares against this pose.
func set_reference(nodes: PackedVector3Array, rest: PackedVector3Array, indices: PackedInt32Array) -> void:
    mesh.clear_surfaces()
    _add_surface(rest, indices, FlexbodyBinder.reference_positions(nodes, binding, triads))


## Where a vertex actually lands, composed the way the engine does it:
## instance_global_transform * bone_transform * vertex, as measured by
## skinning_transform_semantics.
func rendered_position(vertex_index: int) -> Vector3:
    var bone: int = (binding["bone_of_vertex"] as PackedInt32Array)[vertex_index]
    var bone_transform: Transform3D = RenderingServer.skeleton_bone_get_transform(
        skeleton_rid, bone
    )
    return mesh_instance.global_transform * (bone_transform * rest_vertices[vertex_index])


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
    if _uvs.size() == vertices.size():
        arrays[Mesh.ARRAY_TEX_UV] = _uvs
    arrays[Mesh.ARRAY_BONES] = bones
    arrays[Mesh.ARRAY_WEIGHTS] = weights
    arrays[Mesh.ARRAY_CUSTOM0] = custom
    arrays[Mesh.ARRAY_INDEX] = indices
    mesh.add_surface_from_arrays(
        Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
        Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
    )
