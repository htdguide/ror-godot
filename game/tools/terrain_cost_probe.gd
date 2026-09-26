extends SceneTree
## Times every step of building the valley heightmap, at several map sizes.
##
##   godot --path game --headless --script res://tools/terrain_cost_probe.gd
##
## The question this answers is what the valley is allowed to cost. Valley One is 2 x 2 km
## (PLAN §0.5) and the terrain is generated every run, by GDScript, per texel: the height and
## colour loops and the control-map write are all O(texels), so growing the map from the
## current 512 x 512 test track to the planned size multiplies each of them by 16. If the
## control write dominates, the surface painting has to change shape before the map grows —
## measuring that first is cheaper than growing the map and discovering it.

const REGION_SIZE: int = 256
## Each entry is [map size in vertices, vertex spacing in metres], so every row covers a
## different area at a different resolution and the cost can be attributed to texel count
## rather than to extent.
const CASES: Array = [
    [512, 1.0],
    [1024, 2.0],
    [2048, 1.0],
]


var _frame: int = 0


func _initialize() -> void:
    if not ClassDB.class_exists("Terrain3D"):
        print("Terrain3D is not installed: run tools/build_terrain3d.sh")
        quit(1)


func _process(_delta: float) -> bool:
    _frame += 1
    # Terrain3D finishes building only once it is inside a World3D, which is a frame away.
    if _frame < 2:
        return false
    _measure_shape()
    for case: Array in CASES:
        _measure(int(case[0]), float(case[1]))
    quit(0)
    return true


func _measure(size: int, spacing: float) -> void:
    var terrain: Node3D = ClassDB.instantiate("Terrain3D") as Node3D
    root.add_child(terrain)
    terrain.set("region_size", REGION_SIZE)
    terrain.set("vertex_spacing", spacing)
    var directory: String = OS.get_user_data_dir().path_join("cost_probe_%d" % size)
    DirAccess.make_dir_recursive_absolute(directory)
    terrain.set("data_directory", directory)
    var data: Object = terrain.get("data")
    if data == null:
        print("size %d: no data object" % size)
        return
    var origin: Vector3 = Vector3(-0.5 * float(size) * spacing, 0.0, -0.5 * float(size) * spacing)

    var start: int = Time.get_ticks_usec()
    var height: Image = Image.create_empty(size, size, false, Image.FORMAT_RF)
    var colour: Image = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
    for x: int in size:
        for z: int in size:
            var h: float = 18.0 * pow(absf(float(z) / float(size) - 0.5) * 2.0, 2.0)
            height.set_pixel(x, z, Color(h, 0.0, 0.0))
            colour.set_pixel(x, z, Color(0.4, 0.4, 0.4, 0.6))
    var fill_ms: float = float(Time.get_ticks_usec() - start) / 1000.0

    start = Time.get_ticks_usec()
    data.call("import_images", [height, null, colour], origin, 0.0, 1.0)
    var import_ms: float = float(Time.get_ticks_usec() - start) / 1000.0

    start = Time.get_ticks_usec()
    for x: int in size:
        var world_x: float = origin.x + float(x) * spacing
        for z: int in size:
            data.call(
                "set_control_base_id", Vector3(world_x, 0.0, origin.z + float(z) * spacing), 3
            )
    var control_ms: float = float(Time.get_ticks_usec() - start) / 1000.0

    start = Time.get_ticks_usec()
    data.call("update_maps")
    var update_ms: float = float(Time.get_ticks_usec() - start) / 1000.0

    # What the collision bridge costs: one get_height call per cell, across the scripting
    # boundary, which is how TerrainHeightfield.read copies the terrain for the solver.
    start = Time.get_ticks_usec()
    var heights: PackedFloat32Array = PackedFloat32Array()
    heights.resize(size * size)
    for z: int in size:
        var row: int = z * size
        var world_z: float = origin.z + float(z) * spacing
        for x: int in size:
            heights[row + x] = data.call(
                "get_height", Vector3(origin.x + float(x) * spacing, 0.0, world_z)
            ) as float
    var read_ms: float = float(Time.get_ticks_usec() - start) / 1000.0

    print(
        (
            "%d x %d at %.1f m (%.1f km across, %.2f M texels):"
            + " fill %.0f ms, import %.0f ms, control %.0f ms, update %.0f ms,"
            + " bridge read %.0f ms, total %.1f s"
        )
        % [
            size, size, spacing, float(size) * spacing / 1000.0,
            float(size * size) / 1e6,
            fill_ms, import_ms, control_ms, update_ms, read_ms,
            (fill_ms + import_ms + control_ms + update_ms + read_ms) / 1000.0,
        ]
    )
    terrain.get_parent().remove_child(terrain)
    terrain.free()


## What the valley's own shape functions cost over the whole map, which is the part the
## generator spends its time in: the fill loop above only measures Image.set_pixel.
func _measure_shape() -> void:
    var size: int = TerrainCfg.MAP_SIZE
    var start: int = Time.get_ticks_usec()
    var sink: float = 0.0
    for x: int in size:
        for z: int in size:
            sink += ValleyShape.height_at(x, z)
    var height_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
    start = Time.get_ticks_usec()
    var surfaces: int = 0
    for x: int in size:
        for z: int in size:
            surfaces += ValleyShape.surface_at(x, z)
    var surface_ms: float = float(Time.get_ticks_usec() - start) / 1000.0
    print("ValleyShape over %d x %d: height %.0f ms, surface %.0f ms (sink %.1f, %d)" % [
        size, size, height_ms, surface_ms, sink, surfaces])
