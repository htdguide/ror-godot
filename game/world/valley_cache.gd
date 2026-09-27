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
## The files whose contents decide what a world is. A change to any of them is a new world.
const SOURCES: Array[String] = [
    "res://world/valley_one_layout.gd",
    "res://world/valley_shape.gd",
    "res://world/valley_water_cut.gd",
    "res://world/park_shape.gd",
    "res://config/park_cfg.gd",
    "res://config/terrain_cfg.gd",
]
## How many cells of a loaded cache are checked against the live shape function.
const VERIFY_SAMPLES: int = 4096
## The regions hold 32-bit heights, so a cached height is the generated one bit for bit and the
## tolerance is for nothing but the sampler's own arithmetic.
const VERIFY_TOLERANCE_M: float = 0.001


static func disabled() -> bool:
    return OS.get_environment("VALLEY_NO_CACHE") == "1"


## Where this world's cache lives. The key is a hash of the shape's sources, so a layout edit
## lands in a different directory rather than being loaded over.
static func directory(shape: Object = null) -> String:
    var live_shape: Object = shape if shape != null else ValleyShape
    var name: String = live_shape.call("cache_name") as String
    return OS.get_user_data_dir().path_join("cache").path_join("%s_%s" % [name, key(live_shape)])


## A short hash of everything that decides the shape. Returns "unhashable" when a source cannot
## be read, which is a key like any other — the point of it is only to change when they do.
##
## For a generated world the sources are the scripts. For a world loaded from someone else's
## files the scripts decide only how those files are read, so the shape adds a salt of its own:
## a different terrain in the same directory is a different world and must not load this cache.
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
static func verify(data: Object, shape: Object = null) -> String:
    var live_shape: Object = shape if shape != null else ValleyShape
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
                "the cached terrain is %.4f m at %v where the shape says %.4f m"
                % [cached, world, live]
            )
    return ""


## Reads the surface map written beside the regions. Empty when it is missing or the wrong size
## for this map, which is treated as no cache at all.
static func read_surfaces(path: String, shape: Object = null) -> PackedByteArray:
    var live_shape: Object = shape if shape != null else ValleyShape
    var size: int = live_shape.call("lattice")["size"] as int
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
