extends GateBase
## Water takes light exponentially with depth, so equal steps down take equal fractions.
##
## **The oracle is Beer-Lambert**, which says the light surviving a path of length `d` through an
## absorbing medium is `exp(-k d)` — and the property this gate measures is the one that does not
## depend on `k` at all. Write what the camera reads off a plate at depth `d` as
##
##     L(d) = A + (L0 - A) * exp(-2 k d)
##
## where `A` is whatever the water scatters back on its own and the 2 is down and up again. Then
## for four plates at equally spaced depths the successive differences fall in a constant ratio:
##
##     (L2 - L3) / (L1 - L2)  =  (L3 - L4) / (L2 - L3)  =  exp(-2 k step)
##
## `A` cancels, `L0` cancels, and the absorption coefficients this project states cancel with them.
## What is left is the shape of the law. A sea that fades with depth by any other rule — a linear
## ramp, a smoothstep, a lerp towards a deep colour, which is what this shader used to do — fails
## it, and so does one that does not fade at all.
##
## It is worth having because the depth term is the whole difference between water and coloured
## glass, and because by eye a wrong fade curve is only ever "the sea looks a bit off".

const PRESET: String = "diag_topdown"
const WEATHER: String = "noon_clear"
const CONVERGE: int = 6
## Four plates, each this much deeper than the last. Shallow enough that the deepest still reads
## above the noise, far enough apart that the steps are not within it.
const STEP_M: float = 1.0
const PLATE_M: float = 2.2
## How wide the sea is over them: enough to fill the frame from the camera's height.
const SEA_M: float = 60.0
## How equal the two ratios have to be, as a share of the larger. Loose enough for an 8-bit
## capture of a rendered frame.
const TOLERANCE: float = 0.12
## And how far below one they have to be. **Equal ratios alone are not the claim.** A fade that is
## linear in depth has equal successive differences, so both of its ratios are exactly 1.0 and
## agree with each other perfectly — the first version of this gate would have passed a ramp. What
## makes a decay exponential is that each step takes the same *fraction*, and a fraction below one
## is what says any light is being taken at all.
const MOST_THAT_SURVIVES: float = 0.95
## The band each reading has to land in to be a reading at all.
const USABLE: Vector2 = Vector2(0.015, 0.95)
## How far across the plate's image the reading is averaged, in pixels either way.
const SAMPLE_PX: int = 45


