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
        var node: MeshInstance3D = _build_flexbody(
            result, truck, entry, mod_dir, dds_reader, textures
        )
        if node == null:
            skipped.append("%s (no geometry)" % entry["mesh"])
            continue
        root.add_child(node)
        built += 1

    return {
        "error": "",
        "root": root,
        "truck": truck,
        "built": built,
        "skipped": skipped,
        "textures": textures.size(),
    }


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
    material.albedo_color = Color(0.7, 0.7, 0.72)
    var declared: Dictionary = truck.managed_materials.get(material_name, {}) as Dictionary
    if declared.is_empty():
        return material

    var files: PackedStringArray = declared["textures"] as PackedStringArray
    if files.size() > 0:
        var albedo: Texture2D = _texture(mod_dir.path_join(files[0]), dds_reader, textures)
        if albedo != null:
            material.albedo_texture = albedo
            material.albedo_color = Color.WHITE
    # A specular map is a real roughness source. Inverted, because specular intensity and
    # roughness are opposites, and read from the red channel since these maps are grey.
    if files.size() > 2:
        var spec: Texture2D = _texture(mod_dir.path_join(files[2]), dds_reader, textures)
        if spec != null:
            material.roughness_texture = spec
            material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
            material.roughness = 1.0
    if (declared["effect"] as String).contains("transparent"):
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material


static func _texture(path: String, dds_reader: RefCounted, cache: Dictionary) -> Texture2D:
    if cache.has(path):
        return cache[path] as Texture2D
    if not FileAccess.file_exists(path):
        cache[path] = null
        return null
    var result: Dictionary = dds_reader.read_file(path)
    if (result.get("error", "") as String) != "":
        cache[path] = null
        return null
    var image: Image = Image.create_from_data(
        int(result["width"]), int(result["height"]), false,
        int(result["format"]) as Image.Format, result["data"] as PackedByteArray
    )
    if image == null:
        cache[path] = null
        return null
    image.generate_mipmaps()
    var texture: ImageTexture = ImageTexture.create_from_image(image)
    cache[path] = texture
    return texture
