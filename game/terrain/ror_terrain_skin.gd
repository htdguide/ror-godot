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
## Terrain3D samples a texture at `world.xz * uv_scale - 0.5`: every texture is half a tile out
## from where the world says it is. On ordinary ground nobody could tell. La Paz's road texture is
## a whole cross-section — shoulder, white edge line, double yellow, edge line, shoulder — so half
## a tile puts the centre line at the kerb, which a session reported as the road looking stretched
## with one wide lane and the separation line off to the side.
##
## The shader's offset cannot be changed per texture, so the texture is rolled by that much
## instead, which cancels it exactly. Measured on La Paz's road: at 0.0 the centre line lands
## 5.10 m from the middle of the asphalt, at 0.25 2.55 m, at 0.5 0.35 m.
const UV_PHASE: float = 0.5
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
    # Every texture in a Terrain3D array has to be the same size, and a terrain's layers routinely
    # are not: La Paz ships four 512-square layers and works, Russia ships 640s beside 512s and
    # Starling Island a 2048 beside a 512, and both render as flat white ground — the array is
    # rejected whole, so no layer gets a texture rather than the odd one out being dropped.
    #
    # Ogre has no such rule, so the mods are correct and the constraint is this renderer's. Every
    # layer is brought to one size, the largest, so the sharpest texture a terrain ships is the
    # one that sets the standard rather than being thrown away by the smallest.
    var size: Vector2i = _common_size(layers, terrain.directory, reader)
    var textures: Array = []
    for index: int in layers.size():
        textures.append(_asset(index, layers[index], terrain.directory, reader, size))
    var out: Object = ClassDB.instantiate("Terrain3DAssets")
    out.set("texture_list", textures)
    return out


## One layer as a Terrain3D texture asset: the mod's albedo, its normal map, and the tiling the
## page file states in metres.
## The size every layer is brought to: the largest any of them ships.
static func _common_size(
    layers: Array[Dictionary], directory: String, reader: RefCounted
) -> Vector2i:
    var size: Vector2i = Vector2i.ZERO
    for layer: Dictionary in layers:
        for key: String in ["albedo", "normal"]:
            var image: Image = image_of(directory.path_join(layer[key] as String), reader)
            if image == null:
                continue
            size.x = maxi(size.x, image.get_width())
            size.y = maxi(size.y, image.get_height())
    return size


static func _asset(
    index: int, layer: Dictionary, directory: String, reader: RefCounted, size: Vector2i
) -> Object:
    var asset: Object = ClassDB.instantiate("Terrain3DTextureAsset")
    asset.set("id", index)
    asset.set("name", (layer["albedo"] as String).get_file().get_basename())
    var albedo: Texture2D = tiling_texture_of(
        directory.path_join(layer["albedo"] as String), reader, size
    )
    if albedo != null:
        asset.set("albedo_texture", albedo)
    var normal: Texture2D = tiling_texture_of(
        directory.path_join(layer["normal"] as String), reader, size
    )
    if normal != null:
        asset.set("normal_texture", normal)
    # The terrain's own colours, so nothing of this project's is multiplied over them.
    asset.set("albedo_color", Color.WHITE)
    asset.set("roughness", ROUGHNESS)
    # Terrain3D's uv_scale is not one over the tiling distance: measured against a road whose
    # own texture is a 10.1 m cross-section, a scale of 1/10.1 tiled it over 20.2 m. Two over
    # the distance is what puts a repeat where the terrain's page file says one is.
    asset.set("uv_scale", 2.0 / maxf(layer["tile_m"] as float, MIN_TILE_M))
    return asset


## A ground texture from a mod's files, rolled to cancel Terrain3D's own half-tile offset.
##
## Rolling needs pixels, so a block-compressed texture is decompressed first and kept that way.
## Four 512-square layers is a megabyte each and it is the only way the markings land where the
## terrain's author painted them.
static func tiling_texture_of(
    path: String, reader: RefCounted, size: Vector2i = Vector2i.ZERO
) -> Texture2D:
    var image: Image = image_of(path, reader)
    if image == null:
        return null
    # Brought to the array's size before anything else. Resizing needs pixels, so a
    # block-compressed texture is decompressed first — which the roll below does anyway.
    if size != Vector2i.ZERO and image.get_size() != size:
        if image.is_compressed() and image.decompress() != OK:
            return ImageTexture.create_from_image(image)
        image.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
    if is_zero_approx(UV_PHASE):
        return ImageTexture.create_from_image(image)
    if image.is_compressed() and image.decompress() != OK:
        return ImageTexture.create_from_image(image)
    image = rolled(image, UV_PHASE)
    image.generate_mipmaps()
    return ImageTexture.create_from_image(image)


## An image shifted by a fraction of its own size, wrapping round. A tiling texture rolled this
## way tiles exactly as before, that fraction of a tile along.
##
## The source is duplicated, not rebuilt from its own bytes. `Image.create_from_data` was used
## here with `use_mipmaps` hardcoded false, and an image that carries mipmaps carries them in
## that byte array: for one of La Paz's 800x600 textures it meant "expected 1920000 bytes, got
## 2559756", the reconstruction failed, `blit_rect` was handed a zero-size source, and the roll
## produced an empty image.
##
## That is the whole of the recorded finding that "Terrain3D is drawing the ground from the
## colour map and the texture assets reach nothing". They reached nothing because they were
## blank. Every experiment that followed — darkening an albedo, whitening `albedo_color`, taking
## normal depth to zero — was changing a black texture into a slightly different black texture,
## and Terrain3D's own warning for it, the checkerboard it turns on when a texture array is
## empty, was being switched off two lines later by `TerrainWorld._show_surfaces`.
static func rolled(image: Image, fraction: float) -> Image:
    var width: int = image.get_width()
    var height: int = image.get_height()
    var shift_x: int = posmod(int(round(fraction * float(width))), width)
    var shift_y: int = posmod(int(round(fraction * float(height))), height)
    var source: Image = image.duplicate() as Image
    # Mipmaps are regenerated after the roll, and a source that has them makes every rect
    # arithmetic here wrong by the size of its own chain.
    if source.has_mipmaps():
        source.clear_mipmaps()
    var out: Image = Image.create_empty(width, height, false, source.get_format())
    out.blit_rect(source, Rect2i(0, 0, width, height), Vector2i(shift_x, shift_y))
    out.blit_rect(
        source, Rect2i(width - shift_x, 0, shift_x, height), Vector2i(0, shift_y)
    )
    out.blit_rect(
        source, Rect2i(0, height - shift_y, width, shift_y), Vector2i(shift_x, 0)
    )
    out.blit_rect(
        source, Rect2i(width - shift_x, height - shift_y, shift_x, shift_y), Vector2i(0, 0)
    )
    return out


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
    var image: Image = DdsImage.read(path, reader)
    if image != null and not image.is_compressed() and not image.has_mipmaps():
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
