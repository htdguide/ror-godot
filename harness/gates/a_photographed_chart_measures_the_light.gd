extends GateBase
## A step wedge, photographed under controlled lights, measures what a photographer would measure.
##
## This project has twice built a measurement of light on an instrument nobody had calibrated,
## and twice been confidently wrong about the result. Photographers solved this a century ago and
## the method is worth copying literally:
##
## - **A step wedge**, not one grey card. Patches a stop apart around 18% tell you whether the
##   response is linear across the range; one patch tells you nothing about the shape.
## - **Bracket the exposure.** A linear sensor's values scale exactly with it. Anything that does
##   not scale is not the light.
## - **Meter each light on its own.** A lighting ratio is key alone against fill alone, measured
##   separately at the subject. Measuring "both lights" against "fill" couples the two and is
##   what made the sun-to-sky question so slippery: the sky scatters the sun, so the two could
##   never be separated by turning one down.
##
## The chart is lit in a darkroom — `use_measurement_environment` leaves no ambient and a black
## background — so the key and the fill are the only light in the scene. That is the point: it
## separates "is the lighting path linear" from "does the sky behave", which were tangled
## together in every previous attempt.
##
## Reflectances are **injected**, not recited. A real ColorChecker comparison wants its published
## Lab values and a `THIRD_PARTY.md` entry; quoting 24 patches from memory would be the exact
## kind of self-written expectation this project refuses. Here the oracle is construction: the
## gate sets a reflectance and asserts the photograph is proportional to it.

const PRESET: String = "diag_origin"
const CONVERGE: int = 3
## A photographic step wedge: a stop between each patch, centred on an 18% grey card.
const WEDGE: Array[float] = [0.72, 0.36, 0.18, 0.09, 0.045, 0.0225]
const PATCH_SIZE: float = 0.9
const PATCH_GAP: float = 1.05
## The two lights, in lux, and the ratio between them is what the gate checks it can measure.
## Far enough from 1:1 to be unambiguous, and the fill is off to one side the way a fill is.
const KEY_LUX: float = 20000.0
const FILL_LUX: float = 5000.0
const KEY_FROM: Vector3 = Vector3(0.0, 0.0, 1.0)
const FILL_FROM: Vector3 = Vector3(-0.8, 0.2, 0.6)
## The chart faces the camera, so its normal is +Z.
const CHART_NORMAL: Vector3 = Vector3(0.0, 0.0, 1.0)
## 6500 K daylight, as a neutral: a white balance check wants a light that is actually white.
const LIGHT_COLOUR: Color = Color(1.0, 1.0, 1.0)
## How far a measurement may sit from what was configured, as a share of it.
const LINEARITY_TOLERANCE: float = 0.02
const BRACKET_TOLERANCE: float = 0.02
const RATIO_TOLERANCE: float = 0.05
## Half the side of the window sampled at each patch's centre, in pixels.
const WINDOW_PX: int = 10


