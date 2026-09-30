class_name RorTerrain
extends RefCounted
## A Rigs of Rods terrain, loaded from the files its author shipped.
##
## This is the only kind of world the project has. It used to generate two of its own — a valley
## and a flat test park, both pure functions of a grid cell — and they are gone, because a world
## this project wrote cannot check the readers that load somebody else's. A real terrain is 8 MB
## of 16-bit samples, a traction map painted in an image editor and friction numbers in the
## terrain's own config, built and driven by people against those numbers, so it is an oracle the
## project cannot write for itself.
##
## This is the shape interface the terrain builder, the collision bridge and the gates all take:
## a height and a surface per lattice cell, a tint per world position, and where a cell is in the
## world. It is an instance rather than a script, because it holds the files.
##
## Two numbers decide whether it is the terrain its author drew:
##
##   - a height is `sample / 65535 * WorldSizeY`, so La Paz's 35 m of range is the whole of it;
##   - the lattice is `PageSize - 1` cells of `WorldSizeX / (PageSize - 1)` metres, which for a
##     2049-sample page across 4000 m is 2048 cells of 1.953125 m.
##
## The last sample row and column are dropped, because Terrain3D's regions tile on a power of two
## and 2049 does not: the terrain is 3998.05 m of a 4000 m map, its far edge two metres short.
## Nothing is resampled to achieve that — a resampled heightmap is no longer the author's.

var directory: String = ""
## The `.terrn2` this terrain was read from, without its extension. One directory can hold
## several — Rigs of Rods' own shipped map ships three, gravel, asphalt and flooded, over one
## set of files — and they are different terrains that happen to share a folder.
var terrn2_name: String = ""
var name: String = ""
var config: Dictionary = {}
var geometry: Dictionary = {}
var page: Dictionary = {}
var traction: Dictionary = {}
var models: GroundModelSet = null

var _heights: PackedByteArray = PackedByteArray()
var _samples: int = 0
var _height_scale: float = 0.0
## What the ground grips like where the terrain's traction map cannot say: upstream's
## `defaultgroundgm`, set in `Collisions::Collisions`.
const NO_LANDUSE_SURFACE: String = "gravel"

var _traction_image: Image = null
var _blend_image: Image = null
## Which channel of the blend map selects each splat layer, and at what strength.
var _layer_channels: PackedStringArray = PackedStringArray()
var _layer_alphas: PackedFloat32Array = PackedFloat32Array()
## Surface name -> index in `models`, so a per-cell lookup is not a string search.
var _surface_indices: Dictionary = {}
var _default_surface: int = 0
## The terrain's own textures, built on demand.
var _assets: Object = null


## Loads the terrain in a directory. Returns null and leaves `error` set on the result of
## `last_error()` when it cannot be read.
static func load_from(directory_path: String, wanted_terrn2: String = "") -> Dictionary:
    var out: Dictionary = {"error": "", "terrain": null}
    var terrn2_path: String = ""
    if wanted_terrn2.is_empty():
        terrn2_path = _find(directory_path, "terrn2")
    else:
        terrn2_path = directory_path.path_join("%s.terrn2" % wanted_terrn2)
        if not FileAccess.file_exists(terrn2_path):
            out["error"] = "no %s.terrn2 in %s" % [wanted_terrn2, directory_path]
            return out
    if terrn2_path.is_empty():
        out["error"] = "no .terrn2 in %s" % directory_path
        return out
    var terrain: RorTerrain = RorTerrain.new()
    terrain.directory = directory_path
    terrain.terrn2_name = terrn2_path.get_file().get_basename()
    out["error"] = terrain._read(terrn2_path)
    if (out["error"] as String) != "":
        return out
    out["terrain"] = terrain
    return out


## The lattice the terrain is sampled on: how many cells across, how many metres apart, and where
## its first cell is in the world. The shape interface's own question, asked of a real terrain.
func lattice() -> Dictionary:
    return {
        "size": _samples - 1,
        "spacing": (geometry["world_x"] as float) / float(_samples - 1),
        "origin": Vector3.ZERO,
    }


## Where a lattice cell is in the world. RoR terrains start at the origin and run positive.
func world_of(x_index: int, z_index: int) -> Vector2:
    var spacing: float = lattice()["spacing"] as float
    return Vector2(float(x_index) * spacing, float(z_index) * spacing)


## The terrain's height at a lattice cell, in metres.
func height_at(x_index: int, z_index: int) -> float:
    return _sample(x_index, z_index)


## The terrain's height at a world position, interpolated between samples the way a wheel meets it.
func height_at_world(x: float, z: float) -> float:
    var spacing: float = lattice()["spacing"] as float
    var fx: float = x / spacing
    var fz: float = z / spacing
    var x0: int = int(floor(fx))
    var z0: int = int(floor(fz))
    var tx: float = fx - float(x0)
    var tz: float = fz - float(z0)
    var north: float = lerpf(_sample(x0, z0), _sample(x0 + 1, z0), tx)
    var south: float = lerpf(_sample(x0, z0 + 1), _sample(x0 + 1, z0 + 1), tx)
    return lerpf(north, south, tz)


