extends GateBase
## A surface the sun cannot reach is still lit by the sky, and still readable after grading.
##
## Every view of the valley has a shaded wall in it, and four of the seven in
## `tools/valley_shots.sh` came out nearly black. That can be two quite different faults and the
## difference matters: either the sky is not lighting the shaded side at all — a lighting bug — or
## it is, and the tonemapper and exposure are burying what it gives — a grading choice. So both
## are measured, on the same surface, in one run.
##
## The subject is one quad of neutral albedo, captured twice: once with the sun on it and once
## with the sun behind it, so the only thing that changes between the two is whether direct light
## reaches the surface. Nothing about the valley enters, which is deliberate — this is about the
## light, and a terrain would bring its own albedo, its own normals and its own shadow map.
##
## The bound on the ratio is a sanity range rather than a physical claim, and the reason is worth
## recording. Clear-sky daylight is measured physics: a surface facing a midday sun receives about
## 100 klx of direct light plus 15–20 klx of skylight, and the same surface turned away receives
## only skylight — call it 8 klx. That is roughly 14:1. This scene measures about 4:1, so its sky
## is some three times stronger than daylight's relative to its sun. Correcting that belongs with
## M2's HDRI sky, where the balance comes from the captured environment instead of from stated
## colours, and doing it here would darken every shadow in the project to fix a number. So the
## range below is wide: what it is for is catching a sky that contributes nothing, or a sun that
## does, either of which is a bug rather than a grade.
##
## The displayed value is the claim with teeth: whatever the ratio, the shaded side has to survive
## the grading as something a person can see detail in.

const PRESET: String = "diag_origin"
const SETTLE_FRAMES: int = 3
## A mid-grey surface: dark enough not to clip in sun, bright enough to read in shade.
const ALBEDO: Color = Color(0.35, 0.35, 0.35)
const QUAD_SIZE: float = 6.0
## Where the sun sits when it is on the quad, and the same direction mirrored for when it is
## behind it. Matches the noon preset, and the quad is turned to face it: a surface at a glancing
## angle to the sun measures the angle as much as the light, and the physical numbers this is read
## against are for a surface facing the sun square on.
const SUN_ON: Vector3 = Vector3(0.55, 0.78, 0.62)

## The physical band, from clear-sky daylight measurements. Generously wide: what it is there to
## catch is a sky contributing nothing, which reads in the hundreds.
const MIN_SUN_TO_SKY: float = 1.5
const MAX_SUN_TO_SKY: float = 40.0
## What the shaded side has to display at, after the project's tonemapper and exposure. Below this
## a surface is a silhouette: 0.05 is about where an 8-bit sRGB image stops holding usable detail
## in shadow, and the valley's walls were rendering at 0.02.
const MIN_SHADED_LUMA: float = 0.05
## And the sunlit side may not be so bright that there is nothing left in it.
const MAX_SUNLIT_LUMA: float = 0.92


static func meta() -> Dictionary:
    return {
        "name": "daylight_shadows_are_readable",
        "proves": "the sky lights a surface the sun cannot reach, the sun and the sky both contribute, and the grading keeps the shaded surface readable",
        # four captures of a lit scene, which is the harness rendering and capturing.
        "builds_on": ["smoke"],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "scene-referred sunlit:shaded between %.1f:1 and %.0f:1; shaded surface at least"
            % [MIN_SUN_TO_SKY, MAX_SUN_TO_SKY]
            + " %.2f display luma and sunlit at most %.2f" % [MIN_SHADED_LUMA, MAX_SUNLIT_LUMA]
        ),
        "why": (
            "a valley is half shaded wall in every view, and 'too dark to see' has two causes"
            + " that want opposite fixes: a sky that is not lighting the shaded side, or a"
            + " grading that buries what it does light. The ratio separates them; the displayed"
            + " value is measured against what an 8-bit image can still hold detail in. The"
            + " ratio's own range is deliberately wide — see the note in this gate about the"
            + " scene's sun-to-sky balance and M2's HDRI sky."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M2b",
    }


