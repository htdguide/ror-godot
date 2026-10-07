extends GateBase
## A lookup table that maps every colour to itself changes no pixel of the frame.
##
## **The identity is the only entry in a LUT anybody can check by reasoning.** A grading table is a
## look — somebody's decision about how a picture should feel — and there is nothing to measure it
## against. The identity is different: a table whose every sample is its own coordinate must leave
## the frame exactly as it found it, and if it does not then the path is wrong in a way that will
## bend every other table hung on it. The usual causes are all invisible by eye: a cube sampled off
## by half a texel, a table decoded as sRGB when it holds display values, red and blue swapped,
## an edge clamped where it should wrap.
##
## That is why this is worth a gate and a non-neutral grade is not. A wrong look is a complaint; a
## wrong identity is a silent bias on every look the project ever ships.
##
## The subject is a wedge of known colours — greys to catch a gamma, primaries to catch a swapped
## or rotated channel — photographed with the table on and with the grade off entirely, and
## compared pixel for pixel.

const PRESET: String = "diag_topdown"
const WEATHER: String = "spike_black"
const CONVERGE: int = 4
const PATCH_M: float = 0.42
const PATCH_SPACING: float = 0.52
const WEDGE_AT: Vector3 = Vector3(0.0, 1.0, 0.0)
## Greys for the shape of the transfer, primaries and secondaries for the channels, and two
## off-axis mixes because a rotation about the grey axis leaves pure colours alone.
const COLOURS: Array[Color] = [
    Color(0.05, 0.05, 0.05), Color(0.25, 0.25, 0.25), Color(0.5, 0.5, 0.5),
    Color(0.75, 0.75, 0.75), Color(0.95, 0.95, 0.95),
    Color(0.8, 0.1, 0.1), Color(0.1, 0.8, 0.1), Color(0.1, 0.1, 0.8),
    Color(0.8, 0.8, 0.1), Color(0.1, 0.8, 0.8), Color(0.8, 0.1, 0.8),
    Color(0.7, 0.35, 0.15), Color(0.2, 0.45, 0.7),
]
## How far a patch may move, per channel, in display values. An 8-bit frame steps by 0.0039, and a
## table the hardware interpolates across 32 samples lands between two of them, so one step is the
## honest floor and this is a little over it.
const TOLERANCE: float = 0.006


static func meta() -> Dictionary:
    return {
        "name": "a_neutral_grade_changes_nothing",
        "proves": "a colour-correction cube whose every sample is its own coordinate leaves every patch of a known wedge where it was, so the grading path neither shifts nor rotates nor re-gammas what passes through it",
        "builds_on": ["tonemap_and_exposure"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "every patch within %.4f per channel of its ungraded self" % TOLERANCE,
        "why": (
            "a grading table is a look and has nothing to be measured against, but the identity"
            + " has exactly one correct answer. Every way of sampling a cube wrongly — half a"
            + " texel out, decoded in the wrong colour space, channels transposed — survives the"
            + " eye and then bends every look the project ships through it."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M2b",
    }


func run(harness: Node) -> Dictionary:
    var err: String = harness.setup_for(PRESET, WEATHER)
    if err != "":
        return fail(err)
    clear_fog(harness)
    var holder: WorldEnvironment = (
        harness.world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    )
    if holder == null or holder.environment == null:
        return fail("the world has no environment to grade")
    var environment: Environment = holder.environment
    environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    environment.tonemap_exposure = 1.0
    environment.glow_enabled = false
    var ground: Node3D = harness.world.get_node_or_null(^"Ground") as Node3D
    if ground != null:
        ground.visible = false

    var places: Array[Vector3] = []
    for index: int in COLOURS.size():
        places.append(_place(index))
        harness.world.add_child(_patch(places[index], COLOURS[index]))

    environment.adjustment_enabled = false
    environment.adjustment_color_correction = null
    var plain: Array[Color] = await _read(harness, "ungraded", places)
    if plain.is_empty():
        return fail("the wedge did not render")

    environment.adjustment_enabled = true
    environment.adjustment_brightness = 1.0
    environment.adjustment_contrast = 1.0
    environment.adjustment_saturation = 1.0
    environment.adjustment_color_correction = ColourGrade.identity_cube()
    var graded: Array[Color] = await _read(harness, "identity", places)
    if graded.is_empty():
        return fail("the wedge did not render through the table")

    var worst: float = 0.0
    var worst_said: String = ""
    for index: int in COLOURS.size():
        for channel: int in 3:
            var moved: float = absf(graded[index][channel] - plain[index][channel])
            if moved > worst:
                worst = moved
                worst_said = (
                    "the %s patch moved its %s channel from %.4f to %.4f"
                    % [
                        _named(COLOURS[index]), ["red", "green", "blue"][channel],
                        plain[index][channel], graded[index][channel]
                    ]
                )
    if worst > TOLERANCE:
        return fail(
            "%s — %.4f, over the %.4f an identity may move anything. The grading path is not"
            % [worst_said, worst, TOLERANCE] + " neutral, so no table hung on it means what it says",
            worst
        )
    return ok(
        "%d patches through a %d-sample identity cube: worst channel moved %.4f"
        % [COLOURS.size(), ColourGrade.CUBE, worst],
        worst
    )


func _named(colour: Color) -> String:
    if absf(colour.r - colour.g) < 0.001 and absf(colour.g - colour.b) < 0.001:
        return "%.0f%% grey" % (colour.r * 100.0)
    return "(%.2f, %.2f, %.2f)" % [colour.r, colour.g, colour.b]


func _place(index: int) -> Vector3:
    var across: int = 5
    return WEDGE_AT + Vector3(
        (float(index % across) - float(across - 1) * 0.5) * PATCH_SPACING,
        0.0,
        (float(index / across) - 1.0) * PATCH_SPACING
    )


## One flat patch of a stated colour, unshaded so that what reaches the grade is what was chosen.
func _patch(at: Vector3, colour: Color) -> MeshInstance3D:
    var patch: MeshInstance3D = MeshInstance3D.new()
    var plane: PlaneMesh = PlaneMesh.new()
    plane.size = Vector2(PATCH_M, PATCH_M)
    patch.mesh = plane
    var flat: StandardMaterial3D = StandardMaterial3D.new()
    flat.albedo_color = colour
    flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    patch.material_override = flat
    patch.position = at
    return patch


func _read(harness: Node, tag: String, places: Array[Vector3]) -> Array[Color]:
    var out: Array[Color] = []
    var shot: Dictionary = await harness.capture_shot("grade/%s" % tag, "static", CONVERGE)
    if (shot["error"] as String) != "":
        return out
    var image: Image = Image.load_from_file(shot["png"] as String)
    if image == null:
        return out
    var size: Vector2i = image.get_size()
    var viewport: Vector2 = harness.render_viewport().get_visible_rect().size
    for at: Vector3 in places:
        var where: Vector2 = harness.camera.unproject_position(at)
        var x: int = clampi(int(where.x / viewport.x * float(size.x)), 0, size.x - 1)
        var y: int = clampi(int(where.y / viewport.y * float(size.y)), 0, size.y - 1)
        var total: Color = Color(0.0, 0.0, 0.0)
        var counted: int = 0
        for dy: int in range(-8, 9, 4):
            for dx: int in range(-8, 9, 4):
                var pixel: Color = image.get_pixel(
                    clampi(x + dx, 0, size.x - 1), clampi(y + dy, 0, size.y - 1)
                )
                total += pixel
                counted += 1
        out.append(total / maxf(float(counted), 1.0))
    return out
