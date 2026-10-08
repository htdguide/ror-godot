extends GateBase
## The sea reflects the sky by Fresnel: two per cent looking down into it, nearly all of it at the
## horizon, and the curve between is the one the index of refraction of water gives.
##
## **The oracle is the Fresnel equations for a dielectric of n = 1.333**, which are not this
## project's: the unpolarised reflectance of a flat interface at each angle of incidence, from
## published optics. The sea's own reflection is the engine's image-based lighting off a dielectric,
## so what this gate measures is whether that path gives water's reflectance — and it is measured as
## a ratio against a mirror at the same angle under the same sky, which cancels the furnace's
## radiance, the radiance map's scale and the roughness lobe, and leaves the Fresnel term alone.
##
## The sea is made black underneath for the measurement — nothing scattered back, everything
## absorbed — so that what comes off it is reflection and nothing else, and its surface is held
## flat so the angle is the one the camera was put at.
##
## **What it exists to catch.** The shader stated `SPECULAR = 0.5`, which is a reflectance of 4%
## looking straight down, twice water's; it had its own `WATER_F0` written as a constant beside it
## and never used. And the horizon reading 0.296 of the sky, recorded in the shader as unexplained,
## was taken with the haze on: the sea at the horizon is kilometres away and fogged to the fog's
## colour, the mirror it was compared with was not. This gate takes the fog off.

const PRESET: String = "hero_3q"
const WEATHER: String = "noon_clear"
const CONVERGE: int = 8
## The furnace's radiance. The captures are HDR and the readings are ratios, so any value does.
const FURNACE: float = 1.0
## Water's index of refraction.
const WATER_N: float = 1.333
## Angles of incidence measured, in degrees from straight down. The last is the horizon as near as
## a camera four metres up can look at it: a point on a flat sea 229 m off.
const ANGLES_DEG: Array[float] = [0.0, 40.0, 60.0, 75.0, 82.0, 89.0]
const CAMERA_HEIGHT_M: float = 4.0
const SEA_M: float = 4000.0
## How wide a patch is read at the frame's centre, in pixels either side.
const SAMPLE_PX: int = 6
## How far the measured reflectance may sit from exact Fresnel, as a share of it, with an absolute
## floor for the small values. The engine's Fresnel is Schlick's approximation through a fitted
## environment BRDF; against the exact equations Schlick alone is within 14% over these angles,
## and the fit costs a little more. A `SPECULAR` of 0.5 reads twice the exact value at 0 degrees.
const TOLERANCE_SHARE: float = 0.25
const TOLERANCE_ABS: float = 0.006


static func meta() -> Dictionary:
    return {
        "name": "a_sea_reflects_the_sky_by_fresnel",
        "proves": "the sea's reflectance of the sky follows the Fresnel equations for water at every angle from straight down to near the horizon, measured against a mirror under the same sky",
        "builds_on": ["a_white_furnace_shows_nothing"],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "reflectance within %.0f%% (floor %.3f) of unpolarised Fresnel for n = %.3f at %s degrees"
            % [TOLERANCE_SHARE * 100.0, TOLERANCE_ABS, WATER_N, str(ANGLES_DEG)]
        ),
        "why": (
            "the sea's reflection is the engine's dielectric response and nothing in this project"
            + " draws it, so the only way to know it is water's is to measure it against the"
            + " equations. The shader stated a 4% reflectance where water has 2%, with the right"
            + " constant written unused beside it, and recorded a dark horizon it could not"
            + " explain that was the haze."
        ),
        "budget_s": 90.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var err: String = harness.setup_for(PRESET, WEATHER)
    if err != "":
        return fail(err)
    clear_fog(harness)
    var holder: WorldEnvironment = (
        harness.world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    )
    if holder == null:
        return fail("the world has no environment to replace")
    holder.environment = furnace_environment(FURNACE)
    hide_everything(harness.world)

    var sea: MeshInstance3D = _plane()
    sea.material_override = _black_water()
    harness.world.add_child(sea)
    var mirror: MeshInstance3D = _plane()
    mirror.material_override = _mirror()
    mirror.visible = false
    harness.world.add_child(mirror)

    var worst: float = 0.0
    var worst_said: String = ""
    var reported: PackedStringArray = PackedStringArray()
    for index: int in ANGLES_DEG.size():
        var angle: float = ANGLES_DEG[index]
        _aim(harness, angle)
        sea.visible = true
        mirror.visible = false
        var water: Dictionary = await _centre(harness, "fresnel/%02d_water" % int(angle))
        if (water["error"] as String) != "":
            return fail(water["error"] as String)
        sea.visible = false
        mirror.visible = true
        var seen: Dictionary = await _centre(harness, "fresnel/%02d_mirror" % int(angle))
        if (seen["error"] as String) != "":
            return fail(seen["error"] as String)
        var furnace_at: float = seen["value"] as float
        if furnace_at < 0.01:
            return fail(
                "the mirror at %.0f degrees reads %.4f: the frame is not seeing the furnace"
                % [angle, furnace_at], furnace_at
            )
        var measured: float = (water["value"] as float) / furnace_at
        var exact: float = fresnel(deg_to_rad(angle), WATER_N)
        var off: float = measured - exact
        var allowed: float = maxf(TOLERANCE_ABS, exact * TOLERANCE_SHARE)
        reported.append("%.0f deg: %.4f against %.4f" % [angle, measured, exact])
        if absf(off) > allowed and absf(off) > absf(worst):
            worst = off
            worst_said = (
                "at %.0f degrees the sea reflects %.4f of what a mirror does where Fresnel"
                % [angle, measured] + " gives %.4f (%+.0f%%)" % [exact, 100.0 * off / exact]
            )
        elif worst == 0.0 and absf(off) > 0.0:
            pass
    if worst_said != "":
        return fail(
            "%s. Readings: %s" % [worst_said, "; ".join(reported)], worst
        )
    return ok(
        "the sea's reflectance follows Fresnel for n = %.3f at every angle: %s"
        % [WATER_N, "; ".join(reported)],
        0.0
    )