## Which surface a lattice cell is, as an index into `models`.
func surface_at(x_index: int, z_index: int) -> int:
    var world: Vector2 = world_of(x_index, z_index)
    return surface_at_world(world.x, world.y)


## Which surface a world position is. The traction map is the terrain's own painted image, and a
## colour it does not name is the landuse config's own default.
func surface_at_world(x: float, z: float) -> int:
    if _traction_image == null:
        return _default_surface
    var pixel: Color = _traction_image.get_pixelv(_image_cell(_traction_image, x, z))
    var surface: String = Landuse.surface_of(traction, pixel)
    return _surface_indices.get(surface, _default_surface) as int


## What colour the ground is at a world position.
##
## White, deliberately. The terrain's look is its own tiled textures, laid on by
## `RorTerrainSkin` through Terrain3D's control map, and Terrain3D multiplies the colour map
## over them: any tint here would be this project's palette painted over the author's.
##
## What the splat map says is not discarded — it decides which textures are drawn, through
## `layer_coverage_at` — it just does not become a colour.
func tint_at(_x: float, _z: float) -> Color:
    return Color.WHITE


## The terrain's splat layers, as the page file lists them.
func layers() -> Array[Dictionary]:
    return page["layers"] as Array[Dictionary]


## How much of the final picture each layer covers at a world position.
##
## Ogre draws layer 0 over the whole page and lays each later layer over it at that layer's own
## alpha, taken from one channel of the splat map. So a layer's share is its own weight times
## what the layers above it left uncovered, which is the composite unrolled.
func layer_coverage_at(x: float, z: float) -> PackedFloat32Array:
    var out: PackedFloat32Array = PackedFloat32Array()
    out.resize(_layer_channels.size())
    if out.is_empty():
        return out
    var blend: Color = Color(0.0, 0.0, 0.0, 0.0)
    if _blend_image != null:
        blend = _blend_image.get_pixelv(_image_cell(_blend_image, x, z))
    var remaining: float = 1.0
    for index: int in range(out.size() - 1, 0, -1):
        var weight: float = clampf(
            _channel(blend, _layer_channels[index]) * _layer_alphas[index], 0.0, 1.0
        )
        out[index] = weight * remaining
        remaining -= out[index]
    out[0] = maxf(remaining, 0.0)
    return out


## Which textures Terrain3D draws at a lattice cell, and how they mix.
func control_at(x_index: int, z_index: int) -> Dictionary:
    var world: Vector2 = world_of(x_index, z_index)
    return RorTerrainSkin.control_of(layer_coverage_at(world.x, world.y))


## The terrain's own textures, as a Terrain3D asset set. Built once and kept: it holds every
## splat texture the terrain ships.
func terrain_assets() -> Object:
    if _assets == null:
        _assets = RorTerrainSkin.assets(self)
    return _assets


## The surfaces this terrain can be driven on: upstream's set with the terrain's own config laid
## over it. Part of the shape interface — the surface map's indices mean nothing without it.
func ground_models() -> GroundModelSet:
    return models


## What colour each surface is drawn with, over its generated texture: none of this project's
## own, because a loaded terrain carries its own imagery.
##
## The colour map is built from the terrain's own splat layers, and Terrain3D multiplies a
## texture's albedo colour over it. Tinting an imported terrain's asphalt with this project's
## idea of asphalt multiplies two colours that were never meant to meet: measured, La Paz's
## roads came out pure black beside ground that was correct.
func surface_colours() -> Dictionary:
    return {}


## Where a vehicle starts, as the terrain's own config states it.
func start_position() -> Vector3:
    return config["start_position"] as Vector3


## What gravity the terrain asks for, in m/s^2.
func gravity() -> float:
    return config["gravity"] as float


## A name for this terrain's cache directory, and a salt that changes when its files do.
## Named for the `.terrn2` rather than the directory, because three terrains in one directory
## would otherwise share one cache and the second to load would be served the first.
func cache_name() -> String:
    return "ror_%s" % terrn2_name.to_lower()


func cache_salt() -> String:
    return "%s:%d:%d" % [name, _heights.size(), _samples]


## Whether this terrain states that it has no relief at all.
func is_flat() -> bool:
    return geometry["flat"] as bool


## --- Loading --------------------------------------------------------------------------------


