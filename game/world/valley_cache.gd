class_name ValleyCache
extends RefCounted
## Keeps the generated valley between runs, and refuses to trust it when it might be stale.
##
## The valley is 4.2 M cells of GDScript: 10 s of heights, 7 s of surfaces and 2 s of painting,
## measured by `tools/terrain_cost_probe.gd`. Paid on every gate that stands something on the
## terrain, that is most of the suite's runtime — the suite was 37 s in total before the valley
## grew to the 2 km PLAN §0.5 asks for — and it is paid again every time a window is opened.
##
## The shape is deterministic, so it is also cacheable: Terrain3D saves and loads its own
## regions, and the surface map is written beside them. The cache lives under `user://`, keyed
## by a hash of the files that decide the shape, so editing the layout changes the key and the
## old valley is never loaded against new numbers.
##
## **A cache is a golden artifact, which this project does not otherwise allow.** So it is not
## trusted on its key alone: `verify` samples the loaded terrain against `ValleyShape` itself
## and a single disagreement throws the cache away and regenerates. That keeps the live
## function the authority and makes the cache an optimisation rather than a second source of
## truth. Set `VALLEY_NO_CACHE=1` to skip it entirely.

const SURFACE_FILE: String = "surfaces.bin"
## The files whose contents decide what the valley is. A change to any of them is a new valley.
const SOURCES: Array[String] = [
    "res://world/valley_one_layout.gd",
    "res://world/valley_shape.gd",
    "res://config/terrain_cfg.gd",
]
## How many cells of a loaded cache are checked against the live shape function.
const VERIFY_SAMPLES: int = 4096
## The regions hold 32-bit heights, so a cached height is the generated one bit for bit and the
## tolerance is for nothing but the sampler's own arithmetic.
const VERIFY_TOLERANCE_M: float = 0.001


static func disabled() -> bool:
    return OS.get_environment("VALLEY_NO_CACHE") == "1"


## Where this valley's cache lives. The key is a hash of the shape's sources, so a layout edit
## lands in a different directory rather than being loaded over.
static func directory() -> String:
    return OS.get_user_data_dir().path_join("cache").path_join("valley_%s" % key())


## A short hash of every file that decides the shape. Returns "unhashable" when a source cannot
## be read, which is a key like any other — the point of it is only to change when they do.
static func key() -> String:
    var context: HashingContext = HashingContext.new()
    context.start(HashingContext.HASH_SHA256)
    for path: String in SOURCES:
        var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
        if bytes.is_empty():
            return "unhashable"
        context.update(bytes)
    return context.finish().hex_encode().substr(0, 16)


## Whether a cache directory holds a valley: Terrain3D's regions and the surface map beside
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


## Checks a loaded terrain against the live shape function, at cells spread over the whole map.
## Returns "" when they agree and the disagreement when they do not.
static func verify(data: Object) -> String:
    var size: int = TerrainCfg.MAP_SIZE
    var spacing: float = TerrainCfg.VERTEX_SPACING
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = HarnessCfg.SEED
    for _sample: int in VERIFY_SAMPLES:
        var x_index: int = rng.randi_range(0, size - 1)
        var z_index: int = rng.randi_range(0, size - 1)
        var world: Vector2 = ValleyShape.world_of(x_index, z_index)
        var cached: float = data.call(
            "get_height", Vector3(world.x, 0.0, world.y)
        ) as float
        var live: float = ValleyShape.height_at(x_index, z_index)
        if not is_finite(cached) or absf(cached - live) > VERIFY_TOLERANCE_M:
            return (
                "the cached terrain is %.4f m at %v where the shape says %.4f m"
                % [cached, world, live]
            )
    return ""


## Reads the surface map written beside the regions. Empty when it is missing or the wrong size
## for this map, which is treated as no cache at all.
static func read_surfaces(path: String) -> PackedByteArray:
    var expected: int = TerrainCfg.MAP_SIZE * TerrainCfg.MAP_SIZE
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
