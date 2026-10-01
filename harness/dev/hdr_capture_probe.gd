extends SceneTree
## Can a captured frame carry values above 1.0?
##
## Everything this project measures about light is read back out of a capture, and a capture has
## been an 8-bit PNG. This asks the only question that matters before building an HDR path: does
## the viewport hand back a float image, and does a value brighter than white survive the trip.
##
##   godot --path . --headless --script res://harness/dev/hdr_capture_probe.gd

var _frames: int = 0
var _viewports: Array[SubViewport] = []


func _initialize() -> void:
    for hdr: bool in [false, true]:
        var viewport: SubViewport = SubViewport.new()
        viewport.size = Vector2i(64, 64)
        viewport.own_world_3d = true
        viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
        viewport.use_hdr_2d = hdr
        # A world with one unlit quad far brighter than white. Unlit, so nothing about lighting
        # or tonemapping decides the answer -- the albedo alone should arrive.
        var world: Node3D = Node3D.new()
        var environment: Environment = Environment.new()
        environment.background_mode = Environment.BG_COLOR
        environment.background_color = Color.BLACK
        environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
        environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
        environment.tonemap_exposure = 1.0
        var holder: WorldEnvironment = WorldEnvironment.new()
        holder.environment = environment
        world.add_child(holder)
        var quad: MeshInstance3D = MeshInstance3D.new()
        var plane: PlaneMesh = PlaneMesh.new()
        plane.size = Vector2(100.0, 100.0)
        plane.orientation = PlaneMesh.FACE_Z
        quad.mesh = plane
        var material: StandardMaterial3D = StandardMaterial3D.new()
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        material.albedo_color = Color(4.0, 4.0, 4.0)
        quad.material_override = material
        world.add_child(quad)
        var camera: Camera3D = Camera3D.new()
        camera.position = Vector3(0.0, 0.0, 5.0)
        world.add_child(camera)
        viewport.add_child(world)
        root.add_child(viewport)
        _viewports.append(viewport)


func _process(_delta: float) -> bool:
    _frames += 1
    if _frames < 4:
        return false
    for index: int in _viewports.size():
        var image: Image = _viewports[index].get_texture().get_image()
        var pixel: Color = image.get_pixel(32, 32)
        print("use_hdr_2d=%s  format=%d  pixel=(%.3f, %.3f, %.3f)" % [
            index == 1, image.get_format(), pixel.r, pixel.g, pixel.b
        ])
        var path: String = "res://artifacts/hdr_probe_%d.exr" % index
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
        print("  save_exr -> %d" % image.save_exr(path))
    return true