func _read(terrn2_path: String) -> String:
    config = Terrn2.read(terrn2_path)
    if (config["error"] as String) != "":
        return config["error"] as String
    name = config["name"] as String
    geometry = Otc.read(directory.path_join(config["geometry_config"] as String))
    if (geometry["error"] as String) != "":
        return geometry["error"] as String
    page = Otc.read_page(directory.path_join(geometry["page_file"] as String))
    if (page["error"] as String) != "":
        return page["error"] as String
    _samples = geometry["samples"] as int
    if geometry["flat"] as bool:
        # A flat terrain has no heightmap and upstream never opens the one its page file names
        # — Rigs of Rods' own shipped map names a `.png` that is not in the package. Reading it
        # would fail on a terrain the game itself loads, so the samples stay unallocated and
        # `_sample` answers zero.
        _heights = PackedByteArray()
        _height_scale = 0.0
    else:
        var heightmap: String = directory.path_join(page["heightmap"] as String)
        _heights = FileAccess.get_file_as_bytes(heightmap)
        var wanted: int = _samples * _samples * (geometry["bytes_per_sample"] as int)
        if _heights.size() < wanted:
            return "%s holds %d bytes where %d samples of %d bytes need %d" % [
                page["heightmap"], _heights.size(), _samples * _samples,
                geometry["bytes_per_sample"], wanted
            ]
        _height_scale = (geometry["world_y"] as float) / 65535.0
    var surfaces: String = _read_surfaces()
    if surfaces != "":
        return surfaces
    _read_layers()
    return ""


## The traction map and the friction numbers behind it.
func _read_surfaces() -> String:
    models = GroundModelSet.upstream()
    for index: int in models.size():
        _surface_indices[models.name_of(index)] = index
    # A terrain with no traction map is gravel, not the first model in the set. Upstream keeps
    # two defaults — `Collisions.cpp:134-135` — and the one the ground uses when landuse is
    # absent or fails to answer is `defaultgroundgm`, gravel. `defaultgm`, concrete, is for
    # collision meshes. Reading the wrong one makes upstream's own shipped gravel map grip like
    # a road, which is what it did.
    _default_surface = maxi(models.index_of(NO_LANDUSE_SURFACE), 0)
    var landuse_file: String = config["traction_map"] as String
    if landuse_file.is_empty():
        return ""
    traction = Landuse.read(directory.path_join(landuse_file))
    if (traction["error"] as String) != "":
        return traction["error"] as String
    for cfg: String in traction["ground_model_configs"] as PackedStringArray:
        models.add_config(directory.path_join(cfg))
    _traction_image = Image.load_from_file(directory.path_join(traction["texture"] as String))
    if _traction_image == null:
        return "the traction map image %s could not be read" % traction["texture"]
    for index: int in models.size():
        _surface_indices[models.name_of(index)] = index
    # The landuse config's own `defaultuse` for a colour it does not name, and gravel again when
    # it names none: upstream falls back to `defaultgroundgm` whenever landuse cannot answer.
    var fallback: String = traction["default_use"] as String
    _default_surface = maxi(
        models.index_of(fallback), maxi(models.index_of(NO_LANDUSE_SURFACE), 0)
    )
    return ""


## The splat layers: which channel paints each one, and the blend map they are painted with.
func _read_layers() -> void:
    for layer: Dictionary in page["layers"] as Array[Dictionary]:
        _layer_channels.append(layer["channel"] as String)
        _layer_alphas.append(layer["alpha"] as float)
        var blend_file: String = layer["blend_map"] as String
        if _blend_image == null and not blend_file.is_empty():
            _blend_image = Image.load_from_file(directory.path_join(blend_file))


## --- Sampling -------------------------------------------------------------------------------


## One raw sample, clamped to the map. Row-major from the origin, which is what the file is:
## measured against the terrain's own StartPosition, its height there is 7.377 m where the config
## says a vehicle starts at 7.375.
func _sample(x_index: int, z_index: int) -> float:
    if _heights.is_empty():
        return 0.0
    var x: int = clampi(x_index, 0, _samples - 1)
    var z: int = clampi(z_index, 0, _samples - 1)
    if geometry["flip_x"] as bool:
        x = _samples - 1 - x
    return float(_heights.decode_u16((z * _samples + x) * 2)) * _height_scale


## Which pixel of one of the terrain's images covers a world position.
func _image_cell(image: Image, x: float, z: float) -> Vector2i:
    var across: float = x / (geometry["world_x"] as float)
    var along: float = z / (geometry["world_z"] as float)
    return Vector2i(
        clampi(int(across * float(image.get_width())), 0, image.get_width() - 1),
        clampi(int(along * float(image.get_height())), 0, image.get_height() - 1)
    )


func _channel(colour: Color, channel: String) -> float:
    match channel:
        "R":
            return colour.r
        "G":
            return colour.g
        "B":
            return colour.b
        "A":
            return colour.a
    return 0.0


static func _find(directory_path: String, extension: String) -> String:
    var found: PackedStringArray = PackedStringArray()
    for file: String in DirAccess.get_files_at(directory_path):
        if file.get_extension().to_lower() == extension:
            found.append(file)
    if found.is_empty():
        return ""
    found.sort()
    return directory_path.path_join(found[0])
