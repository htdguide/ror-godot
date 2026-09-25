class_name VehicleBuilder
extends RefCounted
## Builds a renderable vehicle from an unmodified Rigs of Rods mod.
##
## Reads the rig, places each flexbody mesh into rig space with upstream's construction,
## and gives it a material derived from the legacy `managedmaterials` declaration. The
## mod is not modified, converted or re-exported: this is the compatibility promise being
## exercised rather than described.
##
## Materials here are deliberately minimal — albedo, plus roughness from the specular map
## where the mod supplies one. The material classification of ADR 0001 lands in M2; this
## is the geometry and texture path it will build on.

const TEXTURE_CACHE_HINT: int = 0


static func build(mod_dir: String, truck_file: String) -> Dictionary:
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_file(mod_dir.path_join(truck_file))
    if error != "":
        return {"error": error}
    var mesh_reader: RefCounted = ClassDB.instantiate("OgreMeshReader") as RefCounted
    var dds_reader: RefCounted = ClassDB.instantiate("DdsReader") as RefCounted
    if mesh_reader == null or dds_reader == null:
        return {"error": "the GDExtension did not load"}

    var root: Node3D = Node3D.new()
    root.name = "Vehicle"
    # The actor frame is computed but NOT applied to the render path. Wiring it —  frame
    # on the root, bones and wheels in actor-local space — makes two wheels render out on
    # open ground, while vehicle_assembly measures every part and every wheel's drawn
    # geometry within a millimetre of its rig position. The gate and the image disagree,
    # so one of them is wrong, and the gate is the thing to fix first: a gate that passes
    # while the render is visibly broken is worse than no gate at all. See
    # docs/architecture/bridge.md.
    var actor: Transform3D = ActorFrame.of(truck.nodes, truck.camera_nodes)
    root.transform = actor
    var render_frame: Transform3D = actor
    var parts: Array[SkinnedFlexbody] = []
    var textures: Dictionary = {}
    var built: int = 0
    var skipped: PackedStringArray = PackedStringArray()

    for entry: Dictionary in truck.flexbodies:
        var mesh_path: String = mod_dir.path_join(entry["mesh"] as String)
        if not FileAccess.file_exists(mesh_path):
            skipped.append("%s (missing)" % entry["mesh"])
            continue
        var result: Dictionary = mesh_reader.read_file(mesh_path)
        if (result.get("error", "") as String) != "":
            skipped.append("%s (%s)" % [entry["mesh"], result["error"]])
            continue
        var part: SkinnedFlexbody = _build_skinned_flexbody(
            root, result, truck, entry, render_frame, mod_dir, dds_reader, textures
        )
        if part == null:
            skipped.append("%s (no geometry)" % entry["mesh"])
            continue
        parts.append(part)
        built += 1

    var wheels_built: int = 0
    var wheel_nodes: Array[Node3D] = []
    for index: int in truck.wheels.size():
        var wheel: Dictionary = truck.wheels[index]
        var node: Node3D = _build_wheel(
            wheel, truck, render_frame, mod_dir, mesh_reader, dds_reader, textures
        )
        if node == null:
            skipped.append("wheel %s" % wheel["mesh"])
            continue
        # Names must be unique or Godot discards them entirely, replacing the node name
        # with a generated one, and anything that finds nodes by name stops working.
        node.name = "Wheel_%d_%s" % [index, wheel["side"]]
        root.add_child(node)
        wheel_nodes.append(node)
        wheels_built += 1

    return {
        "error": "",
        "root": root,
        "actor": actor,
        # How a rig-space point becomes a point in the vehicle's local space. Declared so
        # checks can place rig coordinates without knowing how the frame is wired.
        "rig_to_local": render_frame.affine_inverse(),
        # Where the frame's origin was when the vehicle was built, so a later pose can
        # tell the rig's own motion apart from where a caller has placed the vehicle.
        "frame_origin": render_frame.origin,
        "parts": parts,
        "wheel_nodes": wheel_nodes,
        "wheels": wheels_built,
        "truck": truck,
        "built": built,
        "skipped": skipped,
        "textures": textures.size(),
    }


