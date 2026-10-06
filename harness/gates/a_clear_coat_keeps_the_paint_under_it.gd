extends GateBase
## A clear coat reflects 4% of what arrives head-on, so the paint under it keeps 96% of itself.
##
## **The oracle is Fresnel's equation at normal incidence**, which for a dielectric is
##
##     F0 = ((1 - n) / (1 + n))^2
##
## and for automotive lacquer at n = 1.5 is 0.04. Nothing about this number is this project's: it
## is the same 0.04 the glTF metallic-roughness specification states for every dielectric, and the
## same one `KHR_materials_clearcoat` composes a coated surface with —
##
##     colour = base * (1 - clearcoat * F) + clearcoat_brdf
##
## So a patch of paint photographed face-on, with the coat off and then fully on, must come back
## darker by exactly that 4% and by nothing else.
##
## **Godot's own clearcoat is in the frame as the control.** It has the property and it does not
## layer — it trades the paint away for the highlight, and measured here it keeps far less of the
## paint than a film can account for. A gate that cannot tell the two apart would be measuring
## nothing, so the control failing the same bound is part of the claim.
##
## The light is one sun and nothing else: ambient and the sky's reflection are turned off for the
## measurement, because neither is attenuated by the coat in this shader — see the gap recorded in
## `vehicle_paint.gdshader` — and either one would dilute the ratio toward 1 and make a broken
## coat look fine.

const PRESET: String = "diag_topdown"
const WEATHER: String = "noon_clear"
const CONVERGE: int = 4
## The refractive index of automotive clear lacquer, and the patch's own albedo. Mid-grey rather
## than a paint colour, so the measurement lands in the middle of the film's range: the claim is
## about a ratio and the pigment has nothing to do with it.
const CLEARCOAT_IOR: float = 1.5
const PATCH_ALBEDO: Color = Color(0.5, 0.5, 0.5)
## **A lab exposure, because this frame is not a photograph of anything.** With the ambient and
## the sky's reflection taken away, a patch lit by the sun alone lands near the bottom of the film
## — measured at 0.0117, where a couple of 8-bit levels is most of the signal. The tonemapper is
## linear here, so a multiplier moves every patch by the same factor and the ratio the gate reads
## is untouched.
const LAB_EXPOSURE: float = 1.0
const PATCH_SIZE: float = 1.3
const PATCH_HEIGHT: float = 1.0
const PATCH_SPACING: float = 1.5
## 8-bit output through an sRGB encode, so a couple of levels of slack on a ratio.
const TOLERANCE: float = 0.02
## How far Godot's own coat has to be outside that bound for this gate to be measuring anything.
const CONTROL_MARGIN: float = 0.02
## The band a patch has to land in to be measurable at all: not clipped, not in the noise.
const USABLE: Vector2 = Vector2(0.02, 0.9)
## What each patch is, in the order they are placed, for a failure that has to name one.
const NAMES: Array[String] = ["ours bare", "ours coated", "godot bare", "godot coated"]