func run(harness: Node) -> Dictionary:
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)
    clear_fog(harness)
    var environment: Environment = _environment(harness)
    if environment == null:
        return fail("the world has no environment to configure")
    var sun: DirectionalLight3D = harness.world.get_node_or_null(^"Sun") as DirectionalLight3D
    if sun == null:
        return fail("the world has no sun to move")
    _hide_props(harness)

    var quad: MeshInstance3D = _build_quad()
    harness.world.add_child(quad)
    harness.camera.look_at_from_position(
        SUN_ON.normalized() * QUAD_SIZE * 1.6, Vector3.ZERO, Vector3.UP
    )

    # Scene-referred first: linear tonemapping at unit exposure, so what is measured is the light
    # itself rather than the grade laid over it.
    var tonemap: int = environment.tonemap_mode
    var exposure: float = environment.tonemap_exposure
    environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    environment.tonemap_exposure = 1.0
    var lit_scene: float = await _sample(harness, sun, SUN_ON, "linear_sunlit")
    var shaded_scene: float = await _sample(harness, sun, -SUN_ON, "linear_shaded")

    # Then as the project actually grades it.
    environment.tonemap_mode = tonemap as Environment.ToneMapper
    environment.tonemap_exposure = exposure
    var lit_display: float = await _sample(harness, sun, SUN_ON, "graded_sunlit")
    var shaded_display: float = await _sample(harness, sun, -SUN_ON, "graded_shaded")
    quad.queue_free()

    if shaded_scene <= 0.0:
        return fail(
            "the shaded surface receives no light at all: the sky is not lighting the scene",
            shaded_scene
        )
    var ratio: float = lit_scene / shaded_scene
    if ratio < MIN_SUN_TO_SKY or ratio > MAX_SUN_TO_SKY:
        return fail(
            "sunlit %.4f against shaded %.4f is %.1f:1, outside the %.0f:1 to %.0f:1 of"
            % [lit_scene, shaded_scene, ratio, MIN_SUN_TO_SKY, MAX_SUN_TO_SKY]
            + " clear-sky daylight: the sky's share of the lighting is wrong",
            ratio
        )
    if shaded_display < MIN_SHADED_LUMA:
        return fail(
            "the shaded surface displays at %.4f, under %.2f: the light is there (%.1f:1 scene"
            % [shaded_display, MIN_SHADED_LUMA, ratio]
            + " ratio) and the grading is burying it",
            shaded_display
        )
    if lit_display > MAX_SUNLIT_LUMA:
        return fail(
            "the sunlit surface displays at %.4f, over %.2f: there is nothing left in it"
            % [lit_display, MAX_SUNLIT_LUMA],
            lit_display
        )
    return ok(
        "sunlit %.4f against shaded %.4f scene-referred, %.1f:1; displayed %.3f and %.3f"
        % [lit_scene, shaded_scene, ratio, lit_display, shaded_display],
        shaded_display
    )


## Puts the sun in a direction and measures the quad's mean luma.
func _sample(
    harness: Node, sun: DirectionalLight3D, toward: Vector3, name: String
) -> float:
    sun.look_at_from_position(Vector3.ZERO, -toward.normalized(), Vector3.UP)
    var shot: Dictionary = await harness.capture_shot("daylight/%s" % name, "static", SETTLE_FRAMES)
    if (shot["error"] as String) != "":
        return -1.0
    var image: Image = Image.load_from_file(shot["png"] as String)
    if image == null:
        return -1.0
    # The middle of the frame, which the quad fills: sampling the whole frame would average the
    # sky in and the sky does not change between the two captures the way the quad does.
    var size: Vector2i = image.get_size()
    var total: float = 0.0
    var counted: int = 0
    for y: int in range(size.y / 3, size.y * 2 / 3):
        for x: int in range(size.x / 3, size.x * 2 / 3):
            var colour: Color = image.get_pixel(x, y)
            total += colour.r * 0.2126 + colour.g * 0.7152 + colour.b * 0.0722
            counted += 1
    return total / float(counted)


func _build_quad() -> MeshInstance3D:
    var plane: PlaneMesh = PlaneMesh.new()
    plane.size = Vector2(QUAD_SIZE, QUAD_SIZE)
    # A plane faces up, and up is turned to face the sun: the measurement wants a surface square
    # to the light, not one reading its own angle to it.
    plane.orientation = PlaneMesh.FACE_Y
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = ALBEDO
    material.roughness = 1.0
    material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = "DaylightQuad"
    instance.mesh = plane
    instance.material_override = material
    var toward: Vector3 = SUN_ON.normalized()
    instance.basis = Basis(
        toward.cross(Vector3.UP).normalized(),
        toward,
        toward.cross(toward.cross(Vector3.UP).normalized()).normalized()
    )
    return instance


## The blockout world's scale props would otherwise stand between the camera and the quad.
func _hide_props(harness: Node) -> void:
    for child: Node in harness.world.get_children():
        if child is MeshInstance3D and child.name != "DaylightQuad":
            (child as MeshInstance3D).visible = false


func _environment(harness: Node) -> Environment:
    var holder: WorldEnvironment = harness.world.get_node_or_null(
        ^"WorldEnvironment"
    ) as WorldEnvironment
    return holder.environment if holder != null else null
