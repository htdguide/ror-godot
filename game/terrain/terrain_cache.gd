class_name TerrainCache
extends RefCounted
## Keeps a terrain's Terrain3D import between runs, and refuses to trust it when it might be
## stale.
##
## Importing La Paz is 4.2 M cells of GDScript. Paid on every gate that stands something on a
## terrain, that is most of the suite's runtime, and it is paid again every time a window opens.
##
## Reading a terrain is deterministic, so the import is cacheable: Terrain3D saves and loads its
## own regions, and the surface map is written beside them. The cache lives under `user://`,
## keyed by a hash of the readers that decide what a terrain's files mean plus a salt from the
## terrain itself, so a reader change and a different terrain both land in a different directory
## rather than being loaded over.
##
## **A cache is a golden artifact, which this project does not otherwise allow.** So it is not
## trusted on its key alone: `verify` samples the loaded regions against the terrain's own
## heightmap and a single disagreement throws the cache away and re-imports. That keeps the
## author's files the authority and makes the cache an optimisation rather than a second source
## of truth. Set `TERRAIN_NO_CACHE=1` to skip it entirely.
##
## Every entry point takes the terrain it is caching. There is no default: a cache keyed on the
## wrong terrain is a cache that serves one map's heights for another.

const SURFACE_FILE: String = "surfaces.bin"
## The files whose contents decide what a terrain's own files mean. A change to any of them is a
## different reading of the same map, so it is a different cache.
const SOURCES: Array[String] = [
    "res://game/terrain/ror_terrain.gd",
    "res://game/terrain/ror_terrain_skin.gd",
    "res://game/resources/otc.gd",
    "res://game/resources/terrn2.gd",
    "res://game/resources/landuse.gd",
    "res://game/config/terrain_cfg.gd",
]
## How many cells of a loaded cache are checked against the terrain's own heightmap.
const VERIFY_SAMPLES: int = 4096
## The regions hold 32-bit heights, so a cached height is the imported one bit for bit and the
## tolerance is for nothing but the sampler's own arithmetic.
const VERIFY_TOLERANCE_M: float = 0.001


static func disabled() -> bool:
    return OS.get_environment("TERRAIN_NO_CACHE") == "1"


## Where a terrain's cache lives. The key is a hash of the readers plus the terrain's own salt,
## so a reader edit or a different map lands in a different directory rather than being loaded
## over.
static func directory(shape: Object) -> String:
    var name: String = shape.call("cache_name") as String
    return OS.get_user_data_dir().path_join("cache").path_join("%s_%s" % [name, key(shape)])


## A short hash of everything that decides how a terrain is read, salted with the terrain
## itself. Returns "unhashable" when a source cannot be read, which is a key like any other —
## the point of it is only to change when they do.
##
## The scripts decide only how an author's files are read, so the terrain adds a salt of its
## own: a different terrain in the same directory is a different map and must not load this
## cache. Rigs of Rods' own shipped package is three terrains over one set of files, so that is
## not a hypothetical.
static func key(shape: Object = null) -> String:
    var context: HashingContext = HashingContext.new()
    context.start(HashingContext.HASH_SHA256)
    for path: String in SOURCES:
        var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
        if bytes.is_empty():
            return "unhashable"
        context.update(bytes)
    if shape != null:
        var salt: String = shape.call("cache_salt") as String
        if not salt.is_empty():
            context.update(salt.to_utf8_buffer())
    return context.finish().hex_encode().substr(0, 16)


## Whether a cache directory holds a terrain: Terrain3D's regions and the surface map beside
## them. Both or neither — a surface map without regions describes a terrain that is not there.
static func is_populated(path: String) -> bool:
    if not FileAccess.file_exists(path.path_join(SURFACE_FILE)):
        return false
    var directory_access: DirAccess = DirAccess.open(path)
    if directory_access == null:
        return false
    for file: String in directory_access.get_files():
        if file.ends_with(".res"):
            return true
    return false


## Checks a loaded cache against the terrain's own heightmap, at cells spread over the whole
## map. Returns "" when they agree and the disagreement when they do not.
static func verify(data: Object, shape: Object) -> String:
    var live_shape: Object = shape
    var size: int = live_shape.call("lattice")["size"] as int
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = HarnessCfg.SEED
    for _sample: int in VERIFY_SAMPLES:
        var x_index: int = rng.randi_range(0, size - 1)
        var z_index: int = rng.randi_range(0, size - 1)
        var world: Vector2 = live_shape.call("world_of", x_index, z_index)
        var cached: float = data.call(
            "get_height", Vector3(world.x, 0.0, world.y)
        ) as float
        var live: float = live_shape.call("height_at", x_index, z_index)
        if not is_finite(cached) or absf(cached - live) > VERIFY_TOLERANCE_M:
            return (
                "the cached terrain is %.4f m at %v where its own heightmap says %.4f m"
                % [cached, world, live]
            )
    return ""


## Reads the surface map written beside the regions. Empty when it is missing or the wrong size
## for this map, which is treated as no cache at all.
static func read_surfaces(path: String, shape: Object) -> PackedByteArray:
    var size: int = shape.call("lattice")["size"] as int
    var expected: int = size * size
    var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path.path_join(SURFACE_FILE))
    return bytes if bytes.size() == expected else PackedByteArray()


static func write_surfaces(path: String, surfaces: PackedByteArray) -> void:
    var file: FileAccess = FileAccess.open(path.path_join(SURFACE_FILE), FileAccess.WRITE)
    if file == null:
        return
    file.store_buffer(surfaces)
    file.close()


## Throws a cache away. Called when verification fails, so that the next run regenerates rather
## than failing the same way for ever.
static func discard(path: String) -> void:
    var directory_access: DirAccess = DirAccess.open(path)
    if directory_access == null:
        return
    for file: String in directory_access.get_files():
        directory_access.remove(file)
