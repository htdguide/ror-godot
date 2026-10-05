class_name MeshAssembler
extends RefCounted
## Turns a read OGRE mesh into a Godot mesh with PBR materials derived from the legacy
## `managedmaterials` declaration.
##
## Separate from VehicleBuilder because three different things need it and none of them
## is about vehicles: a flexbody, a rigid prop, and a wheel rim all arrive here as the
## same thing — a read mesh plus a material name — and leave as drawable geometry.


## Builds an ArrayMesh from a read OGRE mesh, with a material per submesh.
## `scripts` is the pack's Ogre `.material` declarations, from `OgreMaterial.read_directory`.
## Passed in rather than read here, and rather than cached on the class: a cache on the class is
## process-global state, which `static_state` exists to refuse.
static func mesh_from(
    result: Dictionary,
    truck: TruckParser,
    mod_dir: String,
    dds_reader: RefCounted,
    textures: Dictionary,
    scripts: Dictionary = {}
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
            material_for(
                submesh["material"] as String, truck, mod_dir, dds_reader, textures, scripts
            )
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
    textures: Dictionary,
    scripts: Dictionary = {}
) -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    var declared: Dictionary = truck.managed_materials.get(material_name, {}) as Dictionary
    if declared.is_empty():
        # A vehicle declares some of its materials in the truck file and the rest in an Ogre
        # `.material` script beside it, and a mesh does not know or care which. The Mazda 626
        # declares thirteen in `managedmaterials` and ten more in `mazda626gf.material` — its
        # paint, its headlights, its indicators, its brake and fog lights — and every mesh that
        # asked for one of those got a plain grey material with no texture on it. Terrain objects
        # have read these scripts since they were written; vehicles never did.
        declared = scripts.get(material_name, {}) as Dictionary
    var classified: Dictionary = MaterialClass.classify(material_name, declared)
    MaterialClass.apply(material, classified["class"] as String)
    # Which declaration this surface was built from. A vehicle's `materialflarebindings` names a
    # material and expects the lamp to light it, and by the time the meshes are built nothing else
    # remembers which surface came from which name. See `MaterialFlares`.
    material.set_meta("ogre_material", material_name)
    material.albedo_color = Color(0.7, 0.7, 0.72)
    if declared.is_empty():
        return material

    var files: PackedStringArray = declared["textures"] as PackedStringArray
    if files.size() > 0:
        var albedo: Texture2D = texture(
            RorContentPath.find(files[0], mod_dir), dds_reader, textures
        )
        if albedo != null:
            material.albedo_texture = albedo
            material.albedo_color = Color.WHITE
    elif declared.get("has_diffuse", false) as bool:
        # A material with no texture and a colour of its own is a flat painted pass, not a
        # failure, and the loader's placeholder grey is wrong for it. `get` rather than index:
        # a vehicle's `managedmaterials` lines are parsed by the truck reader, which has no
        # such key, and only the Ogre scripts beside it carry one.
        material.albedo_color = declared["diffuse"] as Color
    # A specular map is authored data, so it is used where the mod supplies one and the
    # class default stands in where it does not. **Which slot it is in depends on the effect** —
    # see `_specular_slot`.
    var slot: int = _specular_slot(declared.get("effect", "") as String)
    if slot >= 0 and files.size() > slot:
        var roughness: Texture2D = _roughness_texture(
            RorContentPath.find(files[slot], mod_dir), dds_reader, textures
        )
        if roughness != null:
            material.roughness_texture = roughness
            material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
            material.roughness = 1.0
    return material


## Which of a managed material's textures is its specular map.
##
## The slot is not fixed: upstream reads a different argument per effect —
## `RigDef_Parser.cpp`, `ParseManagedMaterials`:
##
##     if (managed_mat.type == MESH_STANDARD || managed_mat.type == MESH_TRANSPARENT)
##     {
##         if (m_num_args > 3) { managed_mat.specular_map = this->GetArgManagedTex(3); }
##     }
##     else if (... FLEXMESH_STANDARD || ... FLEXMESH_TRANSPARENT)
##     {
##         if (m_num_args > 3) { managed_mat.damaged_diffuse_map = this->GetArgManagedTex(3); }
##         if (m_num_args > 4) { managed_mat.specular_map        = this->GetArgManagedTex(4); }
##     }
##
## A flexmesh carries a damaged diffuse between the two and a mesh does not, so counted from the
## first texture the specular map is at 2 for one and **1** for the other. This project read 2 for
## both, so every `mesh_standard` material in the library lost its specular map: the hero truck's
## rims, its steering wheel, its tacho, its speedo and its flares all drew as flat matte shapes,
## which is what "the rims are black plate caps" looks like. 11 materials across this library
## declare one that way.
##
## An Ogre `.material` script has no such convention — its textures are whatever `texture_unit`
## lines it holds, in order — so nothing is assumed for one. 95 scripts here name three or more
## textures and what the third is differs by author.
static func _specular_slot(effect: String) -> int:
    var kind: String = effect.to_lower()
    if kind.begins_with("flexmesh_"):
        return 2
    if kind.begins_with("mesh_"):
        return 1
    return -1


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
    if not image.is_compressed():
        image.generate_mipmaps()
    var texture: ImageTexture = ImageTexture.create_from_image(image)
    cache[key] = texture
    return texture


## Decodes a DDS to an Image, without building a texture from it.
static func _image(path: String, dds_reader: RefCounted) -> Image:
    return DdsImage.read(path, dds_reader)


## One texture from a DDS on disk, decoded once per cache. Public because a lamp's sprite is a
## texture out of the game's own resources rather than off a mesh, and it is read the same way.
static func texture(path: String, dds_reader: RefCounted, cache: Dictionary) -> Texture2D:
    if cache.has(path):
        return cache[path] as Texture2D
    var image: Image = _image(path, dds_reader)
    if image == null:
        cache[path] = null
        return null
    # A block-compressed image already carries whatever mipmaps it shipped with, and Godot
    # refuses to generate more: "Cannot generate mipmaps from compressed image formats".
    #
    # Asking anyway is not harmless. It is how the Mazda 626 arrived with no bodywork — a `.car`
    # whose textures are DXT, where every one of them errored here and the panels drew untextured
    # while the seats and the dash, which are not, came out fine. `RorTerrainSkin` has guarded
    # this for as long as it has existed; the vehicle path never did.
    if not image.is_compressed():
        image.generate_mipmaps()
    var texture: ImageTexture = ImageTexture.create_from_image(image)
    cache[path] = texture
    return texture
