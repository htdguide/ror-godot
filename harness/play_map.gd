class_name PlayMap
extends RefCounted
## The map a session is on: building it stage by stage behind a loading screen, and changing it
## for another without leaving anything of the old one behind.
##
## Split out of `PlayRig` when the loading screen took that file over its source cap, and it is
## a seam: everything here is about what the world is made of, and nothing here reads a key.
##
## Two things a session reported decide the shape of this. **A map change left the sea of the
## old map** — the removal list named three of the four things a map builds — and so the list
## is one constant here, with `RorWater` in it, and the gate `a_map_change_leaves_nothing_of_the_old_map`
## holds it against the builders' own node names. **And the weather was not put back**: the new
## map's unlit backdrop came in undimmed under whatever hour the old one was at, which read as a
## sky fault. A change puts the session's starting weather back on, over everything, last.

## The node every builder parents its map under, and the terrain itself.
const MAP_NODES: PackedStringArray = [
    "RorObjects", "RorProceduralRoads", "RorTrees", "RorWater", "Terrain",
]

var name: String = ""
var terrain: Node3D = null
## The terrain's own files, kept after the scene is built: a screenshot's sidecar reports the
## ground height and surface under the camera, and only the loaded terrain knows them.
var loaded: RorTerrain = null
var vegetation: RorVegetation = null
## The vehicle the map is driven with, if any; the session sets it and swaps it.
var drive: PlayDrive = null
var pending: bool = false
var loading: bool = false

var _rig: Node
var _world: Node3D
var _menu: PlayMenu
var _solid: PlaySolid
var _weather: PlayWeather
var _initial_weather: String
var _screen: PlayLoading


func setup(
    rig: Node, world: Node3D, menu: PlayMenu, solid: PlaySolid, weather: PlayWeather,
    initial_weather: String, screen: PlayLoading
) -> void:
    _rig = rig
    _world = world
    _menu = menu
    _solid = solid
    _weather = weather
    _initial_weather = initial_weather
    _screen = screen


## Adds the terrain node, when this session asked for a world and Terrain3D is installed. It
## cannot be populated yet: a Terrain3D has no data until it has been inside a World3D for a
## frame, so `populate` follows a frame later.
func build() -> void:
    if not Harness.args.has_flag("terrain"):
        return
    if name == "":
        print("PLAY  no map named and none bundled: the flat plane. Maps go in %s" % BuildProfile.maps_hint())
        return
    terrain = TerrainWorld.create()
    if terrain == null:
        printerr("PLAY  --terrain asked for, but Terrain3D is not installed. Run tools/build_terrain3d.sh")
        return
    _world.add_child(terrain)
    pending = true


## Builds the map in stages, a frame apart, each reported to the loading screen.
func populate() -> void:
    pending = false
    loading = true
    var wanted: RorTerrain = _load_terrain()
    if wanted == null:
        loading = false
        return
    loaded = wanted
    _screen.open(wanted.name)
    await _rig.get_tree().process_frame
    _screen.stage("Importing the terrain", 0.05)
    await _rig.get_tree().process_frame
    var error: String = Harness.terrain.populate(terrain, wanted)
    if error != "":
        printerr("PLAY  the terrain could not be built: " + error)
        _finish()
        return
    # The blockout plane would otherwise sit inside the terrain and the rig would rest on
    # whichever happened to be higher.
    var ground: MeshInstance3D = _world.get_node_or_null(^"Ground") as MeshInstance3D
    if ground != null:
        ground.visible = false
    _screen.stage("Placing the objects", 0.35)
    await _rig.get_tree().process_frame
    _world.add_child(RorObjects.build(wanted))
    _screen.stage("Sweeping the roads", 0.55)
    await _rig.get_tree().process_frame
    _world.add_child(RorProceduralRoad.build(wanted))
    _screen.stage("Planting the forests", 0.65)
    await _rig.get_tree().process_frame
    _world.add_child(RorTrees.build(wanted))
    _screen.stage("Filling the sea", 0.72)
    await _rig.get_tree().process_frame
    _world.add_child(RorWater.build(wanted))
    _screen.stage("Growing the vegetation", 0.78)
    await _rig.get_tree().process_frame
    _grow_vegetation(wanted)
    _screen.stage("Making the scenery solid", 0.86)
    await _rig.get_tree().process_frame
    _solid.setup(wanted)
    if Harness.args.has_flag("collision"):
        print("PLAY  " + _solid.show_boxes(_world, true))
    if Harness.args.has_flag("facing"):
        var dressed: int = FacingPaint.dress(_world)
        print("PLAY  facing paint on %d meshes: any bright primary is the back of a face" % dressed)
    _hand_to_vehicle(wanted)
    _screen.stage("Setting the weather", 0.94)
    await _rig.get_tree().process_frame
    # Last, over everything the map built: the new backdrop takes the hour's dimming, the probe
    # recaptures the new sky, and the panel shows the weather that is on.
    _weather.apply(_world, _initial_weather)
    if _menu != null:
        _menu.show_weather(_initial_weather)
    _screen.stage("Ready", 1.0)
    await _rig.get_tree().process_frame
    _finish()