static func meta() -> Dictionary:
    return {
        "name": "a_photographed_chart_measures_the_light",
        "proves": "a photographed step wedge is proportional to its reflectance, scales exactly with exposure, and reports the ratio between two lights that were metered separately",
        "builds_on": ["captures_carry_real_light"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "%d patches linear in reflectance within %.0f%%, every patch scaling within %.0f%%"
            % [WEDGE.size(), LINEARITY_TOLERANCE * 100.0, BRACKET_TOLERANCE * 100.0]
            + " across a one-stop bracket, and a key-to-fill of %.2f:1 measured within %.0f%%"
            % [_wanted_ratio(), RATIO_TOLERANCE * 100.0]
        ),
        "why": (
            "this project has twice built a measurement of light on an uncalibrated instrument"
            + " and been confidently wrong. A step wedge shows the shape of the response rather"
            + " than one point on it, a bracket proves the response is a gain, and metering each"
            + " light separately is the only way to get a lighting ratio out of a sun and a sky"
            + " that scatter into one another."
        ),
        "budget_s": 180.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)
    # A darkroom: no ambient, black background, linear tonemap at unit exposure. The key and the
    # fill are then the only light there is, which is what makes the ratio measurable at all.
    harness.use_measurement_environment()
    for child: Node in harness.world.get_children():
        if child is MeshInstance3D:
            (child as MeshInstance3D).visible = false
        var light: Light3D = child as Light3D
        if light != null:
            light.visible = false

    var patches: Array[MeshInstance3D] = _build_wedge()
    for patch: MeshInstance3D in patches:
        harness.world.add_child(patch)
    var key: DirectionalLight3D = _build_light("Key", KEY_FROM, KEY_LUX)
    var fill: DirectionalLight3D = _build_light("ChartFill", FILL_FROM, FILL_LUX)
    harness.world.add_child(key)
    harness.world.add_child(fill)

    var span: float = float(WEDGE.size() - 1) * PATCH_GAP
    harness.camera.look_at_from_position(
        Vector3(0.0, 0.0, span * 1.25), Vector3.ZERO, Vector3.UP
    )
    await harness.advance_frames(1, "static", "chart")
    var at: PackedVector2Array = PackedVector2Array()
    for index: int in WEDGE.size():
        at.append(harness.camera.unproject_position(_patch_position(index)))

    # Key alone, fill alone: metered separately, the way a lighting ratio is actually taken.
    fill.visible = false
    var key_only: PackedFloat32Array = await _photograph(harness, at, "chart/key")
    key.visible = false
    fill.visible = true
    var fill_only: PackedFloat32Array = await _photograph(harness, at, "chart/fill")
    key.visible = true

    # And a one-stop bracket on the key, which a linear response doubles exactly.
    fill.visible = false
    key.light_intensity_lux = KEY_LUX * 2.0
    var brighter: PackedFloat32Array = await _photograph(harness, at, "chart/bracket")
    key.light_intensity_lux = KEY_LUX

    if key_only.is_empty() or fill_only.is_empty() or brighter.is_empty():
        return fail("a photograph could not be taken; see the capture error above")

    # 1. Linear in reflectance: every patch divided by its own reflectance is the same number,
    #    which is the illuminance the wedge is standing in.
    var illuminance: PackedFloat32Array = PackedFloat32Array()
    for index: int in WEDGE.size():
        illuminance.append(key_only[index] / WEDGE[index])
    var worst_linear: float = _spread(illuminance)
    if worst_linear > LINEARITY_TOLERANCE:
        return fail(
            "the wedge is not linear in reflectance: patch-over-reflectance spreads %.1f%% (%s)"
            % [worst_linear * 100.0, _row(key_only)],
            worst_linear
        )

    # 2. A stop is a factor of two, on every patch.
    var worst_bracket: float = 0.0
    for index: int in WEDGE.size():
        if key_only[index] <= 0.0:
            return fail("patch %d photographed black under the key light" % index)
        worst_bracket = maxf(worst_bracket, absf(brighter[index] / key_only[index] - 2.0) / 2.0)
    if worst_bracket > BRACKET_TOLERANCE:
        return fail(
            "doubling the key moved a patch by %.1f%% away from a factor of two: the response is"
            % (worst_bracket * 100.0) + " not a gain, so nothing measured through it is light",
            worst_bracket
        )

    # 3. The lighting ratio, from two lights metered separately.
    var measured_ratio: float = _mean(key_only) / maxf(_mean(fill_only), 0.000001)
    var wanted: float = _wanted_ratio()
    var ratio_error: float = absf(measured_ratio - wanted) / wanted
    if ratio_error > RATIO_TOLERANCE:
        return fail(
            "the lights are %.0f lx and %.0f lx at %.2f and %.2f cosine, so %.2f:1 reaches the"
            % [KEY_LUX, FILL_LUX, KEY_FROM.normalized().dot(CHART_NORMAL),
               FILL_FROM.normalized().dot(CHART_NORMAL), wanted]
            + " chart, and the photograph reports %.2f:1 — %.1f%% out. A lighting ratio that"
            % [measured_ratio, ratio_error * 100.0]
            + " cannot be measured off a chart cannot be measured off a sky either.",
            measured_ratio
        )
    return ok(
        "wedge linear to %.2f%% over %d patches, a stop is a factor of two to %.2f%%, and a"
        % [worst_linear * 100.0, WEDGE.size(), worst_bracket * 100.0]
        + " %.2f:1 lighting ratio photographs as %.2f:1 (%.1f%%)"
        % [wanted, measured_ratio, ratio_error * 100.0],
        measured_ratio
    )