## World bounds of everything a built vehicle draws.
static func world_bounds(root: Node3D) -> AABB:
    var bounds: AABB = AABB()
    var started: bool = false
    for node: Node in _descendants(root):
        var mesh_instance: MeshInstance3D = node as MeshInstance3D
        if mesh_instance == null or mesh_instance.mesh == null:
            continue
        var world: AABB = mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
        bounds = world if not started else bounds.merge(world)
        started = true
    return bounds


static func _descendants(node: Node) -> Array[Node]:
    var out: Array[Node] = []
    for child: Node in node.get_children():
        out.append(child)
        out.append_array(_descendants(child))
    return out


## Drives the whole vehicle to a node pose: the frame on the root, deformation in the
## bones. This is the per-frame entry point the solver will call.
static func apply_pose(built: Dictionary, truck: TruckParser, nodes: PackedVector3Array) -> void:
    var actor: Transform3D = ActorFrame.of(nodes, truck.camera_nodes)
    var root: Node3D = built["root"] as Node3D
    # Keep whatever the caller did to place the vehicle for a camera, and change only the
    # part of the transform the rig owns.
    var placement: Vector3 = root.transform.origin - built["frame_origin"] as Vector3
    root.transform = Transform3D(actor.basis, actor.origin + placement)
    built["frame_origin"] = actor.origin

    for part: SkinnedFlexbody in built["parts"] as Array[SkinnedFlexbody]:
        part.set_pose(nodes, actor, false)

    # Wheels follow their own axle nodes, so suspension travel moves them.
    var to_local: Transform3D = actor.affine_inverse()
    var wheel_nodes: Array[Node3D] = built["wheel_nodes"] as Array[Node3D]
    for i: int in mini(wheel_nodes.size(), truck.wheels.size()):
        wheel_nodes[i].transform = to_local * WheelBuilder.rim_transform(nodes, truck.wheels[i])


## One flexbody, bound to its locator triads and skinned.
static func _build_skinned_flexbody(
    root: Node3D,
    result: Dictionary,
    truck: TruckParser,
    entry: Dictionary,
    actor: Transform3D,
    mod_dir: String,
    dds_reader: RefCounted,
    textures: Dictionary
) -> SkinnedFlexbody:
    var placement: Transform3D = FlexbodyBinder.placement(truck.nodes, entry)
    var vertices: PackedVector3Array = PackedVector3Array()
    var indices: PackedInt32Array = PackedInt32Array()
    var uvs: PackedVector2Array = PackedVector2Array()
    var material: Material = null
    for submesh: Dictionary in result["submeshes"] as Array:
        var positions: PackedVector3Array = submesh["positions"] as PackedVector3Array
        if positions.is_empty():
            continue
        var offset: int = vertices.size()
        for vertex: Vector3 in positions:
            vertices.append(placement * vertex)
        for index: int in submesh["indices"] as PackedInt32Array:
            indices.append(index + offset)
        var submesh_uvs: PackedVector2Array = submesh["uvs"] as PackedVector2Array
        for i: int in positions.size():
            uvs.append(submesh_uvs[i] if i < submesh_uvs.size() else Vector2.ZERO)
        if material == null:
            material = _material_for(
                submesh["material"] as String, truck, mod_dir, dds_reader, textures
            )
    if vertices.is_empty():
        return null

    var part: SkinnedFlexbody = SkinnedFlexbody.new()
    var error: String = part.build(
        root, truck.nodes, entry["forset"] as PackedInt32Array, vertices, indices, material, uvs
    )
    if error != "":
        return null
    part.mesh_instance.name = (entry["mesh"] as String).get_basename()
    part.set_pose(truck.nodes, actor, false)
    return part


