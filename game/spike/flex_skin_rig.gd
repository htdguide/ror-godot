class_name FlexSkinRig
extends RefCounted
## Builds the skinned mesh for the FlexBody spike and drives it through RenderingServer.
##
## Deliberately not Skeleton3D. A locator triad's frame is non-orthonormal: its columns
## carry the stretch and shear of the node triangle, which is what makes the deformation
## soft instead of rigid. Skeleton3D's pose API stores translation, rotation and scale,
## and a decomposition into those three discards shear silently. RenderingServer's
## skeleton takes a Transform3D and stores it as given, so the shear survives.
##
## The bone transform written each frame is the full skinning matrix, F_current *
## F_bind.inverse(). That is what the real bridge will write from C++, so this spike
## exercises the production path rather than a proxy for it.

var mesh: ArrayMesh
var mesh_instance: MeshInstance3D
var skeleton_rid: RID
var material: ShaderMaterial
var bind_inverse: Array[Transform3D] = []

## Half-size of the explicit instance bounds, in metres. Large enough that no pose in the
## spike leaves it.
const AABB_EXTENT: float = 200.0
## Rendered size of each sample, in pixels. Large enough that every sample is readable
## in the capture, small enough that samples do not overlap and hide each other.
const POINT_SIZE: float = 5.0


func build(
    world: Node3D, lattice: FlexLattice, shader_path: String, threshold_mm: float
) -> String:
    var shader: Shader = load(shader_path) as Shader
    if shader == null:
        return "cannot load shader %s" % shader_path
    material = ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("threshold_mm", threshold_mm)
    material.set_shader_parameter("point_size", POINT_SIZE)

    for transform: Transform3D in FlexReference.bone_transforms(
        lattice.node_rest, lattice, Vector3.ZERO
    ):
        bind_inverse.append(transform.affine_inverse())

    mesh = _build_mesh(lattice)
    # The instance is an ordinary node; only the skeleton is driven at the server level.
    # That is also how the bridge will be built, so the spike exercises the real path.
    mesh_instance = MeshInstance3D.new()
    mesh_instance.name = "FlexSpikeMesh"
    mesh_instance.mesh = mesh
    mesh_instance.material_override = material
    # A server-side skeleton has no Skeleton3D node to track the deformed bounds, so the
    # instance would be culled against its bind-pose bounds. They are given explicitly
    # and generously: culling is not what this spike measures.
    mesh_instance.custom_aabb = AABB(-Vector3.ONE * AABB_EXTENT, Vector3.ONE * AABB_EXTENT * 2.0)
    world.add_child(mesh_instance)

    skeleton_rid = RenderingServer.skeleton_create()
    RenderingServer.skeleton_allocate_data(skeleton_rid, lattice.bone_count())
    RenderingServer.instance_attach_skeleton(mesh_instance.get_instance(), skeleton_rid)
    set_pose(lattice.node_rest, lattice)
    return ""


## Writes one pose: the skinning matrix per bone, and the CPU reference position per
## vertex for the shader to compare against.
func set_pose(nodes: PackedVector3Array, lattice: FlexLattice) -> void:
    var frames: Array[Transform3D] = FlexReference.bone_transforms(nodes, lattice, Vector3.ZERO)
    for bone: int in frames.size():
        RenderingServer.skeleton_bone_set_transform(
            skeleton_rid, bone, frames[bone] * bind_inverse[bone]
        )
    var reference: PackedVector3Array = FlexReference.deform_all(nodes, lattice, Vector3.ZERO)
    mesh.clear_surfaces()
    _add_surface(lattice, reference)


## Displaces one bone without touching the CPU reference, to prove the measurement can
## see an error at all. A gate whose instrument always reads zero proves nothing.
func sabotage_bone(bone: int, offset: Vector3, lattice: FlexLattice, nodes: PackedVector3Array) -> void:
    var frames: Array[Transform3D] = FlexReference.bone_transforms(nodes, lattice, Vector3.ZERO)
    var broken: Transform3D = frames[bone]
    broken.origin += offset
    RenderingServer.skeleton_bone_set_transform(skeleton_rid, bone, broken * bind_inverse[bone])


func free_resources() -> void:
    if skeleton_rid.is_valid():
        RenderingServer.free_rid(skeleton_rid)
        skeleton_rid = RID()
    if mesh_instance != null and is_instance_valid(mesh_instance):
        mesh_instance.queue_free()
        mesh_instance = null


func _build_mesh(lattice: FlexLattice) -> ArrayMesh:
    var built: ArrayMesh = ArrayMesh.new()
    mesh = built
    _add_surface(lattice, FlexReference.deform_all(lattice.node_rest, lattice, Vector3.ZERO))
    return built


## One point per sample. Points rather than triangles because the gate reads the error a
## vertex carries; a triangle would interpolate three vertices' errors together and hide
## the worst one.
func _add_surface(lattice: FlexLattice, reference: PackedVector3Array) -> void:
    var count: int = lattice.vertex_count()
    var bones: PackedInt32Array = PackedInt32Array()
    var weights: PackedFloat32Array = PackedFloat32Array()
    var custom: PackedFloat32Array = PackedFloat32Array()
    bones.resize(count * 4)
    weights.resize(count * 4)
    custom.resize(count * 4)
    for i: int in count:
        bones[i * 4] = lattice.triad_of_vert[i]
        weights[i * 4] = 1.0
        custom[i * 4] = reference[i].x
        custom[i * 4 + 1] = reference[i].y
        custom[i * 4 + 2] = reference[i].z
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = lattice.vert_rest
    arrays[Mesh.ARRAY_BONES] = bones
    arrays[Mesh.ARRAY_WEIGHTS] = weights
    arrays[Mesh.ARRAY_CUSTOM0] = custom
    var format: int = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays, [], {}, format)
