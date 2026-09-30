extends GateBase
## Checks the HDR pipeline against arithmetic rather than against a stored image.
##
## A ramp of known scene-referred values is drawn unshaded, so what reaches the tonemapper
## is exactly what this gate chose. Then:
##
##   linear tonemapping   output must equal input until it clips, and halving the exposure
##                        must halve the output — one stop, exactly
##   AgX                  output must rise monotonically and must sit below linear in the
##                        highlights, which is what "holds highlight detail" means
##
## Both are properties of the pipeline, not records of what it did last time.

const PRESET: String = "diag_topdown"
const SETTLE_FRAMES: int = 3
const RAMP_MAX: float = 4.0
const SAMPLE_COUNT: int = 16
## Metres per patch, and the height the grid sits at.
const PATCH_SIZE: float = 0.6
const RAMP_HEIGHT: float = 1.0
## Output is 8-bit and goes through an sRGB encode, so a couple of levels of slack.
const LINEAR_TOLERANCE: float = 0.02
const EXPOSURE_TOLERANCE: float = 0.03
## How much darker AgX must be than linear at the top of the ramp for highlight
## compression to be real rather than nominal.
const MIN_HIGHLIGHT_COMPRESSION: float = 0.05


static func meta() -> Dictionary:
    return {
        "name": "tonemap_and_exposure",
        "proves": "linear tonemapping is exact, exposure is exactly one stop, and AgX compresses highlights monotonically",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "linear within %.2f, one stop within %.2f, AgX monotonic and at least %.2f below linear on highlights"
            % [LINEAR_TOLERANCE, EXPOSURE_TOLERANCE, MIN_HIGHLIGHT_COMPRESSION]
        ),
        "why": (
            "an exposure applied twice, or a tonemapper that clips where it should roll"
            + " off, is invisible in any single image and changes every later judgement"
            + " about how the game looks. Both are exactly checkable."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)
    var environment: Environment = _environment(harness)
    if environment == null:
        return fail("the world has no environment to configure")

    var ramp: MeshInstance3D = _build_ramp(harness)
    harness.world.add_child(ramp)

    environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    environment.tonemap_exposure = 1.0
    var linear: PackedFloat32Array = await _sample(harness, "linear")

    environment.tonemap_exposure = 0.5
    var halved: PackedFloat32Array = await _sample(harness, "half_exposure")

    environment.tonemap_exposure = 1.0
    environment.tonemap_mode = RenderCfg.TONEMAP as Environment.ToneMapper
    var agx: PackedFloat32Array = await _sample(harness, "agx")
    ramp.queue_free()

    if linear.is_empty() or halved.is_empty() or agx.is_empty():
        return fail("the ramp did not render")

    # Linear tonemapping must be the identity below clipping.
    var worst_linear: float = 0.0
    for i: int in linear.size():
        var expected: float = minf(_ramp_value(i), 1.0)
        worst_linear = maxf(worst_linear, absf(linear[i] - expected))
    if worst_linear > LINEAR_TOLERANCE:
        return fail(
            "linear tonemapping is off by %.3f at worst: what reaches the screen is not"
            % worst_linear
            + " what was rendered",
            worst_linear
        )

    # Halving exposure must halve the result, wherever neither is clipped.
    var worst_stop: float = 0.0
    for i: int in linear.size():
        if linear[i] >= 0.98 or _ramp_value(i) <= 0.05:
            continue
        worst_stop = maxf(worst_stop, absf(halved[i] - linear[i] * 0.5))
    if worst_stop > EXPOSURE_TOLERANCE:
        return fail(
            "halving the exposure changed the image by %.3f away from half: exposure is"
            % worst_stop
            + " not being applied once and cleanly",
            worst_stop
        )

    # AgX must rise everywhere and hold back the highlights.
    for i: int in range(1, agx.size()):
        if agx[i] < agx[i - 1] - LINEAR_TOLERANCE:
            return fail(
                "AgX is not monotonic: sample %d is darker than sample %d" % [i, i - 1]
            )
    var compression: float = linear[agx.size() - 1] - agx[agx.size() - 1]
    if compression < MIN_HIGHLIGHT_COMPRESSION:
        return fail(
            "AgX gives only %.3f of highlight compression against linear: the curve is"
            % compression
            + " not doing its job",
            compression
        )
    return ok(
        "linear exact to %.3f, one stop to %.3f, AgX monotonic with %.2f highlight compression"
        % [worst_linear, worst_stop, compression],
        compression
    )


