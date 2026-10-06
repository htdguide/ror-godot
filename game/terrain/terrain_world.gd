class_name TerrainWorld
extends RefCounted
## Builds a drivable world: a Terrain3D holding a Rigs of Rods terrain, with its collision off.
##
## Which terrain is a parameter, and it is always a `RorTerrain` — a map somebody else authored
## and shipped. This project generated its own worlds for a while, a valley and a flat test park,
## and they are gone: a world this project wrote is a world whose every gate is this project
## agreeing with itself, and the readers in `compat/` are the thing that needs checking.
##
## What is asked of a terrain is four static questions of a grid cell — a height, a surface, a
## tint, and where the cell is in the world — so everything downstream takes any terrain without
## knowing which it has.
##
## **One instance per world, and the harness owns it.** This was a class of static functions over
## two `static var`s, which made the terrain that was built last a property of the process: a
## caller that asked for `lattice()` without having populated in its own run was served the
## previous run's map, silently and with the right-looking numbers. One gate per process hid it.
## D0 runs many gates in one process, so it is an instance and a container owns it — and the
## class of bug is now unreachable rather than avoided by convention.
##
## Two things here are not obvious and both cost a probe to establish.
##
## A Terrain3D builds its subsystems when it enters the tree and finishes only once it is
## inside a World3D, so its `data` and `collision` objects are null until a frame has passed.
## Properties set before that are applied to objects that do not exist yet and are silently
## lost — which is what setting `collision_mode` before adding the node does.
##
## Collision mode is `Disabled`. Godot physics never touches this terrain: Rigs of Rods' own
## collision is authoritative and the solver is handed the heights directly.


## Creates the terrain node. It has no data until it has been in the tree for a frame, so the
## caller must add it, advance a frame, and then call `populate`.
static func create() -> Node3D:
    if not ClassDB.class_exists("Terrain3D"):
        return null
    var terrain: Node3D = ClassDB.instantiate("Terrain3D") as Node3D
    terrain.name = "Terrain"
    return terrain


## Turns off the debug views, now that there are real textures to draw.
##
## With no texture assets Terrain3D has no albedo to shade with at all — measured, the terrain
## renders pure black with both of these off — and the checkered pattern is the placeholder it
## draws instead. That was what a driver saw where the surface lanes should have been, and
## `show_colormap` stood in for it until the textures existed.
##
## Now they do, so both go off: a flat tint tells a driver which surface they are on but gives
## the eye nothing to track, and a ground with no detail in it reads as stationary however
## fast the vehicle is going.
func _show_surfaces(terrain: Node3D) -> void:
    var material: Object = terrain.get("material")
    if material == null:
        return
    material.set("show_checkered", false)
    material.set("show_colormap", false)
    # What lies beyond the map's edge: the author's own ground, flat, to the horizon.
    #
    # **A terrain is smaller than its own horizon.** La Paz is 4 km across and the painted mountain
    # ring it ships stands at 10,070 m, so with nothing beyond the map's edge the camera looks
    # through the gap between them at the sky below the horizon — reported from a window as a grey
    # line along the horizon, and it is a hole rather than a line. Extending the edge flat fills it
    # with the ground the map is made of; the noise background was tried and rejected, because it
    # invents a landscape the author did not make and on La Paz it put a white dune across the
    # backdrop.
    material.set("world_background", WORLD_BACKGROUND_FLAT)


## Terrain3D reads a texel's roughness from the colour map's alpha channel, so this is the
## roughness the whole terrain is drawn with — not the per-surface values in `SurfaceCfg`, which
## reach the texture assets and, measured, do not reach the picture.
const COLOUR_MAP_ROUGHNESS: float = 0.6
## Terrain3DMaterial.WorldBackground values: nothing beyond the map, or the map's edge extended
## flat to the horizon.
const WORLD_BACKGROUND_NONE: int = 0
const WORLD_BACKGROUND_FLAT: int = 1