static func meta() -> Dictionary:
    return {
        "name": "a_sea_swallows_light_by_beers_law",
        "proves": "what the sea takes from the light passing through it is exponential in depth, measured as a constant ratio of successive differences, which holds whatever the absorption coefficients are",
        "builds_on": ["a_terrain_has_the_water_its_file_declares"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "the two successive-difference ratios equal within %.0f%% and both under %.2f"
            % [TOLERANCE * 100.0, MOST_THAT_SURVIVES]
        ),
        "why": (
            "a depth fade is what separates water from coloured glass, and any monotonic curve"
            + " looks plausible in one frame. Beer-Lambert's shape is checkable without knowing"
            + " the coefficients, because the ratio of successive differences cancels them along"
            + " with the surface's own scattering and the brightness of what is being looked at."
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
    # The stage's own floor is in the way: the plates hang below the waterline, which is below it.
    var ground: Node3D = harness.world.get_node_or_null(^"Ground") as Node3D
    if ground != null:
        ground.visible = false
    var stage: Node3D = Node3D.new()
    # **One plate, lowered between frames, rather than four at once.** Four plates have to stand
    # in four places, and the sea over each of them reflects a different piece of sky: measured
    # that way the readings came back 0.4986, 0.4517, 0.4302, 0.3791, whose successive differences
    # do not even fall. The depth is the only thing that may differ between these readings.
    var plate: MeshInstance3D = _plate(Vector3.ZERO)
    stage.add_child(plate)
    stage.add_child(_sea())
    harness.world.add_child(stage)

    var read: PackedFloat32Array = PackedFloat32Array()
    var reported: PackedStringArray = PackedStringArray()
    for index: int in 4:
        var depth: float = STEP_M * float(index + 1)
        plate.position = Vector3(0.0, -depth, 0.0)
        var shot: Dictionary = await harness.capture_shot(
            "water/beer_%d" % index, "static", CONVERGE
        )
        if (shot["error"] as String) != "":
            return fail(shot["error"] as String)
        var image: Image = Image.load_from_file(shot["png"] as String)
        if image == null:
            return fail("the capture at %s could not be read" % shot["png"])
        var value: float = _at(harness, image, plate.position)
        if value < USABLE.x or value > USABLE.y:
            return fail(
                "the plate at %.2f m photographed at %.4f, outside the %.3f to %.2f this"
                % [depth, value, USABLE.x, USABLE.y]
                + " measurement needs: the exposure, not the water, is what this frame is"
                + " measuring. %s" % shot["png"],
                value
            )
        read.append(value)
        reported.append("%.2f m: %.4f" % [depth, value])

    # The plate has to get darker as it goes down before the shape of it means anything.
    for index: int in range(1, read.size()):
        if read[index] >= read[index - 1]:
            return fail(
                "the plate is no darker at %.2f m than at %.2f m (%s): the sea is not taking"
                % [STEP_M * float(index + 1), STEP_M * float(index), ", ".join(reported)]
                + " anything from what passes through it",
                read[index] - read[index - 1]
            )

    var first: float = read[0] - read[1]
    var second: float = read[1] - read[2]
    var third: float = read[2] - read[3]
    var early: float = second / maxf(first, 0.000001)
    var late: float = third / maxf(second, 0.000001)
    var apart: float = absf(early - late) / maxf(maxf(early, late), 0.000001)
    if early > MOST_THAT_SURVIVES or late > MOST_THAT_SURVIVES:
        return fail(
            "each metre of depth takes %.4f then %.4f of what the metre before it left, against"
            % [early, late]
            + " the %.2f this gate asks for (%s): a fade whose steps take the same amount rather"
            % [MOST_THAT_SURVIVES, ", ".join(reported)]
            + " than the same fraction is a ramp, not an absorption",
            maxf(early, late)
        )
    if apart > TOLERANCE:
        return fail(
            "equal steps down take unequal fractions: %.4f then %.4f, %.1f%% apart against the"
            % [early, late, apart * 100.0]
            + " %.0f%% this gate allows (%s). The sea's depth fade is not exponential."
            % [TOLERANCE * 100.0, ", ".join(reported)],
            apart
        )
    return ok(
        "one plate lowered %.2f m at a time reads %s; successive differences fall by %.4f then"
        % [STEP_M, ", ".join(reported), early]
        + " %.4f, %.1f%% apart" % [late, apart * 100.0],
        apart
    )



## One white plate, face up, so that every reading of it is lit and seen the same way and only its
## depth differs.
func _plate(at: Vector3) -> MeshInstance3D:
    var plate: MeshInstance3D = MeshInstance3D.new()
    var mesh: PlaneMesh = PlaneMesh.new()
    mesh.size = Vector2(PLATE_M, PLATE_M)
    plate.mesh = mesh
    var white: StandardMaterial3D = StandardMaterial3D.new()
    white.albedo_color = Color(0.85, 0.85, 0.85)
    white.roughness = 0.9
    plate.material_override = white
    plate.position = at
    return plate


## The sea over it, built the way `RorWater` builds one, with its surface held still.
func _sea() -> MeshInstance3D:
    var sea: MeshInstance3D = MeshInstance3D.new()
    var plane: PlaneMesh = PlaneMesh.new()
    plane.size = Vector2(SEA_M, SEA_M)
    sea.mesh = plane
    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = load(RorWater.SHADER) as Shader
    material.render_priority = 1
    material.set_shader_parameter("wave_phase", 0.0)
    sea.material_override = material
    sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    return sea


## What the plate reads, in light rather than in what the file encodes.
func _at(harness: Node, image: Image, at: Vector3) -> float:
    var where: Vector2 = harness.camera.unproject_position(at)
    var size: Vector2i = image.get_size()
    var viewport: Vector2 = harness.render_viewport().get_visible_rect().size
    var x: int = clampi(int(where.x / viewport.x * float(size.x)), 0, size.x - 1)
    var y: int = clampi(int(where.y / viewport.y * float(size.y)), 0, size.y - 1)
    var total: float = 0.0
    var counted: int = 0
    # **A wide patch, because the differences are a few levels of an 8-bit capture.** Read over
    # thirteen pixels the successive differences came out 0.044, 0.036 and 0.035, and the shape of
    # an exponential cannot be told from quantisation at that size.
    for dy: int in range(-SAMPLE_PX, SAMPLE_PX + 1, 3):
        for dx: int in range(-SAMPLE_PX, SAMPLE_PX + 1, 3):
            var colour: Color = image.get_pixel(
                clampi(x + dx, 0, size.x - 1), clampi(y + dy, 0, size.y - 1)
            )
            total += colour.srgb_to_linear().get_luminance()
            counted += 1
    return total / maxf(float(counted), 1.0)
