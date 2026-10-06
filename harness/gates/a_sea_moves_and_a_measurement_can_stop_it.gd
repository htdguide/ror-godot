extends GateBase
## The sea's surface moves, and a measurement can hold it exactly still.
##
## Both halves are the claim, and the second is the one that costs something. A surface animated
## from the wall clock is a different surface in every frame anything photographs, so every gate
## that looks at water measures the moment it happened to run — which is how the vegetation's sway
## came to disagree with itself across one session, recorded in `foliage.gdshader`. The sea takes a
## phase the same way: negative follows the clock, which is what a window wants, and a number holds
## the surface where that number puts it.
##
## So: one scene, photographed twice at the same stated phase, has to come back identical to the
## pixel. Photographed at two different phases it has to come back different, or the phase is a
## uniform nothing reads and the sea is a still picture that only looks animated because the camera
## was moving.

const PRESET: String = "diag_topdown"
const WEATHER: String = "noon_clear"
const CONVERGE: int = 6
## The sea sits above the stage's own floor, so the ripples have a chequerboard to bend.
const SEA_Y: float = 1.0
const SEA_M: float = 60.0
## Two phases far enough apart that the surface has moved, in the shader's own units.
const PHASES: Array[float] = [3.0, 11.0]
## How far a pixel may move between two captures at the same phase. One level of an 8-bit channel
## is 0.0039, and the claim is that nothing moves at all.
const STILL: float = 0.004
## How much of the frame has to change between the two phases, and by how much, for the surface to
## have moved rather than drifted.
const MOVED_SHARE: float = 0.02
const MOVED_BY: float = 0.02


static func meta() -> Dictionary:
    return {
        "name": "a_sea_moves_and_a_measurement_can_stop_it",
        "proves": "the sea's surface moves with its stated phase, and two captures at one phase are identical to the pixel",
        "builds_on": ["a_terrain_has_the_water_its_file_declares"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "nothing over %.4f between two captures at one phase, and %.0f%% of the frame over"
            % [STILL, MOVED_SHARE * 100.0] + " %.2f between two phases" % MOVED_BY
        ),
        "why": (
            "a surface that animates from the wall clock is a different surface every time it is"
            + " photographed, so every later measurement of water would be of the moment it"
            + " happened to run. The vegetation's sway was exactly this and disagreed with itself"
            + " across one session once the suite stopped giving every gate its own process."
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
    var sea: MeshInstance3D = _sea()
    harness.world.add_child(sea)
    var material: ShaderMaterial = sea.material_override as ShaderMaterial

    material.set_shader_parameter("wave_phase", PHASES[0])
    var first: Image = await _frame(harness, "still_a")
    if first == null:
        return fail("the sea did not render")
    var again: Image = await _frame(harness, "still_b")
    if again == null:
        return fail("the sea did not render a second time")
    var drift: float = _worst(first, again)
    if drift > STILL:
        return fail(
            "two captures of the same sea at phase %.1f differ by %.4f at worst, over the %.4f"
            % [PHASES[0], drift, STILL]
            + " a held surface allows: the sea is moving with something other than its phase",
            drift
        )

    material.set_shader_parameter("wave_phase", PHASES[1])
    var later: Image = await _frame(harness, "moved")
    if later == null:
        return fail("the sea did not render at its second phase")
    var moved: float = _share_over(first, later, MOVED_BY)
    if moved < MOVED_SHARE:
        return fail(
            "%.2f%% of the frame changed between phase %.1f and phase %.1f, under the %.0f%% a"
            % [moved * 100.0, PHASES[0], PHASES[1], MOVED_SHARE * 100.0]
            + " moving surface owes: the phase is a uniform nothing reads",
            moved
        )
    return ok(
        "held at phase %.1f two captures agree to %.4f; moved to phase %.1f, %.1f%% of the frame"
        % [PHASES[0], drift, PHASES[1], moved * 100.0] + " changed",
        moved
    )


## The sea, built the way `RorWater` builds one.
func _sea() -> MeshInstance3D:
    var sea: MeshInstance3D = MeshInstance3D.new()
    var plane: PlaneMesh = PlaneMesh.new()
    plane.size = Vector2(SEA_M, SEA_M)
    sea.mesh = plane
    sea.position = Vector3(0.0, SEA_Y, 0.0)
    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = load(RorWater.SHADER) as Shader
    material.render_priority = 1
    sea.material_override = material
    sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    return sea


func _frame(harness: Node, tag: String) -> Image:
    var shot: Dictionary = await harness.capture_shot("water/%s" % tag, "static", CONVERGE)
    if (shot["error"] as String) != "":
        return null
    return Image.load_from_file(shot["png"] as String)


## The worst a single pixel moved between two frames.
func _worst(before: Image, after: Image) -> float:
    var size: Vector2i = before.get_size()
    var worst: float = 0.0
    for y: int in range(0, size.y, 3):
        for x: int in range(0, size.x, 3):
            var a: Color = before.get_pixel(x, y)
            var b: Color = after.get_pixel(x, y)
            worst = maxf(
                worst, maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
            )
    return worst


## What share of the frame moved by more than `reach`.
func _share_over(before: Image, after: Image, reach: float) -> float:
    var size: Vector2i = before.get_size()
    var counted: int = 0
    var moved: int = 0
    for y: int in range(0, size.y, 3):
        for x: int in range(0, size.x, 3):
            var a: Color = before.get_pixel(x, y)
            var b: Color = after.get_pixel(x, y)
            counted += 1
            if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > reach:
                moved += 1
    return float(moved) / maxf(float(counted), 1.0)
