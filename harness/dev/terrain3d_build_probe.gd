extends SceneTree
## Builds a Terrain3D from a generated heightmap and reads the heights back out.
##
##   godot --path game --headless --script res://harness/dev/terrain3d_build_probe.gd
##
## The question this answers is what a Terrain3D needs before it has any data at all: a bare
## node has a null `data` and a null collision object, so the setup order is the thing to
## establish before anything is built on top of it.

const REGION_SIZE: int = 256
const SPACING: float = 1.0
const AMPLITUDE: float = 20.0


var _terrain: Node3D
var _frame: int = 0


func _initialize() -> void:
    _terrain = ClassDB.instantiate("Terrain3D") as Node3D
    root.add_child(_terrain)
    # Set after entering the tree, not before: Terrain3D builds its subsystems on
    # NOTIFICATION_ENTER_TREE and only finishes once the node is inside a World3D, and a
    # property set before that is applied to an object that does not exist yet.
    _terrain.set("region_size", REGION_SIZE)
    _terrain.set("vertex_spacing", SPACING)
    var directory: String = OS.get_user_data_dir().path_join("terrain_probe")
    DirAccess.make_dir_recursive_absolute(directory)
    _terrain.set("data_directory", directory)
    print("in tree %s, data %s, collision %s" % [
        _terrain.is_inside_tree(), _terrain.get("data"), _terrain.get("collision")])


## Deferred by one frame, so the node has entered its World3D.
func _process(_delta: float) -> bool:
    _frame += 1
    if _frame < 2:
        return false
    _build(_terrain)
    return true


func _build(terrain: Node3D) -> void:
    terrain.set("collision_mode", 0)
    print("frame %d: data %s, collision %s, collision_mode %s" % [
        _frame, terrain.get("data"), terrain.get("collision"), terrain.get("collision_mode")])
    var data: Object = terrain.get("data")
    if data == null:
        print("no data object; nothing further can be built")
        quit(1)
        return

    var height: Image = Image.create_empty(REGION_SIZE, REGION_SIZE, false, Image.FORMAT_RF)
    for x: int in REGION_SIZE:
        for y: int in REGION_SIZE:
            # A valley running along x: low in the middle, rising to both sides.
            var across: float = (float(y) / float(REGION_SIZE) - 0.5) * 2.0
            var along: float = float(x) / float(REGION_SIZE)
            var h: float = AMPLITUDE * (across * across) + 2.0 * sin(along * TAU)
            height.set_pixel(x, y, Color(h, 0.0, 0.0))
    var images: Array = [height, null, null]
    data.call("import_images", images, Vector3.ZERO, 0.0, 1.0)
    print("regions after import: %s" % data.call("get_region_count"))

    for probe: Vector3 in [
        Vector3(10.0, 0.0, 128.0), Vector3(128.0, 0.0, 128.0),
        Vector3(128.0, 0.0, 10.0), Vector3(200.0, 0.0, 200.0),
    ]:
        print("  get_height%s = %s  normal %s" % [
            probe, data.call("get_height", probe), data.call("get_normal", probe)])
    var maps: Array = data.call("get_height_maps")
    print("height maps: %d" % maps.size())
    if maps.size() > 0:
        var map: Image = maps[0] as Image
        print("  map 0: %dx%d format %d" % [map.get_width(), map.get_height(), map.get_format()])
    print("region locations: %s" % data.call("get_region_locations"))
    quit(0)
