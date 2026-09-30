extends GateBase
## The decisive spike: does Godot's GPU skinning reproduce Rigs of Rods' FlexBody
## deformation exactly?
##
## FlexBody computes, per vertex, dst = F*c + P[ref] - center, where F has columns
## (diffX, diffY, nCross) built from the vertex's three locator nodes. That is one affine
## transform applied to a constant vector: single-bone linear blend skinning.
##
## If the identity holds on the GPU, the bridge uploads a few thousand bone transforms
## per actor per frame instead of hundreds of kilobytes of vertices, the deformation runs
## on the GPU, and motion vectors come for free from Godot's own previous-bone-pose path.
## If it does not hold, milestone (b) needs the fallback ladder instead.
##
## Measured on the GPU rather than in GDScript on purpose: CPU-side agreement would only
## prove the algebra, which is already provable on paper. What is actually in question is
## whether Godot's pipeline preserves a non-orthonormal bone basis.

const PRESET: String = "diag_lattice"
const THRESHOLD_MM: float = 1.0
const SETTLE_FRAMES: int = 3
const SHADER_PATH: String = "res://game/shaders/flex_error.gdshader"
## Minimum share of sampled pixels that must contain geometry. Without this the gate
## passes perfectly when nothing renders at all, which is the most likely way for a
## measurement gate to be quietly wrong.
const MIN_COVERAGE: float = 0.01
## Negative control: a deliberate error injected into one bone, which the measurement
## must detect. Comfortably over the threshold so the control tests the instrument, not
## the threshold.
const SABOTAGE_MM: float = 5.0
const SAMPLE_STRIDE: int = 2


static func meta() -> Dictionary:
    return {
        "name": "flexbody_lbs_equivalence",
        "proves": "Godot GPU skinning reproduces FlexBody deformation within the error threshold across extreme poses",
        # comparing skinned output against the reference requires the skinned path to apply its bone
        # transforms at all.
        "builds_on": ["skinned_flexbody_path"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "max vertex error < %.1f mm in every pose" % THRESHOLD_MM,
        "why": (
            "1 mm is well under a pixel at any framing a player sees, and it is the"
            + " bound below which a skinned truck is visually indistinguishable from"
            + " today's CPU deformation. The whole motion-vector plan rests on this"
            + " identity, so it is measured on the GPU rather than assumed from algebra."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)
    # This gate reads numbers back out of pixels, so nothing else may write to the frame:
    # linear tonemapping, black background, no ground.
    harness.use_measurement_environment()

    var lattice: FlexLattice = FlexLattice.new()
    lattice.build(harness.rng)
    var rig: FlexSkinRig = FlexSkinRig.new()
    var rig_error: String = rig.build(harness.world, lattice, SHADER_PATH, THRESHOLD_MM)
    if rig_error != "":
        return fail(rig_error)

    var worst_pose: String = ""
    var worst_mm: float = 0.0
    for pose: String in FlexPoses.POSES:
        var nodes: PackedVector3Array = FlexPoses.apply(pose, lattice.node_rest)
        rig.set_pose(nodes, lattice)
        await harness.advance_frames(SETTLE_FRAMES, "static", "pose_" + pose)
        var shot: Dictionary = await harness.capture_shot(
            "flexbody_lbs/" + pose, "static", 1
        )
        if shot["error"] != "":
            return fail(shot["error"] as String)
        var measured: Dictionary = _measure(shot["png"] as String)
        if measured.has("error"):
            return fail(measured["error"] as String)
        if float(measured["coverage"]) < MIN_COVERAGE:
            return fail(
                "pose '%s': only %.3f%% of the frame contains geometry, need %.1f%%;"
                % [pose, float(measured["coverage"]) * 100.0, MIN_COVERAGE * 100.0]
                + " the measurement would be meaningless. Artifact: %s" % shot["png"],
                measured["coverage"]
            )
        if bool(measured["over_threshold"]):
            return fail(
                "pose '%s': %d pixels exceed %.1f mm; artifact: %s"
                % [pose, int(measured["over_pixels"]), THRESHOLD_MM, shot["png"]],
                measured["max_mm"]
            )
        if float(measured["max_mm"]) > worst_mm:
            worst_mm = float(measured["max_mm"])
            worst_pose = pose
    var control: Dictionary = await _negative_control(harness, rig, lattice)
    rig.free_resources()
    if control.has("error"):
        return fail(control["error"] as String)
    return ok(
        (
            "%d bones, %d vertices: max error %.4f mm in pose '%s', under the %.1f mm"
            + " threshold in all %d poses"
        )
        % [
            lattice.bone_count(), lattice.vertex_count(), worst_mm, worst_pose,
            THRESHOLD_MM, FlexPoses.POSES.size()
        ],
        worst_mm
    )


## Injects a known error and requires the measurement to catch it. Without this the gate
## would pass just as happily if the shader, the capture or the decode were broken and
## every pixel read zero.
func _negative_control(harness: Node, rig: FlexSkinRig, lattice: FlexLattice) -> Dictionary:
    var nodes: PackedVector3Array = FlexPoses.apply("rest", lattice.node_rest)
    rig.set_pose(nodes, lattice)
    rig.sabotage_bone(0, Vector3(SABOTAGE_MM / 1000.0, 0.0, 0.0), lattice, nodes)
    await harness.advance_frames(SETTLE_FRAMES, "static", "negative_control")
    var shot: Dictionary = await harness.capture_shot("flexbody_lbs/negative_control", "static", 1)
    if shot["error"] != "":
        return {"error": shot["error"]}
    var measured: Dictionary = _measure(shot["png"] as String)
    if measured.has("error"):
        return measured
    if int(measured["over_pixels"]) == 0:
        return {
            "error": (
                "negative control failed: a deliberate %.1f mm bone error was not"
                + " detected, so the measurement proves nothing. Artifact: %s"
            ) % [SABOTAGE_MM, shot["png"]]
        }
    return {"over_pixels": measured["over_pixels"]}


## Reads the error image back. Red is the over-threshold flag, green the error ratio.
func _measure(png_path: String) -> Dictionary:
    var image: Image = Image.load_from_file(png_path)
    if image == null:
        return {"error": "cannot read %s" % png_path}
    # The framebuffer is written in sRGB; the shader wrote linear values into it.
    image.srgb_to_linear()
    var size: Vector2i = image.get_size()
    var max_ratio: float = 0.0
    var over: int = 0
    var covered: int = 0
    var sampled: int = 0
    for y: int in range(0, size.y, SAMPLE_STRIDE):
        for x: int in range(0, size.x, SAMPLE_STRIDE):
            var pixel: Color = image.get_pixel(x, y)
            sampled += 1
            if pixel.r > 0.5:
                over += 1
            # Blue is the presence marker: a correct result is black in red and green.
            if pixel.b > 0.5:
                covered += 1
            max_ratio = maxf(max_ratio, pixel.g)
    return {
        "max_mm": max_ratio * THRESHOLD_MM,
        "over_pixels": over,
        "over_threshold": over > 0,
        "coverage": float(covered) / float(maxi(sampled, 1)),
    }
