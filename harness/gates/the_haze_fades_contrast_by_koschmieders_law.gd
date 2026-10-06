extends GateBase
## The haze in the picture is the haze the weather states, measured against Koschmieder's law.
##
## **Aerial perspective has a published scale and this project is set by it.** Koschmieder (1924):
## the apparent contrast of a target seen through a scattering medium falls as
##
##     C(d) = C0 * exp(-k d)
##
## and the meteorological visual range is where that reaches the 2% a human eye can still tell
## apart, which is `V = 3.912 / k`. Every fog density in `weather_cfg.gd` is written as that
## relation — a fog bank at three hundred metres is 0.01304, a dawn mist at two kilometres is
## 0.001956 — so the question this gate asks is whether the frame agrees.
##
## **A black panel and a white one at the same distance.** Both take the same fog colour, so their
## difference is exactly `C0 * exp(-k d)` with everything else cancelled: the sky behind them, the
## exposure, the tonemapper's shape over the range they occupy. Four such pairs at even distances
## give three successive ratios, each of which is `exp(-k * step)`, and `k` comes back out of the
## frame without this gate ever being told what it should be. It is then compared with what the
## environment was actually set to.
##
## The panels are unshaded, so what is measured is the air and not the lighting.

const PRESET: String = "hero_3q"
## The thickest haze in the library, because it is the one whose law can be measured over a
## distance that fits in a scene. A mist of two kilometres needs two kilometres of panels.
const WEATHER: String = "fog_bank"
const CONVERGE: int = 6
## Where the panels stand, in metres down the view, and how big they are. Big enough that the
## furthest pair is still tens of pixels across.
const DISTANCES: Array[float] = [40.0, 80.0, 120.0, 160.0]
const PANEL_M: float = 4.0
## **Each pair stands on its own line of sight, and that is not decoration.** Put straight down the
## view at four distances, the nearest pair covers every pair behind it: all four readings came back
## 0.3908, 0.3916, 0.3916, 0.3916, which is one panel measured four times and reads exactly like a
## fog that does not fade. The pairs fan across the view instead, this many degrees apart.
const YAW_STEP_DEG: float = 10.0
const EYE_HEIGHT_M: float = 2.0
## How far the recovered extinction may sit from the one the weather states.
const TOLERANCE: float = 0.12
## The band a pair's difference has to land in to be a reading: above the 8-bit floor, below the
## point where either panel clips.
const MIN_DIFFERENCE: float = 0.01
## The two panels. Not black and white: one must not sit on the floor of the film and the other
## must not clip, or the difference between them stops being a contrast.
const DARK: Color = Color(0.04, 0.04, 0.04)
const LIGHT: Color = Color(0.8, 0.8, 0.8)


