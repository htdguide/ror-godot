extends GateBase
## How much of a scene's light comes from the sky does not depend on the film in the camera.
##
## **Under physical light units the sky was exposed twice and the sun once.** Godot hands a sky
## shader a light energy that already carries the camera's exposure, renders what comes back into
## a radiance map, and applies the exposure again when it lights the scene with it. So a surface
## lit only by the sky brightened four times for twice the ISO while a surface lit by the sun
## brightened twice, and the whole sunlit-to-skylit balance of the project moved with the film:
## 19.2:1 at ISO 16, 6.4:1 at 32, 2.7:1 at 64, 1.6:1 at 128, on one unchanged scene with a capture
## proven linear. `daylight_shadows_are_readable` recorded that as something it could not explain
## and would not grade against; this is the claim that fixes it.
##
## Both halves are divided out in `sky_clouds.gdshader` — the light the clouds and the disc are
## given, and the cube-map pass the scene is lit from. What is left is one exposure, applied by the
## renderer, to the sky and the sun alike.
##
## **The sky here is this project's own.** Godot's `PhysicalSkyMaterial` cannot hold this claim and
## is not asked to: it is a Preetham model with a tone curve on the end, and the curve is applied
## to the sun's own energy — measured at a fixed exposure, doubling the sun's lux brightened that
## sky by 1.54 rather than by 2, four times running, a response of `light ^ 0.625`. No multiplier
## outside a power can undo it. M2's HDRI sky is what replaces it.

const PRESET: String = "diag_origin"
const SKY_OF: String = "noon_clear"
const SETTLE_FRAMES: int = 3
## The films this one scene is photographed on. Three stops, around the project's own ISO 32.
const ISOS: Array[float] = [16.0, 32.0, 64.0, 128.0]
## A mid-grey surface, square on to the sun, as `daylight_shadows_are_readable` measures it.
const ALBEDO: Color = Color(0.35, 0.35, 0.35)
const QUAD_SIZE: float = 6.0
const SUN_ON: Vector3 = Vector3(0.55, 0.78, 0.62)
## How far any one film's ratio may sit from the middle one. A tenth is far wider than the
## renderer's own spread — measured at 4.3% worst, and that worst is the darkest film, where the
## skylit sample is four thousandths of a unit — and it is a twentieth of what the fault produced:
## 19.2:1 against 1.6:1 is a factor of twelve, not a tenth.
const MOST_IT_MAY_DRIFT: float = 0.10
## Under this the skylit sample is too dark to divide anything by.
const MIN_SKYLIT: float = 0.001


