extends SceneTree
## Does a physical camera in this build produce depth of field, and how much?
##
## A row of posts at known distances under a fast lens focused on the nearest of them. If Godot's
## `CameraAttributesPhysical` blurs from its own aperture and focus distance, the far posts come
## back soft and the near one sharp. If nothing blurs, depth of field is something this project
## has to ask for rather than something the lens already does.
##
##   godot --path . --resolution 960x540 --script res://harness/dev/dof_probe.gd

const SHOT: Vector2i = Vector2i(960, 540)
const WEATHER: String = "noon_clear"
const DISTANCES: Array[float] = [3.0, 6.0, 12.0, 24.0, 48.0]
const EYE: Vector3 = Vector3(0.0, 1.6, 0.0)
const FOCUS_M: float = 3.0
const FOCAL_MM: float = 85.0
const F_STOP: float = 1.8

var _frames: int = 0
var _views: Array[SubViewport] = []


func _initialize() -> void:
    for focused: bool in [false, true]:
        _views.append(_scene(focused))


func _scene(focused: bool) -> SubViewport:
    var viewport: SubViewport = SubViewport.new()
    viewport.size = SHOT
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    var weather: Dictionary = WeatherCfg.get_preset(WEATHER)
    var world: Node3D = BlockoutWorld.build(weather, false, false)

    for index: int in DISTANCES.size():
        world.add_child(_post(index))

    var camera: Camera3D = PhysicalCamera.build({
        "pos": EYE, "look_at": EYE + Vector3(0.0, 0.0, -10.0),
        "focal_mm": FOCAL_MM, "f_stop": F_STOP, "shutter_s": 0.002, "iso": 50.0,
    }, weather)
    if focused:
        var attributes: CameraAttributesPhysical = camera.attributes as CameraAttributesPhysical
        attributes.frustum_focus_distance = FOCUS_M
        print("focus distance set to %.2f, aperture f/%.1f, focal %.0f mm" % [
            attributes.frustum_focus_distance, attributes.exposure_aperture,
            attributes.frustum_focal_length
        ])
    world.add_child(camera)
    WorldSky.reexpose(world, camera)
    viewport.add_child(world)
    root.add_child(viewport)
    return viewport


## A thin bright post at its own distance, offset sideways so they do not hide each other.
func _post(index: int) -> MeshInstance3D:
    var post: MeshInstance3D = MeshInstance3D.new()
    var box: BoxMesh = BoxMesh.new()
    box.size = Vector3(0.08, 2.0, 0.08)
    post.mesh = box
    var white: StandardMaterial3D = StandardMaterial3D.new()
    white.albedo_color = Color(0.9, 0.9, 0.9)
    white.roughness = 0.9
    post.material_override = white
    var yaw: float = deg_to_rad((float(index) - 2.0) * 3.0)
    post.position = EYE + Vector3(sin(yaw), 0.0, -cos(yaw)) * DISTANCES[index]
    return post


func _process(_delta: float) -> bool:
    _frames += 1
    if _frames < 8:
        return false
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
    for index: int in _views.size():
        var image: Image = _views[index].get_texture().get_image()
        image.save_png("res://artifacts/dof_%s.png" % ["off" if index == 0 else "focused"])
    print("wrote artifacts/dof_off.png and artifacts/dof_focused.png")
    return true