## The surface map of the terrain this instance built, one cell per byte.
##
## The solver needs the same surfaces the renderer is painted with, and generating them is a
## second pass over millions of cells. So the pass that built the terrain keeps its result and
## the collision bridge is handed it, instead of both computing it from the same function and
## hoping they agree.
var _surfaces: PackedByteArray = PackedByteArray()
## The terrain this instance built. The surface map and the cache key both depend on it, so it is
## remembered rather than passed to everything that needs it.
##
## Null until something is built. There is no default world: a terrain comes from its author's
## files or there is nothing to stand on, and a caller that forgets to pass one should be told
## so rather than served whichever map happened to be compiled in.
var _shape: Object = null


## The lattice the current shape is sampled on: how many cells across, how far apart, and where
## the first one is.
##
## Asked of the shape rather than read from `TerrainCfg`, because a world loaded from someone
## else's files brings its own: La Paz is 2048 cells of 1.953125 m starting at the origin, where
## a generated world is 2048 of 1.0 m centred on it.
func lattice() -> Dictionary:
    if _shape == null:
        return {"size": 0, "spacing": 0.0, "origin": Vector3.ZERO}
    return _shape.call("lattice") as Dictionary


## The surface map of the terrain built last. Built on demand if the terrain was not built in
## this run, so that a caller cannot be handed an empty one.
func surface_map() -> PackedByteArray:
    if _shape == null:
        return PackedByteArray()
    var size: int = lattice()["size"] as int
    if _surfaces.size() == size * size:
        return _surfaces
    var out: PackedByteArray = PackedByteArray()
    out.resize(size * size)
    for z: int in size:
        var row: int = z * size
        for x: int in size:
            out[row + x] = _shape.call("surface_at", x, z)
    _surfaces = out
    return _surfaces


## Hands the built valley to a solver: the heights it stands on and the surfaces it grips.
## Returns "" on success.
##
## The grid handed over is the terrain's own lattice — same origin, same spacing, same row order
## — because `terrain_collision_agreement` measures the two against each other and any
## resampling here would show up there as a disagreement.
func give_to_solver(solver: RefCounted, data: Object) -> String:
    if data == null:
        return "the terrain has no data object: it has not finished entering the tree"
    if _shape == null:
        return "no terrain has been built: populate() takes the terrain to build"
    var grid: Dictionary = lattice()
    var size: int = grid["size"] as int
    var field: Dictionary = TerrainHeightfield.read(
        data, grid["origin"] as Vector3, size, size, grid["spacing"] as float
    )
    return TerrainHeightfield.apply(
        solver, field, surface_map(), _shape.call("ground_models") as GroundModelSet
    )


## The shape the terrain is currently built from.
func shape() -> Object:
    return _shape


