extends SceneTree
## Photographs any vehicle in the library from every side, the way `vehicle_photoset` does the
## hero truck. For looking at a mod that is reported broken.
##
##   godot --path . --resolution 900x600 --script res://harness/dev/vehicle_shots.gd -- \
##       assets/mods/mazda626gf mazda626sd18i-mt.car

const SIZE: Vector2i = Vector2i(900, 600)
const WEATHER: String = "noon_clear"
const FRAMES: int = 24
## Settle it the way a window does before photographing it. Built and never stepped, a rig stands
## in its file's own rest pose and its skinned parts have never been driven by the solver, which is
## not what anybody looking at the car is looking at.
const SETTLE_SECONDS: float = 2.0

var _viewport: Viewport = null
var _root: Node3D = null
var _camera: Camera3D = null
var _bounds: AABB = AABB()
var _interior: Vector3 = Vector3.ZERO
var _frames: int = 0
var _view: int = 0
var _out: String = ""


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    var directory: String = SourceScan.repo_root().path_join(argv[0])
    _out = SourceScan.repo_root().path_join("artifacts/vehicle_shots")
    DirAccess.make_dir_recursive_absolute(_out)
    var built: Dictionary = VehicleBuilder.build(directory, argv[1])
    if (built.get("error", "") as String) != "":
        printerr(built["error"])
        quit(1)
        return
    var weather: Dictionary = WeatherCfg.get_preset(WEATHER)
    var world: Node3D = BlockoutWorld.build(weather, false, false)
    _root = built["root"] as Node3D
    world.add_child(_root)
    _camera = PhysicalCamera.build(CameraCfg.get_preset("hero_3q"), weather)
    world.add_child(_camera)
    WorldSky.reexpose(world, _camera)
    # **The main viewport, not a SubViewport with a world of its own.** A skinned part attaches
    # its skeleton to the scenario it is in, and a fresh world made after the parts were built
    # loses that attachment silently: the mesh then draws at its rest pose, which is rig space.
    # On the hero truck that is six centimetres and invisible; on the Mazda it is 2.4 m, and it
    # looks exactly like a frame bug in the loader. It is not one — `vehicle_assembly` renders the
    # same vehicle through the harness and finds every part within a thousandth of a millimetre.
    root.add_child(world)
    _viewport = root
    var truck: TruckParser = built["truck"] as TruckParser
    var rig: Dictionary = RigBuilder.build(truck, 0.15)
    if (rig.get("error", "") as String) != "":
        printerr(rig["error"])
        quit(1)
        return
    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.15)
    for _i: int in int(SETTLE_SECONDS * 60.0):
        solver.step(1.0 / 2000.0, 33)
    var angles: PackedFloat32Array = PackedFloat32Array()
    for wheel: int in solver.wheel_count():
        angles.append(solver.get_wheel_rotation(wheel))
    # "nopose" leaves the vehicle exactly as `VehicleBuilder.build` left it, which is the state
    # `vehicle_assembly` measures. Driving it is what a window does, and the two are not the same.
    if (argv[2] if argv.size() > 2 else "") != "nopose":
        VehicleBuilder.apply_pose(built, truck, solver.get_positions(), angles)
    # Optional third argument hides one half of the vehicle, so that a part which is in the wrong
    # place can be told from a part the camera is merely framing oddly.
    var only: String = argv[2] if argv.size() > 2 else "all"
    if only == "body" or only == "rigid":
        for part: SkinnedFlexbody in built["parts"] as Array[SkinnedFlexbody]:
            part.mesh_instance.visible = only == "body"
        for node: Node3D in built["prop_nodes"] as Array[Node3D]:
            node.visible = only == "rigid"
        for node: Node3D in built["wheel_nodes"] as Array[Node3D]:
            node.visible = only == "rigid"
    _bounds = VehicleBuilder.world_bounds(_root)
    _interior = _bounds.get_center()
    print("%s: %d parts, bounds %.2f x %.2f x %.2f m at %v" % [
        argv[1], _root.get_child_count(), _bounds.size.x, _bounds.size.y, _bounds.size.z,
        _bounds.get_center()])
    _aim()


func _aim() -> void:
    var placement: Dictionary = Photoset.placement(Photoset.VIEWS[_view], _bounds, _interior)
    _camera.look_at_from_position(
        placement["pos"] as Vector3, placement["look_at"] as Vector3, Vector3.UP
    )


func _process(_delta: float) -> bool:
    _frames += 1
    if _frames < FRAMES:
        return false
    _frames = 0
    var image: Image = _viewport.get_texture().get_image()
    image.save_png("%s/%s.png" % [_out, Photoset.VIEWS[_view]])
    print("  %s" % Photoset.VIEWS[_view])
    _view += 1
    if _view >= Photoset.VIEWS.size():
        return true
    _aim()
    return false
