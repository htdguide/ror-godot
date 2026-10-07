extends SceneTree
## Why the hero truck's bed shines at dawn.
##
## Reported from a window: at 6.1 h the bed is bright in a way the hour does not look like it should
## allow. The sun is 1.62 degrees up there, so a horizontal panel takes almost none of it directly —
## which leaves the reflection. This photographs the same truck at the same hour with its clear coat
## as it ships and with the coat taken away, and prints what the bed reads in each.
##
##   godot --path . --resolution 960x540 --script res://harness/dev/bed_probe.gd

const SHOT: Vector2i = Vector2i(960, 540)
const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const HOURS: Array[float] = [5.9, 6.1, 6.5, 12.0]

var _frames: int = 0
var _views: Array[SubViewport] = []
var _labels: PackedStringArray = PackedStringArray()


func _initialize() -> void:
    for coated: bool in [true, false]:
        for hour: float in HOURS:
            _labels.append("%s %.1f h" % ["coated" if coated else "bare", hour])
            _views.append(_scene(hour, coated))


func _scene(hour: float, coated: bool) -> SubViewport:
    var viewport: SubViewport = SubViewport.new()
    viewport.size = SHOT
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    var weather: Dictionary = DayCycle.at(hour)
    var world: Node3D = BlockoutWorld.build(weather, false, false)

    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    var result: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    var vehicle: Node3D = result.get("root", null) as Node3D
    if vehicle != null:
        world.add_child(vehicle)
        if not coated:
            _strip_coat(vehicle)

    var camera: Camera3D = PhysicalCamera.build({
        "pos": Vector3(3.4, 2.4, 3.6), "look_at": Vector3(0.0, 0.9, 0.0),
        "focal_mm": 50.0, "f_stop": float(weather.get("f_stop", 5.6)),
        "shutter_s": float(weather.get("shutter_s", 0.008)),
        "iso": float(weather.get("iso", 100.0)),
    }, weather)
    world.add_child(camera)
    WorldSky.reexpose(world, camera)
    viewport.add_child(world)
    root.add_child(viewport)
    return viewport


## Takes the clear coat off every painted surface, leaving everything else as it was.
func _strip_coat(node: Node) -> void:
    var instance: MeshInstance3D = node as MeshInstance3D
    if instance != null and instance.mesh != null:
        for surface: int in instance.mesh.get_surface_count():
            var material: ShaderMaterial = (
                instance.mesh.surface_get_material(surface) as ShaderMaterial
            )
            if material != null and VehiclePaint.is_paint(material):
                material.set_shader_parameter("clearcoat", 0.0)
    for child: Node in node.get_children():
        _strip_coat(child)


func _process(_delta: float) -> bool:
    _frames += 1
    if _frames < 10:
        return false
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
    for index: int in _views.size():
        var image: Image = _views[index].get_texture().get_image()
        print("%-16s brightest %.4f  mean %.4f" % [
            _labels[index], _brightest(image), _mean(image)
        ])
        image.save_png("res://artifacts/bed_%s.png" % _labels[index].replace(" ", "_").replace(".", "_"))
    return true


func _brightest(image: Image) -> float:
    var best: float = 0.0
    for y: int in range(0, SHOT.y, 2):
        for x: int in range(0, SHOT.x, 2):
            best = maxf(best, image.get_pixel(x, y).srgb_to_linear().get_luminance())
    return best


func _mean(image: Image) -> float:
    var total: float = 0.0
    var counted: int = 0
    for y: int in range(0, SHOT.y, 4):
        for x: int in range(0, SHOT.x, 4):
            total += image.get_pixel(x, y).srgb_to_linear().get_luminance()
            counted += 1
    return total / maxf(float(counted), 1.0)
