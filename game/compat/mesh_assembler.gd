class_name MeshAssembler
extends RefCounted
## Turns a read OGRE mesh into a Godot mesh with PBR materials derived from the legacy
## `managedmaterials` declaration.
##
## Separate from VehicleBuilder because three different things need it and none of them
## is about vehicles: a flexbody, a rigid prop, and a wheel rim all arrive here as the
## same thing — a read mesh plus a material name — and leave as drawable geometry.


## Builds an ArrayMesh from a read OGRE mesh, with a material per submesh.
static func mesh_from(
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
            material_for(submesh["material"] as String, truck, mod_dir, dds_reader, textures)
        )
        surfaces += 1
    return null if surfaces == 0 else mesh


## UVs are used as the mesh stores them. A vertical flip is the usual OGRE-to-Godot
## correction and it was tried here, but measuring where the UVs actually land says
## otherwise: the hood samples a region 3.7x brighter unflipped (tools/uv_probe.gd). The
## vehicle simply has a black paint scheme, which is not the same problem as wrong UVs.


static func material_for(
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
