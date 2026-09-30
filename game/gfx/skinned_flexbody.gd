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

## Slack on the posed bounds. The bounds are recomputed every pose, so this only has to
## cover one frame of deformation, and a panel does not travel far in one frame. It is
## generous anyway: too tight and the renderer culls a vehicle that is still on screen,
## which is a far worse failure than a slightly conservative box.
const BOUNDS_MARGIN: float = 0.5

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
## Rest bounds of the vertices belonging to each bone, so a pose's bounds cost one
## transform per bone rather than one per vertex.
var _bone_rest_bounds: Array[AABB] = []

var _uvs: PackedVector2Array = PackedVector2Array()
var _normals: PackedVector3Array = PackedVector3Array()


## `vertices` are the mesh's placed rest positions in rig space.
func build(
    parent: Node3D,
    nodes: PackedVector3Array,
    forset: PackedInt32Array,
    vertices: PackedVector3Array,
    indices: PackedInt32Array,
    material: Material,
    uvs: PackedVector2Array = PackedVector2Array(),
    normals: PackedVector3Array = PackedVector3Array()
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
    _normals = normals
    mesh = ArrayMesh.new()
    _add_surface(vertices, indices, vertices)

    mesh_instance = MeshInstance3D.new()
    mesh_instance.name = "SkinnedFlexbody"
    mesh_instance.mesh = mesh
    if material != null:
        mesh_instance.material_override = material
    _build_bone_rest_bounds()
    parent.add_child(mesh_instance)

    skeleton_rid = RenderingServer.skeleton_create()
    RenderingServer.skeleton_allocate_data(skeleton_rid, triads.size())
    _attach_skeleton()
    # A visual instance attached to a skeleton while it is outside the scene tree loses
    # that attachment when it enters one, and then draws unskinned with no error anywhere.
    # Re-attaching on entry costs nothing and makes the class independent of whether its
    # parent was in the tree when it was built.
    mesh_instance.tree_entered.connect(_attach_skeleton)
    set_pose(nodes)
    return ""


func _attach_skeleton() -> void:
    if mesh_instance != null and skeleton_rid.is_valid():
        RenderingServer.instance_attach_skeleton(mesh_instance.get_instance(), skeleton_rid)


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
    _update_bounds()


## Groups the rest vertices by the bone that moves them. A bone is a rigid transform, so
## the posed bounds of its vertices are that transform applied to their rest bounds.
func _build_bone_rest_bounds() -> void:
    var bone_of_vertex: PackedInt32Array = binding["bone_of_vertex"] as PackedInt32Array
    var started: PackedByteArray = PackedByteArray()
    started.resize(triads.size())
    _bone_rest_bounds.resize(triads.size())
    for i: int in rest_vertices.size():
        var bone: int = bone_of_vertex[i]
        if started[bone] == 0:
            _bone_rest_bounds[bone] = AABB(rest_vertices[i], Vector3.ZERO)
            started[bone] = 1
        else:
            _bone_rest_bounds[bone] = _bone_rest_bounds[bone].expand(rest_vertices[i])
    for bone: int in triads.size():
        if started[bone] == 0:
            _bone_rest_bounds[bone] = AABB()


## Sets the instance's bounds to where this pose actually put the geometry.
##
## A server-driven skeleton has no node tracking its deformed bounds, so without this the
## instance reports its rest mesh's bounds. Those are in rig space while the skinned
## vertices are in actor-local space, which makes every measurement taken from the
## vehicle's bounds -- camera framing, the driver's eye, ground placement -- disagree with
## what is on screen by the whole offset between the two spaces.
func _update_bounds() -> void:
    if mesh_instance == null or _bone_rest_bounds.is_empty():
        return
    var bounds: AABB = AABB()
    var started: bool = false
    for bone: int in _bone_rest_bounds.size():
        var rest: AABB = _bone_rest_bounds[bone]
        if rest.size == Vector3.ZERO and rest.position == Vector3.ZERO:
            continue
        var posed: AABB = RenderingServer.skeleton_bone_get_transform(skeleton_rid, bone) * rest
        bounds = posed if not started else bounds.merge(posed)
        started = true
    if not started:
        return
    mesh_instance.custom_aabb = bounds.grow(BOUNDS_MARGIN)


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
    # Without normals a surface has no surface orientation to light, so it shades by
    # whatever the shader's default normal happens to be: panels read flat, self-shadowing
    # never happens, and from the side away from the sun the vehicle looks lit through.
    # Godot skins these with the same bone transforms as the positions.
    if _normals.size() == vertices.size():
        arrays[Mesh.ARRAY_NORMAL] = _normals
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