static func meta() -> Dictionary:
    return {
        "name": "the_haze_fades_contrast_by_koschmieders_law",
        "proves": "the extinction recovered from a photographed contrast ramp is the fog density the weather states, so a stated visual range is the one the picture has",
        "builds_on": ["tonemap_and_exposure"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "extinction recovered from the frame within %.0f%% of the density the weather states"
            % (TOLERANCE * 100.0)
        ),
        "why": (
            "every fog density in this project is written as 3.912 over a visual range, which is"
            + " only meaningful if the renderer's own fog follows the same law. A fog that fades"
            + " on any other curve makes every stated visibility a number with no referent, and"
            + " by eye one haze looks much like another."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var err: String = harness.setup_for(PRESET, WEATHER)
    if err != "":
        return fail(err)
    var holder: WorldEnvironment = (
        harness.world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    )
    if holder == null or holder.environment == null:
        return fail("the world has no environment to read a fog density from")
    var stated: float = holder.environment.fog_density
    if stated <= 0.0:
        return fail("%s states no fog density at all" % WEATHER, stated)
    # The ground would be a second thing fading with distance in the same frame.
    var ground: Node3D = harness.world.get_node_or_null(^"Ground") as Node3D
    if ground != null:
        ground.visible = false

    var eye: Vector3 = Vector3(0.0, EYE_HEIGHT_M, 0.0)
    harness.camera.look_at_from_position(eye, eye + Vector3.FORWARD, Vector3.UP)
    var stage: Node3D = Node3D.new()
    var places: Array[Vector3] = []
    for index: int in DISTANCES.size():
        places.append(_middle_of(eye, index))
        stage.add_child(_panel(places[index] + Vector3(0.0, PANEL_M * 0.6, 0.0), DARK, eye))
        stage.add_child(_panel(places[index] - Vector3(0.0, PANEL_M * 0.6, 0.0), LIGHT, eye))
    harness.world.add_child(stage)

    var shot: Dictionary = await harness.capture_shot("haze/ramp", "static", CONVERGE)
    if (shot["error"] as String) != "":
        return fail(shot["error"] as String)
    var image: Image = Image.load_from_file(shot["png"] as String)
    if image == null:
        return fail("the capture at %s could not be read" % shot["png"])

    var differences: PackedFloat32Array = PackedFloat32Array()
    var reported: PackedStringArray = PackedStringArray()
    for index: int in DISTANCES.size():
        var dark: float = _at(harness, image, places[index] + Vector3(0.0, PANEL_M * 0.6, 0.0))
        var light: float = _at(harness, image, places[index] - Vector3(0.0, PANEL_M * 0.6, 0.0))
        var difference: float = light - dark
        var distance: float = DISTANCES[index]
        reported.append("%.0f m: %.4f" % [distance, difference])
        if difference < MIN_DIFFERENCE:
            return fail(
                "at %.0f m the two panels are %.4f apart, under the %.3f this measurement needs"
                % [distance, difference, MIN_DIFFERENCE]
                + " (%s): the ramp has faded into the noise rather than into the law. %s"
                % [", ".join(reported), shot["png"]],
                difference
            )
        differences.append(difference)

    # Each successive ratio is exp(-k * step), so each one gives a k.
    var step: float = DISTANCES[1] - DISTANCES[0]
    var recovered: PackedFloat32Array = PackedFloat32Array()
    for index: int in range(1, differences.size()):
        recovered.append(-log(differences[index] / differences[index - 1]) / step)
    var mean: float = 0.0
    for value: float in recovered:
        mean += value
    mean /= float(recovered.size())
    var off: float = absf(mean - stated) / stated
    var said: PackedStringArray = PackedStringArray()
    for value: float in recovered:
        said.append("%.5f" % value)
    if off > TOLERANCE:
        return fail(
            "the frame fades at %.5f per metre where %s states %.5f, %.1f%% apart and over the"
            % [mean, WEATHER, stated, off * 100.0]
            + " %.0f%% allowed (steps %s; %s). A stated visual range of %.0f m is not the one"
            % [TOLERANCE * 100.0, ", ".join(said), ", ".join(reported), 3.912 / stated]
            + " the picture has. %s" % shot["png"],
            mean
        )
    return ok(
        "%s states %.5f per metre, which is a visual range of %.0f m; the frame fades at %.5f"
        % [WEATHER, stated, 3.912 / stated, mean]
        + " (%s), %.1f%% apart. Contrasts: %s" % [", ".join(said), off * 100.0, ", ".join(reported)],
        off
    )


## One panel facing the camera.
##
## **Lit, and that is not a choice.** Unshaded was the obvious way to measure air rather than
## lighting, and Godot does not fog an unshaded surface at all: the two panels stayed 0.2966,
## 0.2975, 0.2975, 0.2975 apart across forty to a hundred and sixty metres, which is a frame with
## no haze in it. Lit panels work because the difference between them cancels the lighting anyway —
## both face the same way in the same place and take the same light, so what is left of
## `mix(colour, fog, 1 - exp(-k d))` is exactly the contrast times `exp(-k d)`.
## Where a pair stands: its own distance, down its own line of sight.
func _middle_of(eye: Vector3, index: int) -> Vector3:
    var yaw: float = deg_to_rad(
        (float(index) - float(DISTANCES.size() - 1) * 0.5) * YAW_STEP_DEG
    )
    return eye + Vector3(sin(yaw), 0.0, -cos(yaw)) * DISTANCES[index]


func _panel(at: Vector3, colour: Color, eye: Vector3) -> MeshInstance3D:
    var panel: MeshInstance3D = MeshInstance3D.new()
    var quad: QuadMesh = QuadMesh.new()
    quad.size = Vector2(PANEL_M, PANEL_M)
    panel.mesh = quad
    var flat: StandardMaterial3D = StandardMaterial3D.new()
    flat.albedo_color = colour
    flat.roughness = 1.0
    # A `QuadMesh` faces +Z and `look_at` points -Z at its target, so a panel turned towards the
    # camera presents its back to it and is culled away: the frame came back empty.
    flat.cull_mode = BaseMaterial3D.CULL_DISABLED
    panel.material_override = flat
    panel.position = at
    panel.look_at_from_position(at, Vector3(eye.x, at.y, eye.z), Vector3.UP)
    return panel


## What a panel reads, in light rather than in what the file encodes.
func _at(harness: Node, image: Image, at: Vector3) -> float:
    var where: Vector2 = harness.camera.unproject_position(at)
    var size: Vector2i = image.get_size()
    var viewport: Vector2 = harness.render_viewport().get_visible_rect().size
    var x: int = clampi(int(where.x / viewport.x * float(size.x)), 0, size.x - 1)
    var y: int = clampi(int(where.y / viewport.y * float(size.y)), 0, size.y - 1)
    var total: float = 0.0
    var counted: int = 0
    for dy: int in range(-5, 6, 2):
        for dx: int in range(-5, 6, 2):
            total += image.get_pixel(
                clampi(x + dx, 0, size.x - 1), clampi(y + dy, 0, size.y - 1)
            ).srgb_to_linear().get_luminance()
            counted += 1
    return total / maxf(float(counted), 1.0)