## Unpolarised Fresnel reflectance of a flat dielectric interface, air to a medium of index `n`,
## at angle of incidence `theta` — the average of the s and p polarisations.
static func fresnel(theta: float, n: float) -> float:
    var cos_i: float = cos(theta)
    var sin_t: float = sin(theta) / n
    if sin_t >= 1.0:
        return 1.0
    var cos_t: float = sqrt(1.0 - sin_t * sin_t)
    var rs: float = pow((cos_i - n * cos_t) / (cos_i + n * cos_t), 2.0)
    var rp: float = pow((cos_t - n * cos_i) / (cos_t + n * cos_i), 2.0)
    return 0.5 * (rs + rp)


## Puts the camera so the frame's centre meets the sea at the origin at this angle of incidence.
func _aim(harness: Node, angle_deg: float) -> void:
    var along: float = CAMERA_HEIGHT_M * tan(deg_to_rad(angle_deg))
    var from: Vector3 = Vector3(along, CAMERA_HEIGHT_M, 0.0)
    # Looking straight down, "up" cannot be up.
    var up: Vector3 = Vector3.UP if angle_deg > 1.0 else Vector3.FORWARD
    harness.camera.look_at_from_position(from, Vector3.ZERO, up)


## The value at the frame's centre of an HDR capture, averaged over a small patch.
func _centre(harness: Node, out_dir: String) -> Dictionary:
    var shot: Dictionary = await harness.capture_hdr(out_dir, "static", CONVERGE)
    if (shot["error"] as String) != "":
        return shot
    var image: Image = shot["image"] as Image
    if image == null:
        return {"error": "the HDR capture produced no image: %s" % out_dir}
    var size: Vector2i = image.get_size()
    var total: float = 0.0
    var counted: int = 0
    for dy: int in range(-SAMPLE_PX, SAMPLE_PX + 1):
        for dx: int in range(-SAMPLE_PX, SAMPLE_PX + 1):
            var colour: Color = image.get_pixel(size.x / 2 + dx, size.y / 2 + dy)
            total += (colour.r + colour.g + colour.b) / 3.0
            counted += 1
    return {"error": "", "value": total / float(counted)}


func _plane() -> MeshInstance3D:
    var node: MeshInstance3D = MeshInstance3D.new()
    var plane: PlaneMesh = PlaneMesh.new()
    plane.size = Vector2(SEA_M, SEA_M)
    node.mesh = plane
    node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    return node


## The sea's own material, black underneath and flat: reflection and nothing else.
func _black_water() -> ShaderMaterial:
    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = load(RorWater.SHADER) as Shader
    material.render_priority = 1
    material.set_shader_parameter("wave_phase", 0.0)
    material.set_shader_parameter("ripple_steepness", 0.001)
    material.set_shader_parameter("scattered", Color.BLACK)
    material.set_shader_parameter("extinction", Vector3(50.0, 50.0, 50.0))
    return material


## A mirror as smooth as the sea says it is, which returns the furnace at every angle.
func _mirror() -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = Color.WHITE
    material.metallic = 1.0
    material.roughness = 0.055
    return material
