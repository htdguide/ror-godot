class_name RorTerrainSkin
extends RefCounted
## Dresses a loaded Rigs of Rods terrain in its own textures.
##
## A terrain's look is four tiled textures blended by a splat map, and until now this project
## averaged each of them to one colour and painted that into Terrain3D's colour map. That is the
## right shape at a kilometre and wrong at a metre: La Paz came out as brown ground with a grey
## stripe where its road is, which is the terrain's palette and not the terrain.
##
## Terrain3D's control map holds two texture ids and a blend per texel, which is a smaller
## vocabulary than Ogre's four layers with an alpha each. So the layers are composited the way
## Ogre composites them — each layer laid over what is under it at its own alpha — and the two
## with the most coverage at that point are kept. Where three layers meet, the third is dropped;
## everywhere else this is what the terrain's author painted.
##
## The textures themselves are the mod's own DDS files, read by the extension's `DdsReader`
## because Godot handles DDS as an editor import format only.

## Terrain3D scales a texture by metres per repeat, as one over the tiling distance.
const MIN_TILE_M: float = 0.5
## How rough a loaded terrain's ground is. The mod's own specular maps are a legacy encoding
## this project does not read here; a dry, dusty ground is rough, and the shipped normal maps
## carry what relief there is.
const ROUGHNESS: float = 0.9


## The Terrain3D asset set for a terrain's splat layers, or null when Terrain3D is absent.
static func assets(terrain: RorTerrain) -> Object:
    if not ClassDB.class_exists("Terrain3DAssets"):
        return null
    var layers: Array[Dictionary] = terrain.layers()
    if layers.is_empty():
        return null
    var reader: RefCounted = ClassDB.instantiate("DdsReader") as RefCounted
    var textures: Array = []
    for index: int in layers.size():
        textures.append(_asset(index, layers[index], terrain.directory, reader))
    var out: Object = ClassDB.instantiate("Terrain3DAssets")
    out.set("texture_list", textures)
    return out


## One layer as a Terrain3D texture asset: the mod's albedo, its normal map, and the tiling the
## page file states in metres.
static func _asset(
    index: int, layer: Dictionary, directory: String, reader: RefCounted
) -> Object:
    var asset: Object = ClassDB.instantiate("Terrain3DTextureAsset")
    asset.set("id", index)
    asset.set("name", (layer["albedo"] as String).get_file().get_basename())
    var albedo: Texture2D = texture_of(directory.path_join(layer["albedo"] as String), reader)
    if albedo != null:
        asset.set("albedo_texture", albedo)
    var normal: Texture2D = texture_of(directory.path_join(layer["normal"] as String), reader)
    if normal != null:
        asset.set("normal_texture", normal)
    # The terrain's own colours, so nothing of this project's is multiplied over them.
    asset.set("albedo_color", Color.WHITE)
    asset.set("roughness", ROUGHNESS)
    asset.set("uv_scale", 1.0 / maxf(layer["tile_m"] as float, MIN_TILE_M))
    return asset


## A texture from a mod's files, DDS or otherwise. Null when it cannot be read.
static func texture_of(path: String, reader: RefCounted) -> Texture2D:
    var image: Image = image_of(path, reader)
    if image == null:
        return null
    return ImageTexture.create_from_image(image)


## The image behind one of a mod's texture files.
##
## DDS goes through the extension's reader, which hands the block-compressed payload back
## untouched; everything else goes through Godot. A compressed image is left compressed — the
## GPU wants it that way — and mipmaps are generated only where they can be.
static func image_of(path: String, reader: RefCounted) -> Image:
    if not FileAccess.file_exists(path):
        return null
    if path.get_extension().to_lower() != "dds":
        var plain: Image = Image.load_from_file(path)
        if plain != null:
            plain.generate_mipmaps()
        return plain
    if reader == null:
        return null
    var result: Dictionary = reader.read_file(path)
    if (result.get("error", "") as String) != "":
        return null
    var image: Image = Image.create_from_data(
        int(result["width"]), int(result["height"]), false,
        int(result["format"]) as Image.Format, result["data"] as PackedByteArray
    )
    if image != null and not image.is_compressed():
        image.generate_mipmaps()
    return image


## Which two of a terrain's layers are drawn at a point, and how they mix.
##
## Ogre lays each layer over what is under it at its own alpha, so a layer's share of the final
## picture is its own weight times whatever the layers above it left. That unrolling is here
## rather than in the shader because Terrain3D's control map stores the answer, not the layers.
static func control_of(coverage: PackedFloat32Array) -> Dictionary:
    var best: int = 0
    var second: int = 0
    var best_share: float = -1.0
    var second_share: float = -1.0
    for index: int in coverage.size():
        var share: float = coverage[index]
        if share > best_share:
            second = best
            second_share = best_share
            best = index
            best_share = share
        elif share > second_share:
            second = index
            second_share = share
    var total: float = best_share + maxf(second_share, 0.0)
    return {
        "base": best,
        "overlay": second,
        "blend": 0.0 if total <= 0.0 else clampf(maxf(second_share, 0.0) / total, 0.0, 1.0),
    }