func _environment(harness: Node) -> Environment:
    var holder: WorldEnvironment = harness.world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    return null if holder == null else holder.environment


## Scene-referred value of sample i: a ramp from 0 to RAMP_MAX across the strip.
func _ramp_value(index: int) -> float:
    return RAMP_MAX * float(index) / float(SAMPLE_COUNT - 1)


## A grid of quads, each emitting one known value. A grid rather than a strip so every
## patch is large enough to sample reliably from above.
func _build_ramp(harness: Node) -> MeshInstance3D:
    var vertices: PackedVector3Array = PackedVector3Array()
    # The value travels in UV rather than vertex colour: Godot stores vertex colours as
    # 8-bit, so anything above 1.0 is clipped before it ever reaches the tonemapper, which
    # is precisely the range an HDR test needs.
    var uvs: PackedVector2Array = PackedVector2Array()
    var indices: PackedInt32Array = PackedInt32Array()
    for i: int in SAMPLE_COUNT:
        var centre: Vector3 = _patch_centre(i)
        var half: float = PATCH_SIZE * 0.5
        var base: int = vertices.size()
        vertices.append_array(PackedVector3Array([
            centre + Vector3(-half, 0.0, -half), centre + Vector3(half, 0.0, -half),
            centre + Vector3(half, 0.0, half), centre + Vector3(-half, 0.0, half),
        ]))
        var normalised: float = float(i) / float(SAMPLE_COUNT - 1)
        for corner: int in 4:
            uvs.append(Vector2(normalised, 0.0))
        indices.append_array(PackedInt32Array([
            base, base + 1, base + 2, base, base + 2, base + 3
        ]))

    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh: ArrayMesh = ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

    var shader: Shader = Shader.new()
    shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
uniform float ramp_max = 4.0;
void fragment() { ALBEDO = vec3(UV.x * ramp_max); }
"""
    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("ramp_max", RAMP_MAX)

    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = "TonemapRamp"
    instance.mesh = mesh
    instance.material_override = material
    instance.position = Vector3(0.0, RAMP_HEIGHT, 0.0)
    return instance


## Grid position of patch i, in the ramp's own space.
func _patch_centre(index: int) -> Vector3:
    var columns: int = int(sqrt(float(SAMPLE_COUNT)))
    var column: int = index % columns
    var row: int = index / columns
    var offset: float = (float(columns) - 1.0) * 0.5
    return Vector3(
        (float(column) - offset) * PATCH_SIZE, 0.0, (float(row) - offset) * PATCH_SIZE
    )


## One reading per ramp step, taken from the middle of each quad.
func _sample(harness: Node, tag: String) -> PackedFloat32Array:
    await harness.advance_frames(SETTLE_FRAMES, "static", tag)
    var shot: Dictionary = await harness.capture_shot("tonemap/" + tag, "static", 1)
    if shot["error"] != "":
        return PackedFloat32Array()
    var image: Image = Image.load_from_file(shot["png"] as String)
    if image == null:
        return PackedFloat32Array()
    image.srgb_to_linear()
    var camera: Camera3D = harness.camera
    var out: PackedFloat32Array = PackedFloat32Array()
    for i: int in SAMPLE_COUNT:
        var screen: Vector2 = camera.unproject_position(
            _patch_centre(i) + Vector3(0.0, RAMP_HEIGHT, 0.0)
        )
        var x: int = clampi(int(screen.x), 0, image.get_width() - 1)
        var y: int = clampi(int(screen.y), 0, image.get_height() - 1)
        out.append(image.get_pixel(x, y).get_luminance())
    return out
