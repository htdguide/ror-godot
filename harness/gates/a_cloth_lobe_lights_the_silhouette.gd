extends GateBase
## A cloth surface lights up at its silhouette, where no roughness setting puts light.
##
## **The oracle is where the Charlie distribution has its peak.** Estevez & Kulla (2017) replace
## the microfacet lobe with
##
##     D(h) = (2 + 1/r) * sin(theta_h)^(1/r) / 2pi
##
## which is zero at the mirror direction — `sin(theta_h) = 0`, where a GGX lobe has all of its
## energy — and largest when the half vector lies in the surface. That is the whole character of
## velvet, brushed cloth and the bloom around a worn tyre, and it is why `MaterialCfg` has stated a
## sheen for seats and tyres since it was written. Nothing read it: `StandardMaterial3D` in Godot
## 4.7 has no sheen property at all, so the number went nowhere.
##
## So: one ball, lit from exactly where the camera is. At the middle of the ball the half vector is
## the normal and a sheen lobe must contribute nothing. Towards the silhouette the half vector
## turns into the surface and the sheen must be what lights it. Photographed with the sheen off and
## then on, the ratio between the two frames has to be flat in the middle and rise at the rim —
## which no value of `roughness` can do, because every microfacet lobe peaks in the middle of this
## framing rather than at its edge.

const PRESET: String = "diag_topdown"
## No sun and no sky: this gate brings its own light, pointing where the camera looks.
const WEATHER: String = "spike_black"
const CONVERGE: int = 4
const BALL_RADIUS: float = 1.0
const BALL_AT: Vector3 = Vector3(0.0, 1.0, 0.0)
const LIGHT_LUX: float = 60000.0
## Where on the ball the two rings are read, as a share of the way out to the silhouette. Not at
## the silhouette itself, which is one pixel of anti-aliasing wide.
const MIDDLE_RING: float = 0.25
const RIM_RING: float = 0.85
## The middle must not change: the lobe is zero there and a sheen that brightens it is a lobe
## pointing the wrong way. The rim must change by enough to see.
const MIDDLE_TOLERANCE: float = 0.06
const MIN_RIM_GAIN: float = 1.15
const USABLE: Vector2 = Vector2(0.02, 0.9)


