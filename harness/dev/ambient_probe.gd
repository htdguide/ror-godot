extends SceneTree
## Does Godot's exposure normalisation reach the ambient term, and does the answer depend on where
## the ambient comes from?
##
## Two measurements in this project disagree. `BlockoutWorld` pre-multiplies `ambient_light_energy`
## by the camera's own exposure scale, citing a surface lit only by `ambient_light_color` that
## photographed identically across three stops — so the normalisation does not reach it. And
## `one_stop_is_one_stop` finds a sunlit patch under this project's sky brightening by 2.1623 per
## stop instead of 2, which fits a frame where about 8% of the light is exposed twice.
##
## Both can be true if the answer depends on the *source*: a stated ambient colour and a sky's own
## irradiance are different quantities, and only one of them is light the renderer has measured.
## This asks the question directly — a grey patch, no other light in the scene, read across three
## stops, once for each source.
##
##   godot --path . --resolution 480x270 --script res://harness/dev/ambient_probe.gd

const SIZE: int = 256
const PATCH_AT: Vector3 = Vector3(0.0, 0.0, 0.0)
## Three stops apart, by shutter so that nothing about the lens changes with them.
const SHUTTERS: Array[float] = [500.0, 250.0, 125.0]
const SOURCES: Array[String] = ["colour", "sky"]

var _frames: int = 0
var _views: Array[SubViewport] = []
var _labels: PackedStringArray = PackedStringArray()


func _initialize() -> void:
    for source: String in SOURCES:
        for shutter: float in SHUTTERS:
            _labels.append("%s at 1/%.0f" % [source, shutter])
            _views.append(_scene(source, shutter))


func _scene(source: String, shutter: float) -> SubViewport:
    var viewport: SubViewport = SubViewport.new()
    viewport.size = Vector2i(SIZE, SIZE)
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    var world: Node3D = Node3D.new()

    var environment: Environment = Environment.new()
    environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    environment.tonemap_exposure = 1.0
    if source == "colour":
        # A stated colour, and no sky whatsoever.
        environment.background_mode = Environment.BG_COLOR
        environment.background_color = Color.BLACK
        environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
        environment.ambient_light_color = Color.WHITE
        environment.ambient_light_sky_contribution = 0.0
        environment.ambient_light_energy = 0.4
    else:
        # The sky's own irradiance, from a uniform white sky, with the energy left at one so that
        # what is measured is the sky and not a multiplier on it.
        var sky: Sky = Sky.new()
        sky.process_mode = Sky.PROCESS_MODE_QUALITY
        var paint: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
        paint.sky_top_color = Color.WHITE
        paint.sky_horizon_color = Color.WHITE
        paint.ground_bottom_color = Color.WHITE
        paint.ground_horizon_color = Color.WHITE
        paint.sky_energy_multiplier = 1.0
        paint.ground_energy_multiplier = 1.0
        paint.energy_multiplier = 0.35
        paint.sun_angle_max = 0.0
        sky.sky_material = paint
        environment.background_mode = Environment.BG_SKY
        environment.sky = sky
        environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
        environment.ambient_light_sky_contribution = 1.0
        environment.ambient_light_energy = 1.0
    var holder: WorldEnvironment = WorldEnvironment.new()
    holder.environment = environment
    world.add_child(holder)

    var patch: MeshInstance3D = MeshInstance3D.new()
    var quad: QuadMesh = QuadMesh.new()
    quad.size = Vector2(4.0, 4.0)
    patch.mesh = quad
    var grey: StandardMaterial3D = StandardMaterial3D.new()
    grey.albedo_color = Color(0.5, 0.5, 0.5)
    grey.roughness = 1.0
    patch.material_override = grey
    patch.position = PATCH_AT
    world.add_child(patch)

    var camera: Camera3D = Camera3D.new()
    var attributes: CameraAttributesPhysical = CameraAttributesPhysical.new()
    attributes.auto_exposure_enabled = false
    attributes.exposure_aperture = 8.0
    attributes.exposure_shutter_speed = shutter
    attributes.exposure_sensitivity = 50.0
    camera.attributes = attributes
    camera.position = PATCH_AT + Vector3(0.0, 0.0, 3.0)
    world.add_child(camera)
    viewport.add_child(world)
    root.add_child(viewport)
    return viewport


func _process(_delta: float) -> bool:
    _frames += 1
    if _frames < 10:
        return false
    var readings: PackedFloat32Array = PackedFloat32Array()
    for index: int in _views.size():
        var image: Image = _views[index].get_texture().get_image()
        readings.append(image.get_pixel(SIZE / 2, SIZE / 2).srgb_to_linear().get_luminance())
        print("%-22s %.5f" % [_labels[index], readings[index]])
    for source: int in SOURCES.size():
        var base: float = readings[source * SHUTTERS.size()]
        var said: PackedStringArray = PackedStringArray()
        for step: int in range(1, SHUTTERS.size()):
            said.append("%.3fx" % (readings[source * SHUTTERS.size() + step] / maxf(base, 1e-9)))
        print("%s: one stop %s, two stops %s  (a stop is 2 and 4)" % [
            SOURCES[source], said[0], said[1]
        ])
    return true
