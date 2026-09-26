class_name ValleyTerrain
extends RefCounted
## Builds the drivable valley: a Terrain3D with a generated heightmap and its collision off.
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
static func _show_surfaces(terrain: Node3D) -> void:
    var material: Object = terrain.get("material")
    if material == null:
        return
    material.set("show_checkered", false)
    material.set("show_colormap", false)


## Terrain3D reads a texel's roughness from the colour map's alpha channel, so this is the
## roughness the whole terrain is drawn with — not the per-surface values in `SurfaceCfg`, which
## reach the texture assets and, measured, do not reach the picture.
const COLOUR_MAP_ROUGHNESS: float = 0.6


## The surface map of the valley that was built last, one cell per byte.
##
## The solver needs the same surfaces the renderer is painted with, and generating them is a
## second pass over 4.2 M cells. So the pass that built the terrain keeps its result and the
## collision bridge is handed it, instead of both computing it from the same function and
## hoping they agree.
static var _surfaces: PackedByteArray = PackedByteArray()


## The surface map of the terrain built last. Built on demand if the terrain was not built in
## this run, so that a caller cannot be handed an empty one.
static func surface_map() -> PackedByteArray:
    if _surfaces.size() == TerrainCfg.MAP_SIZE * TerrainCfg.MAP_SIZE:
        return _surfaces
    var size: int = TerrainCfg.MAP_SIZE
    var out: PackedByteArray = PackedByteArray()
    out.resize(size * size)
    for z: int in size:
        var row: int = z * size
        for x: int in size:
            out[row + x] = ValleyShape.surface_at(x, z)
    _surfaces = out
    return _surfaces


## Hands the built valley to a solver: the heights it stands on and the surfaces it grips.
## Returns "" on success.
##
## The grid handed over is the terrain's own lattice — same origin, same spacing, same row order
## — because `terrain_collision_agreement` measures the two against each other and any
## resampling here would show up there as a disagreement.
static func give_to_solver(solver: RefCounted, data: Object) -> String:
    if data == null:
        return "the terrain has no data object: it has not finished entering the tree"
    var size: int = TerrainCfg.MAP_SIZE
    var field: Dictionary = TerrainHeightfield.read(
        data, TerrainCfg.ORIGIN, size, size, TerrainCfg.VERTEX_SPACING
    )
    return TerrainHeightfield.apply(solver, field, surface_map())


## Generates the heightmap and imports it, or loads the cached valley when there is one. Call
## after the node has been in the tree a frame. Returns "" on success.
static func populate(terrain: Node3D) -> String:
    if terrain == null:
        return "Terrain3D is not installed: run tools/build_terrain3d.sh"
    if not terrain.is_inside_tree():
        return "the terrain is not in the tree yet"
    terrain.set("region_size", TerrainCfg.REGION_SIZE)
    terrain.set("vertex_spacing", TerrainCfg.VERTEX_SPACING)
    # Terrain3D persists its regions in its data directory and loads them when the directory is
    # set, so this both names where the cache goes and loads it if it is already there.
    var directory: String = ValleyCache.directory()
    DirAccess.make_dir_recursive_absolute(directory)
    terrain.set("data_directory", directory)
    var data: Object = terrain.get("data")
    if data == null:
        return "the terrain has no data object after a frame in the tree"
    terrain.set("collision_mode", TerrainCfg.COLLISION_DISABLED)
    var assets: Object = SurfaceTextures.build()
    if assets != null:
        terrain.set("assets", assets)
    _show_surfaces(terrain)
    if _load_cached(data, directory):
        return ""

    var size: int = TerrainCfg.MAP_SIZE
    var height: Image = Image.create_empty(size, size, false, Image.FORMAT_RF)
    var colour: Image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
    # The surface is asked for once per cell and used twice: it tints the colour map here and
    # selects the texture in _paint_surfaces. Asking twice cost 8 s over a 4.2 M cell map.
    var surfaces: PackedByteArray = PackedByteArray()
    surfaces.resize(size * size)
    var tints: Array[Color] = []
    for name: String in GroundModels.ORDER:
        var tint: Color = TerrainCfg.SURFACE_COLOURS.get(name, Color.GRAY) as Color
        # Terrain3D's colour map carries roughness in its alpha channel.
        tints.append(Color(tint.r, tint.g, tint.b, COLOUR_MAP_ROUGHNESS))
    # The surface map is stored row by row — z outer, x inner — because that is the order the
    # solver reads a heightfield in, and the two are indexed by the same arithmetic. Stored the
    # other way round the whole map is transposed, which reads as the right surfaces in the
    # wrong places: concrete where the terrain draws sand.
    for z: int in size:
        var row: int = z * size
        for x: int in size:
            height.set_pixel(x, z, Color(ValleyShape.height_at(x, z), 0.0, 0.0))
            var surface: int = ValleyShape.surface_at(x, z)
            surfaces[row + x] = surface
            colour.set_pixel(x, z, tints[surface])
    # import_images takes [height, control, colour]; the control map is left to its default.
    data.call("import_images", [height, null, colour], TerrainCfg.ORIGIN, 0.0, 1.0)
    if int(data.call("get_region_count")) == 0:
        return "importing the heightmap produced no regions"
    _paint_surfaces(terrain, data, surfaces)
    _surfaces = surfaces
    data.call("save_directory", directory)
    ValleyCache.write_surfaces(directory, surfaces)
    return ""


## Takes the cached valley if there is one and it still agrees with the shape function.
##
## The agreement check is what keeps this an optimisation rather than a golden artifact: the key
## already covers an edit to the files that decide the shape, and the sampling covers everything
## the key cannot — a half-written cache, a Terrain3D upgrade that stores heights differently,
## or a shape that reads something the key does not hash.
static func _load_cached(data: Object, directory: String) -> bool:
    if ValleyCache.disabled():
        return false
    if not ValleyCache.is_populated(directory):
        return false
    if int(data.call("get_region_count")) == 0:
        return false
    var surfaces: PackedByteArray = ValleyCache.read_surfaces(directory)
    if surfaces.is_empty():
        return false
    var disagreement: String = ValleyCache.verify(data)
    if disagreement != "":
        push_warning("the cached valley was discarded: %s" % disagreement)
        ValleyCache.discard(directory)
        return false
    _surfaces = surfaces
    return true


## Writes which texture each part of the terrain uses, lane by lane.
##
## The control map is what selects a texture per texel, and it is written through Terrain3D's
## own setter rather than by packing its bit layout here: the packing is an internal detail of
## a pinned dependency and hand-writing it would break silently on an upgrade.
static func _paint_surfaces(terrain: Node3D, data: Object, surfaces: PackedByteArray) -> void:
    var size: int = TerrainCfg.MAP_SIZE
    var spacing: float = TerrainCfg.VERTEX_SPACING
    for z: int in size:
        var world_z: float = TerrainCfg.ORIGIN.z + float(z) * spacing
        var row: int = z * size
        for x: int in size:
            data.call(
                "set_control_base_id",
                Vector3(TerrainCfg.ORIGIN.x + float(x) * spacing, 0.0, world_z),
                surfaces[row + x]
            )
    data.call("update_maps")
    terrain.set("data_directory", terrain.get("data_directory"))
