class_name SurfaceTextures
extends RefCounted
## Generates a texture set for the driving surfaces and hands it to Terrain3D.
##
## Every texture is made here rather than loaded, which keeps the terrain a reproducible
## artifact of code and avoids adopting third-party assets for what is still a test track.
## Each surface gets one greyscale noise image, tinted by Terrain3D's per-texture albedo
## colour, and a normal map derived from the same noise — so the grain a driver sees and the
## relief the sun catches come from one source and cannot disagree.
##
## Greyscale plus a tint, rather than nine coloured images, because tinting in GDScript means
## a million per-pixel calls per surface. `FastNoiseLite.get_image` and
## `Image.bump_map_to_normal_map` are both native, so this generates in a fraction of a second.


## Builds the asset set, in GroundModels order so a texture's id is its surface's index.
static func build() -> Object:
    if not ClassDB.class_exists("Terrain3DAssets"):
        return null
    var assets: Object = ClassDB.instantiate("Terrain3DAssets")
    var textures: Array = []
    for index: int in GroundModels.ORDER.size():
        var asset: Object = _asset(index, GroundModels.ORDER[index])
        if asset == null:
            return null
        textures.append(asset)
    assets.set("texture_list", textures)
    return assets


static func _asset(index: int, surface: String) -> Object:
    var detail: Array = SurfaceCfg.DETAIL.get(surface, [0.08, 0.4, 4.0, 0.8]) as Array
    var noise: FastNoiseLite = FastNoiseLite.new()
    noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    noise.frequency = float(detail[0])
    # Seeded from the surface's own index, so every surface looks different and every run
    # looks the same.
    noise.seed = index * 7919
    noise.fractal_octaves = 4

    var height: Image = noise.get_image(
        SurfaceCfg.TEXTURE_SIZE, SurfaceCfg.TEXTURE_SIZE, false, false, false
    )
    _apply_contrast(height, float(detail[1]))

    var albedo: Image = height.duplicate() as Image
    albedo.convert(Image.FORMAT_RGBA8)
    # Terrain3D reads height from the albedo texture's alpha for depth blending, and the noise
    # is exactly that height.
    var normal: Image = height.duplicate() as Image
    normal.bump_map_to_normal_map(SurfaceCfg.NORMAL_DEPTH)
    normal.convert(Image.FORMAT_RGBA8)

    var asset: Object = ClassDB.instantiate("Terrain3DTextureAsset")
    asset.set("id", index)
    asset.set("name", surface)
    asset.set("albedo_texture", ImageTexture.create_from_image(albedo))
    asset.set("normal_texture", ImageTexture.create_from_image(normal))
    # The surface's own colour, multiplied over the greyscale noise.
    asset.set("albedo_color", TerrainCfg.SURFACE_COLOURS.get(surface, Color.GRAY))
    asset.set("uv_scale", float(detail[2]))
    asset.set("roughness", float(detail[3]))
    asset.set("detiling_rotation", SurfaceCfg.DETILE_ROTATION)
    asset.set("detiling_shift", SurfaceCfg.DETILE_SHIFT)
    return asset


## Scales the noise to a variation around SurfaceCfg.DETAIL_BASE, and flattens the quietest
## part of it so a surface has plain patches rather than being busy everywhere.
static func _apply_contrast(image: Image, contrast: float) -> void:
    for y: int in image.get_height():
        for x: int in image.get_width():
            var value: float = image.get_pixel(x, y).r
            var centred: float = (value - 0.5) * 2.0
            if absf(centred) < SurfaceCfg.DETAIL_FLOOR:
                centred = 0.0
            var scaled: float = clampf(
                SurfaceCfg.DETAIL_BASE + centred * contrast * SurfaceCfg.DETAIL_BASE, 0.0, 1.0
            )
            image.set_pixel(x, y, Color(scaled, scaled, scaled, scaled))