static func meta() -> Dictionary:
    return {
        "name": "a_cloth_lobe_lights_the_silhouette",
        "proves": "a stated sheen lights a surface at its silhouette and leaves the middle of it alone, which is where the Charlie distribution has its energy and no roughness has any",
        "builds_on": ["a_clear_coat_keeps_the_paint_under_it"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "the middle within %.2f of unchanged and the rim at least %.2fx brighter"
            % [MIDDLE_TOLERANCE, MIN_RIM_GAIN]
        ),
        "why": (
            "the sheen in `MaterialCfg` was read by nothing for as long as it existed, because"
            + " Godot has no such property, so seats and tyres were drawn as plain dielectrics."
            + " A lobe that is simply added everywhere would brighten a surface and look like"
            + " cloth in a screenshot; what makes it cloth is that the light is at the"
            + " silhouette and not in the middle, and that is a property of the published"
            + " distribution rather than a judgement about the picture."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var err: String = harness.setup_for(PRESET, WEATHER)
    if err != "":
        return fail(err)
    clear_fog(harness)
    var environment: Environment = _environment(harness)
    if environment == null:
        return fail("the world has no environment to configure")
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color.BLACK
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
    environment.ambient_light_energy = 0.0
    environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    environment.tonemap_exposure = 1.0

    # Lit from where the camera is, so the half vector is the normal at the middle of the ball.
    var lamp: DirectionalLight3D = DirectionalLight3D.new()
    lamp.light_intensity_lux = LIGHT_LUX
    lamp.shadow_enabled = false
    lamp.look_at_from_position(
        harness.camera.global_position, BALL_AT, Vector3.FORWARD
    )
    harness.world.add_child(lamp)

    var ball: MeshInstance3D = _ball()
    var material: ShaderMaterial = _cloth(0.0)
    ball.material_override = material
    harness.world.add_child(ball)

    var bare: Dictionary = await _rings(harness, "bare")
    if (bare["error"] as String) != "":
        return fail(bare["error"] as String)
    material.set_shader_parameter(
        "sheen", float((MaterialCfg.CLASSES["leather_cloth"] as Dictionary)["sheen"])
    )
    var cloth: Dictionary = await _rings(harness, "cloth")
    if (cloth["error"] as String) != "":
        return fail(cloth["error"] as String)

    for reading: Dictionary in [bare, cloth]:
        for key: String in ["middle", "rim"]:
            var value: float = reading[key] as float
            if value < USABLE.x or value > USABLE.y:
                return fail(
                    "the %s ring photographed at %.4f, outside the %.2f to %.2f the measurement"
                    % [key, value, USABLE.x, USABLE.y]
                    + " needs: the exposure, not the cloth, is what this frame is measuring",
                    value
                )

    var middle_gain: float = (cloth["middle"] as float) / maxf(bare["middle"] as float, 0.000001)
    var rim_gain: float = (cloth["rim"] as float) / maxf(bare["rim"] as float, 0.000001)
    if absf(middle_gain - 1.0) > MIDDLE_TOLERANCE:
        return fail(
            "the sheen changed the middle of the ball by %.3f, where the half vector is the"
            % absf(middle_gain - 1.0)
            + " normal and the Charlie lobe is zero: this is a lobe pointing the wrong way,"
            + " not cloth",
            middle_gain
        )
    if rim_gain < MIN_RIM_GAIN:
        return fail(
            "the sheen brightened the silhouette by %.3fx, under the %.2fx this gate asks for:"
            % [rim_gain, MIN_RIM_GAIN]
            + " a sheen nobody can see is the same as the one Godot does not have",
            rim_gain
        )
    return ok(
        "a stated sheen of %.2f leaves the middle at %.3fx and lights the silhouette at %.3fx"
        % [
            float((MaterialCfg.CLASSES["leather_cloth"] as Dictionary)["sheen"]),
            middle_gain, rim_gain
        ],
        rim_gain
    )


func _environment(harness: Node) -> Environment:
    var holder: WorldEnvironment = (
        harness.world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    )
    return null if holder == null else holder.environment


func _ball() -> MeshInstance3D:
    var ball: MeshInstance3D = MeshInstance3D.new()
    var sphere: SphereMesh = SphereMesh.new()
    sphere.radius = BALL_RADIUS
    sphere.height = BALL_RADIUS * 2.0
    sphere.radial_segments = 96
    sphere.rings = 48
    ball.mesh = sphere
    ball.position = BALL_AT
    return ball


func _cloth(sheen: float) -> ShaderMaterial:
    var material: ShaderMaterial = ShaderMaterial.new()
    var cloth: Dictionary = MaterialCfg.CLASSES["leather_cloth"] as Dictionary
    material.shader = load(VehiclePaint.SHADER_PATH) as Shader
    material.set_shader_parameter("albedo", Color(0.35, 0.3, 0.28))
    material.set_shader_parameter("metallic", float(cloth["metallic"]))
    material.set_shader_parameter("roughness", float(cloth["roughness"]))
    material.set_shader_parameter("clearcoat", 0.0)
    material.set_shader_parameter("sheen", sheen)
    material.set_shader_parameter("sheen_roughness", MaterialCfg.SHEEN_ROUGHNESS)
    return material


## The mean luminance of two rings on the ball, in light rather than in what the file encodes.
func _rings(harness: Node, tag: String) -> Dictionary:
    var shot: Dictionary = await harness.capture_shot("sheen/%s" % tag, "static", CONVERGE)
    if (shot["error"] as String) != "":
        return {"error": shot["error"] as String}
    var image: Image = Image.load_from_file(shot["png"] as String)
    if image == null:
        return {"error": "the capture at %s could not be read" % shot["png"]}
    # How wide the ball is in the frame, from the camera rather than from an assumption: the
    # silhouette is the projection of a point one radius to the side of its middle.
    var centre: Vector2 = harness.camera.unproject_position(BALL_AT)
    var edge: Vector2 = harness.camera.unproject_position(
        BALL_AT + harness.camera.global_transform.basis.x * BALL_RADIUS
    )
    var radius: float = centre.distance_to(edge)
    return {
        "error": "",
        "middle": _ring(harness, image, centre, radius * MIDDLE_RING),
        "rim": _ring(harness, image, centre, radius * RIM_RING),
    }


func _ring(harness: Node, image: Image, centre: Vector2, radius: float) -> float:
    var size: Vector2i = image.get_size()
    var viewport: Vector2 = harness.render_viewport().get_visible_rect().size
    var scale: Vector2 = Vector2(float(size.x) / viewport.x, float(size.y) / viewport.y)
    var total: float = 0.0
    var counted: int = 0
    for degrees: int in range(0, 360, 3):
        var radians: float = deg_to_rad(float(degrees))
        var at: Vector2 = (centre + Vector2(cos(radians), sin(radians)) * radius) * scale
        var colour: Color = image.get_pixel(
            clampi(int(at.x), 0, size.x - 1), clampi(int(at.y), 0, size.y - 1)
        )
        total += colour.srgb_to_linear().get_luminance()
        counted += 1
    return total / maxf(float(counted), 1.0)