## A wheel is a rim mesh posed by the axle nodes plus a tyre swept around them.
static func _build_wheel(
    wheel: Dictionary,
    truck: TruckParser,
    render_frame: Transform3D,
    mod_dir: String,
    mesh_reader: RefCounted,
    dds_reader: RefCounted,
    textures: Dictionary
) -> Node3D:
    var holder: Node3D = Node3D.new()
    holder.transform = render_frame.affine_inverse() * WheelBuilder.rim_transform(
        truck.nodes, wheel
    )

    var rim_path: String = mod_dir.path_join(wheel["mesh"] as String)
    if FileAccess.file_exists(rim_path):
        var result: Dictionary = mesh_reader.read_file(rim_path)
        if (result.get("error", "") as String) == "":
            var rim: MeshInstance3D = MeshInstance3D.new()
            rim.name = "Rim"
            rim.mesh = _mesh_from(result, truck, mod_dir, dds_reader, textures)
            if rim.mesh != null:
                holder.add_child(rim)

    var tyre: MeshInstance3D = MeshInstance3D.new()
    tyre.name = "Tyre"
    tyre.mesh = WheelBuilder.build_tyre(truck.nodes, wheel)
    tyre.material_override = _material_for(
        wheel["material"] as String, truck, mod_dir, dds_reader, textures
    )
    holder.add_child(tyre)
    return holder


## Builds an ArrayMesh from a read OGRE mesh, with a material per submesh.
static func _mesh_from(
    result: Dictionary,
    truck: TruckParser,
    mod_dir: String,
    dds_reader: RefCounted,
    textures: Dictionary
) -> ArrayMesh:
    var mesh: ArrayMesh = ArrayMesh.new()
    var surfaces: int = 0
    for submesh: Dictionary in result["submeshes"] as Array:
        var positions: PackedVector3Array = submesh["positions"] as PackedVector3Array
        var indices: PackedInt32Array = submesh["indices"] as PackedInt32Array
        if positions.is_empty() or indices.is_empty():
            continue
        var arrays: Array = []
        arrays.resize(Mesh.ARRAY_MAX)
        arrays[Mesh.ARRAY_VERTEX] = positions
        var normals: PackedVector3Array = submesh["normals"] as PackedVector3Array
        if normals.size() == positions.size():
            arrays[Mesh.ARRAY_NORMAL] = normals
        var uvs: PackedVector2Array = submesh["uvs"] as PackedVector2Array
        if uvs.size() == positions.size():
            arrays[Mesh.ARRAY_TEX_UV] = uvs
        arrays[Mesh.ARRAY_INDEX] = indices
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        mesh.surface_set_material(
            surfaces,
            _material_for(submesh["material"] as String, truck, mod_dir, dds_reader, textures)
        )
        surfaces += 1
    return null if surfaces == 0 else mesh


static func _build_flexbody(
    result: Dictionary,
    truck: TruckParser,
    entry: Dictionary,
    mod_dir: String,
    dds_reader: RefCounted,
    textures: Dictionary
) -> MeshInstance3D:
    var mesh: ArrayMesh = ArrayMesh.new()
    var surfaces: int = 0
    for submesh: Dictionary in result["submeshes"] as Array:
        var positions: PackedVector3Array = submesh["positions"] as PackedVector3Array
        var indices: PackedInt32Array = submesh["indices"] as PackedInt32Array
        if positions.is_empty() or indices.is_empty():
            continue
        var arrays: Array = []
        arrays.resize(Mesh.ARRAY_MAX)
        arrays[Mesh.ARRAY_VERTEX] = positions
        var normals: PackedVector3Array = submesh["normals"] as PackedVector3Array
        if normals.size() == positions.size():
            arrays[Mesh.ARRAY_NORMAL] = normals
        var uvs: PackedVector2Array = submesh["uvs"] as PackedVector2Array
        if uvs.size() == positions.size():
            arrays[Mesh.ARRAY_TEX_UV] = uvs
        arrays[Mesh.ARRAY_INDEX] = indices
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        mesh.surface_set_material(
            surfaces,
            _material_for(submesh["material"] as String, truck, mod_dir, dds_reader, textures)
        )
        surfaces += 1
    if surfaces == 0:
        return null

    var node: MeshInstance3D = MeshInstance3D.new()
    node.name = (entry["mesh"] as String).get_basename()
    node.mesh = mesh
    node.transform = FlexbodyBinder.placement(truck.nodes, entry)
    return node


