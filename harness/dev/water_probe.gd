extends SceneTree
## Photographs the sea, so a change to the water shader can be looked at rather than argued about.
##
## Its own stage rather than a terrain: a tilted sea bed crossing the waterline is a beach, a few
## posts standing in the water show what refraction does to something straight, and a sunk plate
## shows what the depth fade does. All of it under the project's own noon, through the project's own
## camera, from the three angles that matter — down into it, across it, and along it toward the sun.
##
##   godot --path . --resolution 960x540 --script res://harness/dev/water_probe.gd
##
## Writes artifacts/water_probe_<view>.png.

const WEATHER: String = "noon_clear"
const SHOT: Vector2i = Vector2i(960, 540)
const WATER_Y: float = 0.0
const BED_TILT_DEG: float = 4.0
const VIEWS: Array[Dictionary] = [
    # Down into the shallows: the depth fade and the shoreline.
    {"name": "down", "pos": Vector3(0.0, 9.0, 2.0), "look_at": Vector3(0.0, 0.0, -14.0)},
    # Across it at standing height: the Fresnel ramp from under the eye out to the horizon.
    {"name": "across", "pos": Vector3(0.0, 1.7, 14.0), "look_at": Vector3(0.0, 0.0, -30.0)},
    # Into the sun, low: the glitter path, which is what says the surface has a slope.
    {"name": "sunward", "pos": Vector3(14.0, 1.2, 10.0), "look_at": Vector3(-20.0, 0.0, -24.0)},
]

var _frames: int = 0
var _views: Array[SubViewport] = []


func _initialize() -> void:
    for view: Dictionary in VIEWS:
        _views.append(_scene(view))


func _scene(view: Dictionary) -> SubViewport:
    var viewport: SubViewport = SubViewport.new()
    viewport.size = SHOT
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    var weather: Dictionary = WeatherCfg.get_preset(WEATHER)
    var world: Node3D = BlockoutWorld.build(weather, false, false)
    var ground: Node3D = world.get_node_or_null(^"Ground") as Node3D
    if ground != null:
        ground.visible = false

    world.add_child(_bed())
    for at: Vector3 in [Vector3(-3.0, 0.0, -4.0), Vector3(2.0, 0.0, -9.0), Vector3(5.5, 0.0, -2.0)]:
        world.add_child(_post(at))
    world.add_child(_plate(Vector3(-1.0, 0.0, -16.0)))
    world.add_child(_sea())
    var camera: Camera3D = PhysicalCamera.build({
        "pos": view["pos"] as Vector3,
        "look_at": view["look_at"] as Vector3,
        "focal_mm": 35.0,
        "f_stop": 8.0,
        "shutter_s": 0.008,
    }, weather)
    world.add_child(camera)
    WorldSky.reexpose(world, camera)
    viewport.add_child(world)
    root.add_child(viewport)
    return viewport


## A sea bed tilted so it comes up through the waterline: one side beach, the other side deep.
## The sea against the sky it mirrors.
##
## A ray leaving the eye just below the horizon reflects off a flat sea into the sky just above it,
## so those two bands are the same piece of sky and a mirror-flat sea has to match. The `across`
## view is level, so the horizon is the middle row of it.
func _report() -> void:
    var image: Image = _views[1].get_texture().get_image()
    var middle: int = _horizon(image)
    print("sea just under the horizon %.4f, sky just over it %.4f  (%.3fx)" % [
        _band(image, middle + 6), _band(image, middle - 6),
        _band(image, middle + 6) / maxf(_band(image, middle - 6), 0.000001)
    ])


## Which row of the frame the horizon is on: the row where the frame changes most from the one
## above it, which for a level camera over an open sea is the waterline.
func _horizon(image: Image) -> int:
    var best: int = SHOT.y / 2
    var worst_step: float = 0.0
    for y: int in range(10, SHOT.y - 10):
        var step: float = absf(_band(image, y) - _band(image, y - 4))
        if step > worst_step:
            worst_step = step
            best = y
    return best


## The mean of one row of the frame, in light rather than in what the file encodes.
func _band(image: Image, y: int) -> float:
    var total: float = 0.0
    var counted: int = 0
    for x: int in range(0, SHOT.x, 4):
        total += image.get_pixel(x, clampi(y, 0, SHOT.y - 1)).srgb_to_linear().get_luminance()
        counted += 1
    return total / maxf(float(counted), 1.0)


func _bed() -> MeshInstance3D:
    var bed: MeshInstance3D = MeshInstance3D.new()
    var plane: PlaneMesh = PlaneMesh.new()
    plane.size = Vector2(300.0, 300.0)
    bed.mesh = plane
    var sand: StandardMaterial3D = StandardMaterial3D.new()
    sand.albedo_color = Color(0.42, 0.36, 0.26)
    sand.roughness = 0.9
    bed.material_override = sand
    bed.rotation = Vector3(deg_to_rad(-BED_TILT_DEG), 0.0, 0.0)
    bed.position = Vector3(0.0, WATER_Y, 0.0)
    return bed


## A post standing in the water: straight, so refraction has something to bend.
func _post(at: Vector3) -> MeshInstance3D:
    var post: MeshInstance3D = MeshInstance3D.new()
    var box: BoxMesh = BoxMesh.new()
    box.size = Vector3(0.3, 4.0, 0.3)
    post.mesh = box
    var paint: StandardMaterial3D = StandardMaterial3D.new()
    paint.albedo_color = Color(0.85, 0.82, 0.78)
    paint.roughness = 0.6
    post.material_override = paint
    post.position = at + Vector3(0.0, 1.0, 0.0)
    return post


## A bright plate on the bed out in the deep, so the depth fade has something to swallow.
func _plate(at: Vector3) -> MeshInstance3D:
    var plate: MeshInstance3D = MeshInstance3D.new()
    var mesh: PlaneMesh = PlaneMesh.new()
    mesh.size = Vector2(6.0, 6.0)
    plate.mesh = mesh
    var white: StandardMaterial3D = StandardMaterial3D.new()
    white.albedo_color = Color(0.9, 0.9, 0.88)
    white.roughness = 0.8
    plate.material_override = white
    plate.position = at + Vector3(0.0, -0.45, 0.0)
    return plate


## The sea, the way `RorWater` builds it.
func _sea() -> MeshInstance3D:
    var sea: MeshInstance3D = MeshInstance3D.new()
    var plane: PlaneMesh = PlaneMesh.new()
    plane.size = Vector2(4000.0, 4000.0)
    plane.subdivide_width = 0
    plane.subdivide_depth = 0
    sea.mesh = plane
    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = load(RorWater.SHADER) as Shader
    material.render_priority = 1
    sea.material_override = material
    sea.position = Vector3(0.0, WATER_Y, 0.0)
    sea.extra_cull_margin = 4000.0
    sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    return sea


func _process(_delta: float) -> bool:
    _frames += 1
    if _frames < 8:
        return false
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
    _report()
    for index: int in _views.size():
        var image: Image = _views[index].get_texture().get_image()
        var path: String = "res://artifacts/water_probe_%s.png" % VIEWS[index]["name"]
        print("%s -> %d" % [path, image.save_png(path)])
    return true
