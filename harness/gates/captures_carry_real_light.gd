extends GateBase
## A capture carries light, not display pixels: linear, and unclipped above white.
##
## This is an instrument calibration, and it exists because the instrument was wrong for the
## whole life of the project without anybody noticing. Every measurement of light here is read
## back out of a capture, and a capture was an 8-bit PNG — display-encoded and clipped at white.
## A ratio taken from one is not a ratio of light, and it cannot be corrected afterwards because
## the error is not a constant: the bright end saturates and the dark end quantises.
##
## It was found by accident. Turning on physical light units let the exposure move, and
## `daylight_shadows_are_readable`'s "scene-referred" sun-to-sky ratio moved with it — 1.3:1 at
## ISO 100, 3.4:1 at 25, 12.2:1 at 12, 38.6:1 at 6, on one unchanged scene. **A gain cannot
## change a ratio.** Every sun-to-sky figure this project ever recorded came from that
## measurement.
##
## So the claim here is about the capture path and nothing else: a surface of known linear value
## arrives at that value. The value is injected through a shader uniform straight into `ALBEDO`,
## unshaded, because `StandardMaterial3D.albedo_color` is treated as sRGB and converted on the
## way in — asking it for 4.0 puts 25.3 on screen, which is a real measurement of the wrong
## thing. Nothing lights the quad, so no lighting model, tonemapper or exposure stands between
## the number set and the number read.

const PRESET: String = "diag_origin"
const CONVERGE: int = 3
## The levels to inject. Two below white, two above — the two above are the point, because an
## 8-bit capture cannot represent them at all and reads both as 1.0.
const LEVELS: Array[float] = [0.25, 0.75, 2.0, 8.0]
## How far a captured value may sit from the value injected, as a share of it. The target is a
## 16-bit half float, so a few parts in a thousand is the format's own resolution.
const TOLERANCE: float = 0.01
## Half the side of the sampled window, in pixels, centred on the quad.
const WINDOW_PX: int = 12


static func meta() -> Dictionary:
    return {
        "name": "captures_carry_real_light",
        "proves": "a captured frame reports linear scene values, unclipped above white, so a measurement taken from one is a measurement of light",
        "builds_on": ["smoke"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "levels %s read back within %.0f%%, including the ones above 1.0"
            % [LEVELS, TOLERANCE * 100.0]
        ),
        "why": (
            "every measurement of light in this project is read out of a capture, and a capture"
            + " was an 8-bit display-encoded PNG. That clips at white and quantises in shadow, so"
            + " a ratio taken from one is not a ratio of light — which is why the same scene"
            + " reported sun-to-sky as 1.3:1 and as 38.6:1 depending only on the exposure. An"
            + " instrument has to be calibrated before anything measured with it means anything."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)
    harness.use_measurement_environment()
    for child: Node in harness.world.get_children():
        if child is MeshInstance3D:
            (child as MeshInstance3D).visible = false

    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = load("res://game/shaders/flat_level.gdshader") as Shader
    var quad: MeshInstance3D = _build_quad(material)
    harness.world.add_child(quad)
    harness.camera.look_at_from_position(Vector3(0.0, 0.0, 4.0), Vector3.ZERO, Vector3.UP)

    var reported: PackedStringArray = PackedStringArray()
    var worst: float = 0.0
    var worst_level: float = 0.0
    for level: float in LEVELS:
        material.set_shader_parameter("level", level)
        var shot: Dictionary = await harness.capture_hdr(
            "hdr/level_%s" % String.num(level, 2), "static", CONVERGE
        )
        if (shot["error"] as String) != "":
            return fail(shot["error"] as String)
        var image: Image = shot["image"] as Image
        if image == null:
            return fail("the HDR capture produced no image at level %.2f" % level)
        var read: float = _window(image)
        var off: float = absf(read - level) / maxf(level, 0.0001)
        if off > worst:
            worst = off
            worst_level = level
        reported.append("%.2f read %.4f" % [level, read])
    quad.queue_free()

    if worst > TOLERANCE:
        return fail(
            "level %.2f read back %.1f%% out (%s): the capture is not carrying linear light."
            % [worst_level, worst * 100.0, ", ".join(reported)]
            + " A value above 1.0 reading as 1.0 means the target is still 8-bit.",
            worst
        )
    return ok(
        "%d levels read back within %.2f%%: %s" % [LEVELS.size(), worst * 100.0, ", ".join(reported)],
        worst
    )


## The mean of a small window at the centre of the frame, which the quad fills.
func _window(image: Image) -> float:
    var centre: Vector2i = image.get_size() / 2
    var total: float = 0.0
    var counted: int = 0
    for y: int in range(centre.y - WINDOW_PX, centre.y + WINDOW_PX):
        for x: int in range(centre.x - WINDOW_PX, centre.x + WINDOW_PX):
            total += image.get_pixel(x, y).r
            counted += 1
    return total / float(maxi(counted, 1))


func _build_quad(material: ShaderMaterial) -> MeshInstance3D:
    var plane: PlaneMesh = PlaneMesh.new()
    plane.size = Vector2(20.0, 20.0)
    plane.orientation = PlaneMesh.FACE_Z
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = "LevelQuad"
    instance.mesh = plane
    instance.material_override = material
    return instance
