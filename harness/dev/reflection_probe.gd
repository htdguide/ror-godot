extends SceneTree
## Does a mirror in this project's world show the sky that is above it?
##
## A perfect mirror returns the radiance arriving along the reflected direction, so a chrome ball
## under an open sky photographs as the sky — a little darker at the edges where the reflected ray
## has turned towards the ground, and no darker than that anywhere. If it comes back far below the
## sky drawn in the same frame, the radiance map and the picture disagree, and everything that
## reflects anything in this project is wrong by that factor.
##
##   godot --path . --resolution 640x640 --script res://harness/dev/reflection_probe.gd

const SIZE: int = 512
const WEATHER: String = "noon_clear"
const AT: Vector3 = Vector3(0.0, 2.0, 0.0)

var _frames: int = 0
var _viewport: SubViewport = null


func _initialize() -> void:
    _viewport = SubViewport.new()
    _viewport.size = Vector2i(SIZE, SIZE)
    _viewport.own_world_3d = true
    _viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    var weather: Dictionary = WeatherCfg.get_preset(WEATHER)
    var world: Node3D = BlockoutWorld.build(weather, false, false)
    var ground: Node3D = world.get_node_or_null(^"Ground") as Node3D
    if ground != null:
        ground.visible = false

    var ball: MeshInstance3D = MeshInstance3D.new()
    var sphere: SphereMesh = SphereMesh.new()
    sphere.radius = 1.0
    sphere.height = 2.0
    sphere.radial_segments = 96
    sphere.rings = 48
    ball.mesh = sphere
    ball.position = AT
    var chrome: StandardMaterial3D = StandardMaterial3D.new()
    chrome.albedo_color = Color.WHITE
    chrome.metallic = 1.0
    chrome.roughness = 0.0
    ball.material_override = chrome
    world.add_child(ball)
    var holder: WorldEnvironment = world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    for argument: String in OS.get_cmdline_user_args():
        if argument == "--no-ssao":
            holder.environment.ssao_enabled = false
        if argument == "--full-radiance":
            var shaded: ShaderMaterial = holder.environment.sky.sky_material as ShaderMaterial
            shaded.set_shader_parameter("radiance_scale", 1.0)
        print("argument %s" % argument)

    var camera: Camera3D = PhysicalCamera.build({
        "pos": Vector3(0.0, 2.0, 5.0), "look_at": AT,
        "focal_mm": 50.0, "f_stop": 8.0, "shutter_s": 0.008,
    }, weather)
    world.add_child(camera)
    WorldSky.reexpose(world, camera)
    _viewport.add_child(world)
    root.add_child(_viewport)


func _process(_delta: float) -> bool:
    _frames += 1
    if _frames < 10:
        return false
    var image: Image = _viewport.get_texture().get_image()
    # The top of the ball reflects the sky straight up; a pixel near the top of the frame is that
    # same sky drawn directly.
    var ball_top: float = _mean(image, SIZE / 2, int(float(SIZE) * 0.34), 6)
    var sky_above: float = _mean(image, SIZE / 2, int(float(SIZE) * 0.06), 6)
    var ball_middle: float = _mean(image, SIZE / 2, SIZE / 2, 6)
    var sky_side: float = _mean(image, int(float(SIZE) * 0.06), SIZE / 2, 6)
    print("mirror top %.4f against the sky above it %.4f  (%.3fx)"
        % [ball_top, sky_above, ball_top / maxf(sky_above, 0.000001)])
    print("mirror middle %.4f against the sky beside it %.4f  (%.3fx)"
        % [ball_middle, sky_side, ball_middle / maxf(sky_side, 0.000001)])
    image.save_png("res://artifacts/reflection_probe.png")
    return true


func _mean(image: Image, x: int, y: int, reach: int) -> float:
    var total: float = 0.0
    var counted: int = 0
    for dy: int in range(-reach, reach + 1, 2):
        for dx: int in range(-reach, reach + 1, 2):
            var colour: Color = image.get_pixel(
                clampi(x + dx, 0, SIZE - 1), clampi(y + dy, 0, SIZE - 1)
            )
            total += colour.srgb_to_linear().get_luminance()
            counted += 1
    return total / maxf(float(counted), 1.0)