## UVs are used as the mesh stores them. A vertical flip is the usual OGRE-to-Godot
## correction and it was tried here, but measuring where the UVs actually land says
## otherwise: the hood samples a region 3.7x brighter unflipped (tools/uv_probe.gd). The
## vehicle simply has a black paint scheme, which is not the same problem as wrong UVs.


static func _material_for(
    material_name: String,
    truck: TruckParser,
    mod_dir: String,
    dds_reader: RefCounted,
    textures: Dictionary
) -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    var declared: Dictionary = truck.managed_materials.get(material_name, {}) as Dictionary
    var classified: Dictionary = MaterialClass.classify(material_name, declared)
    MaterialClass.apply(material, classified["class"] as String)
    material.albedo_color = Color(0.7, 0.7, 0.72)
    if declared.is_empty():
        return material

    var files: PackedStringArray = declared["textures"] as PackedStringArray
    if files.size() > 0:
        var albedo: Texture2D = _texture(mod_dir.path_join(files[0]), dds_reader, textures)
        if albedo != null:
            material.albedo_texture = albedo
            material.albedo_color = Color.WHITE
    # A specular map is authored data, so it is used where the mod supplies one and the
    # class default stands in where it does not.
    if files.size() > 2:
        var roughness: Texture2D = _roughness_texture(
            mod_dir.path_join(files[2]), dds_reader, textures
        )
        if roughness != null:
            material.roughness_texture = roughness
            material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
            material.roughness = 1.0
    return material


## What class a material would be given, without building anything. For gates and tools.
static func classify_materials(truck: TruckParser) -> Dictionary:
    var out: Dictionary = {}
    for material_name: String in truck.managed_materials.keys():
        out[material_name] = MaterialClass.classify(
            material_name, truck.managed_materials[material_name] as Dictionary
        )
    return out


## A roughness map derived from a legacy specular map, cached like any other texture.
static func _roughness_texture(
    path: String, dds_reader: RefCounted, cache: Dictionary
) -> Texture2D:
    var key: String = path + "#roughness"
    if cache.has(key):
        return cache[key] as Texture2D
    var source: Image = _image(path, dds_reader)
    if source == null:
        cache[key] = null
        return null
    var image: Image = MaterialClass.roughness_from_specular(source)
    image.generate_mipmaps()
    var texture: ImageTexture = ImageTexture.create_from_image(image)
    cache[key] = texture
    return texture


## Decodes a DDS to an Image, without building a texture from it.
static func _image(path: String, dds_reader: RefCounted) -> Image:
    if not FileAccess.file_exists(path):
        return null
    var result: Dictionary = dds_reader.read_file(path)
    if (result.get("error", "") as String) != "":
        return null
    return Image.create_from_data(
        int(result["width"]), int(result["height"]), false,
        int(result["format"]) as Image.Format, result["data"] as PackedByteArray
    )


static func _texture(path: String, dds_reader: RefCounted, cache: Dictionary) -> Texture2D:
    if cache.has(path):
        return cache[path] as Texture2D
    var image: Image = _image(path, dds_reader)
    if image == null:
        cache[path] = null
        return null
    image.generate_mipmaps()
    var texture: ImageTexture = ImageTexture.create_from_image(image)
    cache[path] = texture
    return texture