## The ratio that actually reaches a surface facing the camera, which is not the ratio of the two
## lights' intensities.
##
## **Lambert's cosine law, and the gate had to be corrected by it rather than the renderer.** The
## first version compared the photograph against 20000/5000 = 4:1 and the photograph said 6.80:1,
## which looks like a 70% error and is not one: the fill arrives at 54 degrees, so only
## cos(54) = 0.588 of it lands, and 20000 / (5000 x 0.588) is 6.80. The renderer was right. An
## incident meter obeys the same law, which is why a photographer aims one at the camera rather
## than at the light.
static func _wanted_ratio() -> float:
    var key: float = KEY_LUX * maxf(KEY_FROM.normalized().dot(CHART_NORMAL), 0.0)
    var fill: float = FILL_LUX * maxf(FILL_FROM.normalized().dot(CHART_NORMAL), 0.0)
    return key / maxf(fill, 0.000001)


## One HDR photograph, read at each patch.
func _photograph(
    harness: Node, at: PackedVector2Array, out_dir: String
) -> PackedFloat32Array:
    var out: PackedFloat32Array = PackedFloat32Array()
    var shot: Dictionary = await harness.capture_hdr(out_dir, "static", CONVERGE)
    if (shot["error"] as String) != "":
        push_error(shot["error"])
        return out
    var image: Image = shot["image"] as Image
    if image == null:
        return out
    for centre: Vector2 in at:
        out.append(_window(image, centre))
    return out


func _window(image: Image, centre: Vector2) -> float:
    var size: Vector2i = image.get_size()
    var total: float = 0.0
    var counted: int = 0
    for y: int in range(int(centre.y) - WINDOW_PX, int(centre.y) + WINDOW_PX):
        for x: int in range(int(centre.x) - WINDOW_PX, int(centre.x) + WINDOW_PX):
            if x < 0 or y < 0 or x >= size.x or y >= size.y:
                continue
            var colour: Color = image.get_pixel(x, y)
            total += colour.r * 0.2126 + colour.g * 0.7152 + colour.b * 0.0722
            counted += 1
    return total / float(maxi(counted, 1))


## How far the widest value in a set sits from its own mean, as a share of it.
func _spread(values: PackedFloat32Array) -> float:
    var mean: float = _mean(values)
    if mean <= 0.0:
        return INF
    var worst: float = 0.0
    for value: float in values:
        worst = maxf(worst, absf(value - mean) / mean)
    return worst


func _mean(values: PackedFloat32Array) -> float:
    if values.is_empty():
        return 0.0
    var total: float = 0.0
    for value: float in values:
        total += value
    return total / float(values.size())


func _row(values: PackedFloat32Array) -> String:
    var parts: PackedStringArray = PackedStringArray()
    for index: int in values.size():
        parts.append("%.3f@%.4f" % [WEDGE[index], values[index]])
    return ", ".join(parts)


func _patch_position(index: int) -> Vector3:
    var span: float = float(WEDGE.size() - 1) * PATCH_GAP
    return Vector3(float(index) * PATCH_GAP - span * 0.5, 0.0, 0.0)


func _build_wedge() -> Array[MeshInstance3D]:
    var out: Array[MeshInstance3D] = []
    var shader: Shader = load("res://game/shaders/chart_patch.gdshader") as Shader
    for index: int in WEDGE.size():
        var plane: PlaneMesh = PlaneMesh.new()
        plane.size = Vector2(PATCH_SIZE, PATCH_SIZE)
        plane.orientation = PlaneMesh.FACE_Z
        var material: ShaderMaterial = ShaderMaterial.new()
        material.shader = shader
        var level: float = WEDGE[index]
        material.set_shader_parameter("reflectance", Vector3(level, level, level))
        var instance: MeshInstance3D = MeshInstance3D.new()
        instance.name = "Patch_%d" % index
        instance.mesh = plane
        instance.material_override = material
        instance.position = _patch_position(index)
        out.append(instance)
    return out


## A light of stated illuminance, aimed at the chart.
func _build_light(name: String, from: Vector3, lux: float) -> DirectionalLight3D:
    var light: DirectionalLight3D = DirectionalLight3D.new()
    light.name = name
    light.look_at_from_position(Vector3.ZERO, -from.normalized(), Vector3.UP)
    light.light_intensity_lux = lux
    light.light_color = LIGHT_COLOUR
    light.light_energy = 1.0
    # A chart is flat and unoccluded; a shadow map here would only add its own bias.
    light.shadow_enabled = false
    return light