static func meta() -> Dictionary:
    return {
        "name": "the_sky_does_not_follow_the_camera",
        "proves": "the share of a scene's light that comes from the sky is the same on every film, so the sunlit-to-skylit balance is a property of the scene rather than of the exposure",
        "builds_on": ["daylight_shadows_are_readable"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "the sunlit-to-skylit ratio within %.0f%% of its median across %d films three stops"
            % [MOST_IT_MAY_DRIFT * 100.0, ISOS.size()] + " apart"
        ),
        "why": (
            "Godot exposes a sky's light twice and a lamp's once, so the project's whole"
            + " sun-to-sky balance was a property of the camera: 19.2:1 at ISO 16 and 1.6:1 at"
            + " 128 on one unchanged scene. A lighting balance that moves with the film cannot be"
            + " graded against, and every figure measured through one is worth nothing."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)
    clear_fog(harness)
    var holder: WorldEnvironment = harness.world.get_node_or_null(
        ^"WorldEnvironment"
    ) as WorldEnvironment
    if holder == null or holder.environment == null or holder.environment.sky == null:
        return fail("the world has no sky to photograph")
    var environment: Environment = holder.environment
    # Scene-referred, through an HDR capture: a ratio read off a display-encoded PNG is a ratio of
    # neither light nor anything else. See `captures_carry_real_light`.
    environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    environment.tonemap_exposure = 1.0
    environment.sky.sky_material = SkyClouds.material(WeatherCfg.get_preset(SKY_OF))
    var sun: DirectionalLight3D = harness.world.get_node_or_null(^"Sun") as DirectionalLight3D
    if sun == null:
        return fail("the world has no sun to take away")
    for child: Node in harness.world.get_children():
        if child is MeshInstance3D:
            (child as MeshInstance3D).visible = false
    var quad: MeshInstance3D = _quad()
    harness.world.add_child(quad)
    harness.camera.look_at_from_position(
        SUN_ON.normalized() * QUAD_SIZE * 1.6, Vector3.ZERO, Vector3.UP
    )
    var attributes: CameraAttributesPhysical = harness.camera.attributes
    if attributes == null:
        return fail("the camera is not a physical one, so it has no film to change")

    var ratios: Array[float] = []
    var reported: PackedStringArray = PackedStringArray()
    for iso: float in ISOS:
        attributes.exposure_sensitivity = iso
        # The sky is built from the hour and the hour states its exposure, so a camera moved
        # afterwards has to say so. See `WorldSky.reexpose`.
        WorldSky.reexpose(harness.world, harness.camera)
        sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
        var lit: float = await _sample(harness, "iso%d_lit" % int(iso))
        # `SKY_ONLY` leaves the atmosphere exactly as it was and removes only the direct light,
        # which is the difference between a surface in shadow and a surface at night.
        sun.sky_mode = DirectionalLight3D.SKY_MODE_SKY_ONLY
        var skylit: float = await _sample(harness, "iso%d_sky" % int(iso))
        if skylit < MIN_SKYLIT:
            return fail(
                "at ISO %d the skylit sample is %.5f, too dark to measure a ratio with"
                % [int(iso), skylit], skylit
            )
        ratios.append(lit / skylit)
        reported.append("ISO %d %.3f:1" % [int(iso), lit / skylit])
    quad.queue_free()

    var middle: float = _median(ratios)
    var worst: float = 0.0
    var worst_at: int = 0
    for at: int in ratios.size():
        var drift: float = absf(ratios[at] - middle) / middle
        if drift > worst:
            worst = drift
            worst_at = at
    if worst > MOST_IT_MAY_DRIFT:
        return fail(
            "the sunlit-to-skylit ratio is %.3f:1 at ISO %d against a median of %.3f:1, which is"
            % [ratios[worst_at], int(ISOS[worst_at]), middle]
            + " %.1f%% away and over the %.0f%% allowed: the sky is following the camera"
            % [worst * 100.0, MOST_IT_MAY_DRIFT * 100.0],
            worst
        )
    return ok(
        "%s: a median of %.3f:1, worst film %.1f%% from it"
        % [", ".join(reported), middle, worst * 100.0],
        worst
    )


func _median(values: Array[float]) -> float:
    var sorted: Array[float] = values.duplicate()
    sorted.sort()
    var middle: int = sorted.size() / 2
    if sorted.size() % 2 == 1:
        return sorted[middle]
    return (sorted[middle - 1] + sorted[middle]) * 0.5


## The quad's mean luminance, as linear light.
func _sample(harness: Node, name: String) -> float:
    var shot: Dictionary = await harness.capture_hdr(
        "sky_exposure/%s" % name, "static", SETTLE_FRAMES
    )
    if (shot["error"] as String) != "":
        return -1.0
    var image: Image = shot["image"] as Image
    if image == null:
        return -1.0
    var size: Vector2i = image.get_size()
    var total: float = 0.0
    var counted: int = 0
    for y: int in range(size.y / 3, size.y * 2 / 3):
        for x: int in range(size.x / 3, size.x * 2 / 3):
            var colour: Color = image.get_pixel(x, y)
            total += colour.r * 0.2126 + colour.g * 0.7152 + colour.b * 0.0722
            counted += 1
    return total / float(counted)


## A mid-grey card facing the sun. Square on, because a surface at a glancing angle measures the
## angle as much as the light.
func _quad() -> MeshInstance3D:
    var plane: PlaneMesh = PlaneMesh.new()
    plane.size = Vector2(QUAD_SIZE, QUAD_SIZE)
    plane.orientation = PlaneMesh.FACE_Y
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = ALBEDO
    material.roughness = 1.0
    material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = "SkyExposureQuad"
    instance.mesh = plane
    instance.material_override = material
    var toward: Vector3 = SUN_ON.normalized()
    instance.basis = Basis(
        toward.cross(Vector3.UP).normalized(),
        toward,
        toward.cross(toward.cross(Vector3.UP).normalized()).normalized()
    )
    return instance