func _finish() -> void:
    _screen.dismiss()
    loading = false


## Where the vehicle starts, under what gravity, and what it may hit, before the terrain is
## handed over: taking the terrain puts the rig down, and it has to be put down where the
## terrain says.
func _hand_to_vehicle(wanted: RorTerrain) -> void:
    if drive == null:
        return
    drive.spawn = PlaySolid.clear_spawn(wanted)
    drive.solver.set_gravity(Vector3(0.0, wanted.gravity(), 0.0))
    var error: String = drive.use_terrain(terrain.get("data"))
    if error != "":
        printerr("PLAY  the solver could not take the terrain: " + error)
        return
    var solid: int = RorObjectCollision.apply(wanted, drive.solver)
    print("PLAY  driving on %s, spawned at %v under %.2f m/s^2; %d solid scenery parts"
        % [wanted.name, drive.spawn, wanted.gravity(), solid])


## Puts another map up, where this one was. Ignored while one is still being built.
func change(wanted: String) -> void:
    if wanted == name:
        return
    if loading:
        print("PLAY  still loading %s; %s can wait" % [name, wanted])
        return
    name = wanted
    clear(_world)
    if vegetation != null:
        vegetation.clear()
        vegetation = null
    terrain = null
    loaded = null
    build()
    print("PLAY  loading %s" % wanted)


## Removes everything a map built from a world. Returns how many nodes went.
static func clear(world: Node3D) -> int:
    var gone: int = 0
    for child: Node in world.get_children():
        for prefix: String in MAP_NODES:
            if child.name.begins_with(prefix):
                world.remove_child(child)
                child.queue_free()
                gone += 1
                break
    return gone


## The terrain's own vegetation, in a ring of tiles that follows whoever is driving.
func _grow_vegetation(wanted: RorTerrain) -> void:
    var grown: RorVegetation = RorVegetation.new()
    if grown.setup(wanted) != "":
        grown.free()
        return
    _world.add_child(grown)
    grown.focus_on(wanted.start_position())
    vegetation = grown
    if _menu != null:
        _menu.set_vegetation(grown)


## The terrain the session names: a library name, or a path to a directory holding a `.terrn2`.
## A terrain that will not load is reported and the library listed, rather than opening a window
## onto nothing.
func _load_terrain() -> RorTerrain:
    var result: Dictionary = RorTerrainLibrary.load_named(name)
    if (result["error"] as String) != "":
        printerr("PLAY  %s" % result["error"])
        for summary: Dictionary in RorTerrainLibrary.summaries():
            printerr("PLAY    %s (%s)" % [summary["name"], summary["title"]])
        return null
    return result["terrain"] as RorTerrain