## Imports a terrain's heightmap, or loads the cached import when there is one. Call after the
## node has been in the tree a frame. `with_shape` is the `RorTerrain` to build; leaving it null
## keeps whichever was built last, so a second call is cheap. Returns "" on success.
func populate(terrain: Node3D, with_shape: Object = null) -> String:
    if with_shape != null and with_shape != _shape:
        _shape = with_shape
        _surfaces = PackedByteArray()
    if _shape == null:
        return "populate() was given no terrain, and there is no default world to fall back to"
    if terrain == null:
        return "Terrain3D is not installed: run tools/build_terrain3d.sh"
    if not terrain.is_inside_tree():
        return "the terrain is not in the tree yet"
    var grid: Dictionary = lattice()
    terrain.set("region_size", TerrainCfg.REGION_SIZE)
    terrain.set("vertex_spacing", grid["spacing"] as float)
    # Terrain3D persists its regions in its data directory and loads them when the directory is
    # set, so this both names where the cache goes and loads it if it is already there.
    var directory: String = TerrainCache.directory(_shape)
    DirAccess.make_dir_recursive_absolute(directory)
    terrain.set("data_directory", directory)
    var data: Object = terrain.get("data")
    if data == null:
        return "the terrain has no data object after a frame in the tree"
    terrain.set("collision_mode", TerrainCfg.COLLISION_DISABLED)
    # A terrain is drawn in the textures its author shipped. There is no generated fallback any
    # more: every world here comes from somebody's files and every one of them brings its own.
    var assets: Object = _shape.call("terrain_assets")
    if assets == null:
        return "%s ships no textures, and there is no generated set to draw it in" % _shape
    terrain.set("assets", assets)
    _show_surfaces(terrain)
    if _load_cached(data, directory):
        return ""

    var size: int = grid["size"] as int
    var height: Image = Image.create_empty(size, size, false, Image.FORMAT_RF)
    var colour: Image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
    # The surface is asked for once per cell and used twice: it tints the colour map here and
    # selects the texture in _paint_surfaces. Asking twice cost 8 s over a 4.2 M cell map.
    var surfaces: PackedByteArray = PackedByteArray()
    surfaces.resize(size * size)
    # The colour is asked of the terrain rather than looked up from the surface, because a
    # loaded terrain's look is its own splat layers and not a palette per surface name.
    # The surface map is stored row by row — z outer, x inner — because that is the order the
    # solver reads a heightfield in, and the two are indexed by the same arithmetic. Stored the
    # other way round the whole map is transposed, which reads as the right surfaces in the
    # wrong places: concrete where the terrain draws sand.
    for z: int in size:
        var row: int = z * size
        for x: int in size:
            height.set_pixel(x, z, Color(_shape.call("height_at", x, z), 0.0, 0.0))
            var surface: int = _shape.call("surface_at", x, z)
            surfaces[row + x] = surface
            var world: Vector2 = _shape.call("world_of", x, z)
            var tint: Color = _shape.call("tint_at", world.x, world.y)
            # Terrain3D's colour map carries roughness in its alpha channel.
            colour.set_pixel(x, z, Color(tint.r, tint.g, tint.b, COLOUR_MAP_ROUGHNESS))
    # import_images takes [height, control, colour]; the control map is left to its default.
    data.call("import_images", [height, null, colour], grid["origin"] as Vector3, 0.0, 1.0)
    if int(data.call("get_region_count")) == 0:
        return "importing the heightmap produced no regions"
    _paint_surfaces(terrain, data)
    _surfaces = surfaces
    data.call("save_directory", directory)
    TerrainCache.write_surfaces(directory, surfaces)
    return ""


## Takes the cached import if there is one and it still agrees with the terrain's own files.
##
## The agreement check is what keeps this an optimisation rather than a golden artifact: the key
## already covers an edit to the files that decide the shape, and the sampling covers everything
## the key cannot — a half-written cache, a Terrain3D upgrade that stores heights differently,
## or a shape that reads something the key does not hash.
func _load_cached(data: Object, directory: String) -> bool:
    if TerrainCache.disabled():
        return false
    if not TerrainCache.is_populated(directory):
        return false
    if int(data.call("get_region_count")) == 0:
        return false
    var surfaces: PackedByteArray = TerrainCache.read_surfaces(directory, _shape)
    if surfaces.is_empty():
        return false
    var disagreement: String = TerrainCache.verify(data, _shape)
    if disagreement != "":
        push_warning("the cached terrain was discarded: %s" % disagreement)
        TerrainCache.discard(directory)
        return false
    _surfaces = surfaces
    return true


## Writes which textures each part of the terrain uses.
##
## The control map holds two texture ids and a blend per texel, and which those are is the
## terrain's own answer: the two splat layers its author painted most of at that point.
##
## Written through Terrain3D's own setters rather than by packing its bit layout here: the
## packing is an internal detail of a pinned dependency and hand-writing it would break
## silently on an upgrade.
func _paint_surfaces(terrain: Node3D, data: Object) -> void:
    var grid: Dictionary = lattice()
    var size: int = grid["size"] as int
    var spacing: float = grid["spacing"] as float
    var origin: Vector3 = grid["origin"] as Vector3
    for z: int in size:
        var world_z: float = origin.z + float(z) * spacing
        var row: int = z * size
        for x: int in size:
            var at: Vector3 = Vector3(origin.x + float(x) * spacing, 0.0, world_z)
            var control: Dictionary = _shape.call("control_at", x, z)
            data.call("set_control_base_id", at, control["base"] as int)
            var blend: float = control["blend"] as float
            if blend > 0.0:
                data.call("set_control_overlay_id", at, control["overlay"] as int)
                data.call("set_control_blend", at, blend)
    data.call("update_maps")
    terrain.set("data_directory", terrain.get("data_directory"))