static func meta() -> Dictionary:
    return {
        "name": "a_clear_coat_keeps_the_paint_under_it",
        "proves": "a fully coated surface keeps the Fresnel share of its paint — 96% at normal incidence for lacquer at IOR 1.5 — where Godot's own clearcoat does not",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "retention within %.2f of 1 - F0, with F0 from Fresnel at IOR %.1f"
            % [TOLERANCE, CLEARCOAT_IOR]
        ),
        "why": (
            "a coat that darkens the paint instead of layering over it is the difference"
            + " between a panel and a sheet of smoked glass, and it is invisible in any one"
            + " image — what gives it away is the ratio between the same panel coated and bare."
            + " Godot's property loses two thirds of the paint at full strength, which is why"
            + " this project's car paint sat at a coverage of 0.25: a number chosen to hide it."
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
    # One sun and nothing else. `BG_COLOR` as well as the ambient, because a sky left in the
    # background is still a radiance map and still reflects off the patches.
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color.BLACK
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
    environment.ambient_light_energy = 0.0
    environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    environment.tonemap_exposure = LAB_EXPOSURE

    var patches: Node3D = Node3D.new()
    var places: Array[Vector3] = []
    var materials: Array[Material] = [
        _ours(0.0), _ours(1.0), _godot(0.0), _godot(1.0),
    ]
    for index: int in materials.size():
        var at: Vector3 = Vector3(
            (-0.5 + float(index % 2)) * 2.0 * PATCH_SPACING,
            PATCH_HEIGHT,
            (-0.5 + float(index / 2)) * 2.0 * PATCH_SPACING
        )
        places.append(at)
        patches.add_child(_patch(at, materials[index]))
    harness.world.add_child(patches)

    var shot: Dictionary = await harness.capture_shot("clearcoat/patches", "static", CONVERGE)
    if (shot["error"] as String) != "":
        return fail(shot["error"] as String)
    var image: Image = Image.load_from_file(shot["png"] as String)
    if image == null:
        return fail("the capture at %s could not be read" % shot["png"])

    var read: PackedFloat32Array = PackedFloat32Array()
    var reported: PackedStringArray = PackedStringArray()
    for index: int in places.size():
        var value: float = _at(harness, image, places[index])
        read.append(value)
        reported.append("%s %.4f" % [NAMES[index], value])
    for value: float in read:
        if value < USABLE.x or value > USABLE.y:
            return fail(
                "a patch photographed outside the %.2f to %.2f the measurement needs (%s):"
                % [USABLE.x, USABLE.y, ", ".join(reported)]
                + " the exposure, not the coat, is what this frame is measuring. %s"
                % shot["png"],
                value
            )

    # Fresnel at normal incidence, from the index of refraction alone.
    var reflected: float = pow((1.0 - CLEARCOAT_IOR) / (1.0 + CLEARCOAT_IOR), 2.0)
    var expected: float = 1.0 - reflected
    var ours: float = read[1] / maxf(read[0], 0.000001)
    var godots: float = read[3] / maxf(read[2], 0.000001)
    if absf(ours - expected) > TOLERANCE:
        return fail(
            "a fully coated patch keeps %.4f of its bare self where a film at IOR %.1f accounts"
            % [ours, CLEARCOAT_IOR]
            + " for %.4f: the coat is not layering over the paint, it is replacing it (%s). %s"
            % [expected, ", ".join(reported), shot["png"]],
            ours
        )
    # The control. Godot's coat has to be outside the bound, or this gate is not measuring the
    # difference it claims to.
    if absf(godots - expected) <= TOLERANCE + CONTROL_MARGIN:
        return fail(
            "Godot's own clearcoat keeps %.4f against the %.4f a film accounts for, inside this"
            % [godots, expected]
            + " gate's own bound: either the engine now layers its coat and this shader has"
            + " nothing left to prove, or the frame is not measuring the coat at all. %s"
            % shot["png"],
            godots
        )
    return ok(
        "a full coat keeps %.4f of the paint against %.4f from Fresnel at IOR %.1f; Godot's own"
        % [ours, expected, CLEARCOAT_IOR]
        + " keeps %.4f, which is the control. Uncoated, this shader reads %.4f against the"
        % [godots, read[0]]
        + " engine's %.4f on the same patch" % read[2],
        ours
    )


func _environment(harness: Node) -> Environment:
    var holder: WorldEnvironment = (
        harness.world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    )
    return null if holder == null else holder.environment


## One flat patch, face up, so the camera overhead sees it at normal incidence.
func _patch(at: Vector3, material: Material) -> MeshInstance3D:
    var quad: MeshInstance3D = MeshInstance3D.new()
    var plane: PlaneMesh = PlaneMesh.new()
    plane.size = Vector2(PATCH_SIZE, PATCH_SIZE)
    quad.mesh = plane
    quad.position = at
    quad.material_override = material
    return quad


func _ours(coverage: float) -> ShaderMaterial:
    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = load(VehiclePaint.SHADER_PATH) as Shader
    material.set_shader_parameter("albedo", PATCH_ALBEDO)
    material.set_shader_parameter("metallic", 0.0)
    material.set_shader_parameter("roughness", float(
        (MaterialCfg.CLASSES["car_paint"] as Dictionary)["roughness"]
    ))
    material.set_shader_parameter("clearcoat", coverage)
    material.set_shader_parameter("clearcoat_roughness", MaterialCfg.CLEARCOAT_ROUGHNESS)
    material.set_shader_parameter("sheen", 0.0)
    return material


func _godot(coverage: float) -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = PATCH_ALBEDO
    material.metallic = 0.0
    material.roughness = float((MaterialCfg.CLASSES["car_paint"] as Dictionary)["roughness"])
    if coverage > 0.0:
        material.clearcoat_enabled = true
        material.clearcoat = coverage
        material.clearcoat_roughness = MaterialCfg.CLEARCOAT_ROUGHNESS
    return material


## The patch's own luminance, in light rather than in what the file encodes.
func _at(harness: Node, image: Image, at: Vector3) -> float:
    var where: Vector2 = harness.camera.unproject_position(at)
    var size: Vector2i = image.get_size()
    var viewport: Vector2 = harness.render_viewport().get_visible_rect().size
    var x: int = clampi(int(where.x / viewport.x * float(size.x)), 0, size.x - 1)
    var y: int = clampi(int(where.y / viewport.y * float(size.y)), 0, size.y - 1)
    # A small mean rather than one pixel: a patch is flat, and anti-aliasing is not.
    var total: float = 0.0
    var counted: int = 0
    for dy: int in range(-4, 5, 2):
        for dx: int in range(-4, 5, 2):
            var colour: Color = image.get_pixel(
                clampi(x + dx, 0, size.x - 1), clampi(y + dy, 0, size.y - 1)
            )
            total += colour.srgb_to_linear().get_luminance()
            counted += 1
    return total / maxf(float(counted), 1.0)
