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


## Generates the heightmap and imports it. Call after the node has been in the tree a frame.
## Returns "" on success.
static func populate(terrain: Node3D) -> String:
    if terrain == null:
        return "Terrain3D is not installed: run tools/build_terrain3d.sh"
    if not terrain.is_inside_tree():
        return "the terrain is not in the tree yet"
    terrain.set("region_size", TerrainCfg.REGION_SIZE)
    terrain.set("vertex_spacing", TerrainCfg.VERTEX_SPACING)
    # A data directory is where Terrain3D would persist regions. This terrain is generated
    # every run and never saved, so it gets a scratch directory and nothing is written.
    var directory: String = OS.get_user_data_dir().path_join("valley_one")
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

    var size: int = TerrainCfg.MAP_SIZE
    var height: Image = Image.create_empty(size, size, false, Image.FORMAT_RF)
    var colour: Image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
    for x: int in size:
        for z: int in size:
            height.set_pixel(x, z, Color(TerrainCfg.height_at(x, z), 0.0, 0.0))
            var surface: String = GroundModels.name_of(TerrainCfg.surface_at(x, z))
            var tint: Color = TerrainCfg.SURFACE_COLOURS.get(surface, Color.GRAY) as Color
            # Terrain3D's colour map carries roughness in its alpha channel.
            colour.set_pixel(x, z, Color(tint.r, tint.g, tint.b, 0.6))
    # import_images takes [height, control, colour]; the control map is left to its default.
    data.call("import_images", [height, null, colour], TerrainCfg.ORIGIN, 0.0, 1.0)
    if int(data.call("get_region_count")) == 0:
        return "importing the heightmap produced no regions"
    _paint_surfaces(terrain, data)
    return ""


## Writes which texture each part of the terrain uses, lane by lane.
##
## The control map is what selects a texture per texel, and it is written through Terrain3D's
## own setter rather than by packing its bit layout here: the packing is an internal detail of
## a pinned dependency and hand-writing it would break silently on an upgrade.
static func _paint_surfaces(terrain: Node3D, data: Object) -> void:
    var size: int = TerrainCfg.MAP_SIZE
    var spacing: float = TerrainCfg.VERTEX_SPACING
    for x: int in size:
        var world_x: float = TerrainCfg.ORIGIN.x + float(x) * spacing
        for z: int in size:
            data.call(
                "set_control_base_id",
                Vector3(world_x, 0.0, TerrainCfg.ORIGIN.z + float(z) * spacing),
                TerrainCfg.surface_at(x, z)
            )
    data.call("update_maps")
    terrain.set("data_directory", terrain.get("data_directory"))
