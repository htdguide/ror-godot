extends SceneTree
## What a clear coat does to the paint under it, Godot's and this project's side by side.
##
## One ball, the project's own noon, one exposure, and nothing changing between scenes but the
## coat. The number that matters is the middle of the ball, where the view is near normal to the
## surface: a clear coat is a dielectric film at IOR 1.5, it reflects 4% of what arrives head-on,
## so the paint under it should keep 96% of itself whatever the coat is set to.
##
##   godot --path . --resolution 320x320 --script res://harness/dev/paint_probe.gd

const SIZE: int = 256
const CAMERA: String = "hero_3q"
const WEATHER: String = "noon_clear"
## Where the ball stands: the subject position `hero_3q` is framed on, lifted clear of the ground.
const AT: Vector3 = Vector3(0.0, 1.1, 0.0)
const SHADER: String = "res://game/shaders/vehicle_paint.gdshader"
const PAINT: Color = Color(0.25, 0.03, 0.03)
## How wide the ball is in the frame, as a share of the frame's height. A 1 m ball at 6.3 m through
## a 50 mm lens on a 24 mm sensor subtends 18.3 degrees of a 27-degree view.
const BALL_SHARE: float = 0.34
const SETTINGS: Array[Dictionary] = [
    {"name": "godot, no coat", "shader": false, "clearcoat": 0.0},
    {"name": "godot, coat 0.25", "shader": false, "clearcoat": 0.25},
    {"name": "godot, coat 1.0", "shader": false, "clearcoat": 1.0},
    {"name": "ours, no coat", "shader": true, "clearcoat": 0.0},
    {"name": "ours, coat 0.25", "shader": true, "clearcoat": 0.25},
    {"name": "ours, coat 1.0", "shader": true, "clearcoat": 1.0},
    {"name": "ours, sheen 1.0", "shader": true, "clearcoat": 0.0, "sheen": 1.0},
]

var _frames: int = 0
var _viewports: Array[SubViewport] = []


func _initialize() -> void:
    var probe: StandardMaterial3D = StandardMaterial3D.new()
    var missing: PackedStringArray = PackedStringArray()
    for wanted: String in ["clearcoat", "clearcoat_roughness", "sheen", "transmission"]:
        if not (wanted in probe):
            missing.append(wanted)
    print("StandardMaterial3D in this build has no: %s" % ", ".join(missing))
    for setting: Dictionary in SETTINGS:
        _viewports.append(_scene(setting))


func _scene(setting: Dictionary) -> SubViewport:
    var viewport: SubViewport = SubViewport.new()
    viewport.size = Vector2i(SIZE, SIZE)
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

    # **The project's own noon, not a stage of this probe's invention.** A coat reflects the sky,
    # so the sky has to be the calibrated one: a sky energy guessed for this probe read as nothing
    # at 0.06 and as pure white at 4000, and neither says anything about paint.
    var weather: Dictionary = WeatherCfg.get_preset(WEATHER)
    var world: Node3D = BlockoutWorld.build(weather, false, false)

    var ball: MeshInstance3D = MeshInstance3D.new()
    var sphere: SphereMesh = SphereMesh.new()
    sphere.radius = 1.0
    sphere.height = 2.0
    sphere.radial_segments = 96
    sphere.rings = 48
    ball.mesh = sphere
    ball.position = AT
    ball.material_override = _ours(setting) if bool(setting["shader"]) else _godot(setting)
    world.add_child(ball)

    var camera: Camera3D = PhysicalCamera.build(CameraCfg.get_preset(CAMERA), weather)
    world.add_child(camera)
    WorldSky.reexpose(world, camera)
    viewport.add_child(world)
    root.add_child(viewport)
    return viewport


func _godot(setting: Dictionary) -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    var paint: Dictionary = MaterialCfg.CLASSES["car_paint"] as Dictionary
    material.albedo_color = PAINT
    material.metallic = float(paint["metallic"])
    material.roughness = float(paint["roughness"])
    if float(setting["clearcoat"]) > 0.0:
        material.clearcoat_enabled = true
        material.clearcoat = float(setting["clearcoat"])
        material.clearcoat_roughness = 0.06
    return material


func _ours(setting: Dictionary) -> ShaderMaterial:
    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = load(SHADER) as Shader
    var paint: Dictionary = MaterialCfg.CLASSES["car_paint"] as Dictionary
    material.set_shader_parameter("albedo", PAINT)
    material.set_shader_parameter("metallic", float(paint["metallic"]))
    material.set_shader_parameter("roughness", float(paint["roughness"]))
    material.set_shader_parameter("clearcoat", float(setting["clearcoat"]))
    material.set_shader_parameter("clearcoat_roughness", 0.06)
    material.set_shader_parameter("sheen", float(setting.get("sheen", 0.0)))
    return material


func _process(_delta: float) -> bool:
    _frames += 1
    if _frames < 8:
        return false
    var baselines: Dictionary = {}
    for index: int in _viewports.size():
        var image: Image = _viewports[index].get_texture().get_image()
        var setting: Dictionary = SETTINGS[index]
        var side: String = "ours" if bool(setting["shader"]) else "godot"
        var middle: float = _ring(image, 0.0)
        if float(setting["clearcoat"]) == 0.0 and float(setting.get("sheen", 0.0)) == 0.0:
            baselines[side] = middle
        print("%-17s middle %.4f (%.3fx its own bare paint)  half %.4f  rim %.4f" % [
            setting["name"], middle,
            middle / maxf(baselines.get(side, middle) as float, 0.000001),
            _ring(image, 0.6), _ring(image, 0.92)
        ])
        image.save_png("res://artifacts/paint_probe_%d.png" % index)
    return true


## The mean luminance of a ring on the ball, at a share of the way out to its silhouette. The
## middle of the ball faces the camera; the rim is grazing, which is where Fresnel is strongest and
## where a cloth lobe lives.
func _ring(image: Image, out: float) -> float:
    var radius: float = float(SIZE) * BALL_SHARE * out
    if out <= 0.0:
        return image.get_pixel(SIZE / 2, SIZE / 2).get_luminance()
    var total: float = 0.0
    var counted: int = 0
    for degrees: int in range(0, 360, 2):
        var radians: float = deg_to_rad(float(degrees))
        var x: int = clampi(int(float(SIZE) * 0.5 + cos(radians) * radius), 0, SIZE - 1)
        var y: int = clampi(int(float(SIZE) * 0.5 + sin(radians) * radius), 0, SIZE - 1)
        total += image.get_pixel(x, y).get_luminance()
        counted += 1
    return total / maxf(float(counted), 1.0)
