extends SceneTree
## The white furnace: under a uniform sky, a white ball must vanish into it.
##
## A surface lit from every direction by the same radiance `L`, whose albedo is 1 and which absorbs
## nothing, must send `L` back whatever its roughness and whatever it is made of. Energy in equals
## energy out. So a white ball photographed against the sky that lights it should be invisible —
## and any part of it that is darker is light the renderer lost, any part brighter is light it
## invented.
##
## Nothing in this is a number this project chose. It is the oldest test in rendering and the
## answer is "you cannot see the ball".
##
##   godot --path . --resolution 640x640 --script res://harness/dev/furnace_probe.gd

const SIZE: int = 420
## The furnace's own radiance. Low, because the measurement is a ratio and both ends of an 8-bit
## channel are places where a ratio stops meaning anything: at 1.0 and above every frame came back
## clipped to white and the ball vanished for the wrong reason.
const FURNACE: float = 0.5
const ROUGHNESSES: Array[float] = [0.0, 0.15, 0.35, 0.6, 1.0]

var _frames: int = 0
var _views: Array[SubViewport] = []
var _labels: PackedStringArray = PackedStringArray()


func _initialize() -> void:
    print("furnace %.4f" % FURNACE)
    for metallic: float in [0.0, 1.0]:
        for roughness: float in ROUGHNESSES:
            _labels.append(
                "%s roughness %.2f" % ["metal" if metallic > 0.5 else "dielectric", roughness]
            )
            _views.append(_scene(metallic, roughness))


func _scene(metallic: float, roughness: float) -> SubViewport:
    var viewport: SubViewport = SubViewport.new()
    viewport.size = Vector2i(SIZE, SIZE)
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    var world: Node3D = Node3D.new()

    # The furnace: one radiance from every direction, and no light in the scene at all.
    var environment: Environment = Environment.new()
    environment.background_mode = Environment.BG_SKY
    var sky: Sky = Sky.new()
    sky.process_mode = Sky.PROCESS_MODE_QUALITY
    sky.radiance_size = Sky.RADIANCE_SIZE_256
    var paint: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
    paint.sky_top_color = Color.WHITE
    paint.sky_horizon_color = Color.WHITE
    paint.ground_bottom_color = Color.WHITE
    paint.ground_horizon_color = Color.WHITE
    # One multiplier, not three: these compound, so setting all of them made the furnace the cube
    # of what it said.
    paint.sky_energy_multiplier = 1.0
    paint.ground_energy_multiplier = 1.0
    paint.energy_multiplier = FURNACE
    paint.sun_angle_max = 0.0
    sky.sky_material = paint
    environment.sky = sky
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    environment.ambient_light_sky_contribution = 1.0
    environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    environment.tonemap_exposure = 1.0
    var holder: WorldEnvironment = WorldEnvironment.new()
    holder.environment = environment
    world.add_child(holder)

    var ball: MeshInstance3D = MeshInstance3D.new()
    var sphere: SphereMesh = SphereMesh.new()
    sphere.radius = 1.0
    sphere.height = 2.0
    sphere.radial_segments = 96
    sphere.rings = 48
    ball.mesh = sphere
    var white: StandardMaterial3D = StandardMaterial3D.new()
    white.albedo_color = Color.WHITE
    white.metallic = metallic
    white.roughness = roughness
    ball.material_override = white
    world.add_child(ball)

    var camera: Camera3D = Camera3D.new()
    # Physical light units are on for this project, so a camera without the photographer's three
    # numbers has no exposure and every frame comes back clipped to white.
    var attributes: CameraAttributesPhysical = CameraAttributesPhysical.new()
    attributes.auto_exposure_enabled = false
    attributes.exposure_aperture = 8.0
    attributes.exposure_shutter_speed = 400.0
    attributes.exposure_sensitivity = 100.0
    camera.attributes = attributes
    camera.position = Vector3(0.0, 0.0, 4.0)
    world.add_child(camera)
    viewport.add_child(world)
    root.add_child(viewport)
    return viewport


func _process(_delta: float) -> bool:
    _frames += 1
    if _frames < 12:
        return false
    for index: int in _views.size():
        var image: Image = _views[index].get_texture().get_image()
        var furnace: float = _at(image, 0.04, 0.5)
        print("%-24s middle %.4f  rim %.4f  against the furnace %.4f  (%.3fx, %.3fx)" % [
            _labels[index], _at(image, 0.5, 0.5), _ring(image, 0.93), furnace,
            _at(image, 0.5, 0.5) / maxf(furnace, 0.000001),
            _ring(image, 0.93) / maxf(furnace, 0.000001)
        ])
        image.save_png("res://artifacts/furnace_%d.png" % index)
    return true


func _at(image: Image, u: float, v: float) -> float:
    return image.get_pixel(int(u * SIZE), int(v * SIZE)).srgb_to_linear().get_luminance()


## A ring on the ball, at a share of the way out to its silhouette. The ball is 2 m across, 4 m
## from a 75-degree camera, so it spans a known part of the frame.
func _ring(image: Image, out: float) -> float:
    var radius: float = float(SIZE) * 0.5 * 0.407 * out
    var total: float = 0.0
    var counted: int = 0
    for degrees: int in range(0, 360, 2):
        var radians: float = deg_to_rad(float(degrees))
        var x: int = clampi(int(float(SIZE) * 0.5 + cos(radians) * radius), 0, SIZE - 1)
        var y: int = clampi(int(float(SIZE) * 0.5 + sin(radians) * radius), 0, SIZE - 1)
        total += image.get_pixel(x, y).srgb_to_linear().get_luminance()
        counted += 1
    return total / maxf(float(counted), 1.0)
