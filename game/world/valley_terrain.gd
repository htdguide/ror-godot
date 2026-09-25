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

    var size: int = TerrainCfg.MAP_SIZE
    var height: Image = Image.create_empty(size, size, false, Image.FORMAT_RF)
    for x: int in size:
        for z: int in size:
            height.set_pixel(x, z, Color(TerrainCfg.height_at(x, z), 0.0, 0.0))
    # import_images takes [height, control, colour]; the last two are left to their defaults.
    data.call("import_images", [height, null, null], TerrainCfg.ORIGIN, 0.0, 1.0)
    if int(data.call("get_region_count")) == 0:
        return "importing the heightmap produced no regions"
    return ""
