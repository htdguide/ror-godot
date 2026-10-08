class_name GateBase
extends RefCounted
## Base class for every gate.
##
## A gate declares its own metadata and the gate_metadata meta-gate refuses to run a
## gate that does not. The required keys exist so that a failure is actionable and so
## that the suite can report its own debt: which gates lean on a golden image instead
## of an outside oracle, and what each one costs in runtime.
##
## Required metadata keys:
##   name         String, stable identifier used on the command line
##   proves       String, the single claim this gate makes. One gate, one claim.
##   oracle       String, one of the ORACLE_* values below
##   threshold    String, the numeric bound and its unit
##   why          String, why that threshold is the right number
##   budget_s     float, runtime budget in seconds
##   needs_gpu    bool, whether it renders
##   milestone    String, owning milestone
##
## Optional:
##   builds_on    Array[String], the gates whose claims this gate's claim contains. See
##                `GateChain` for what an edge means and what the runner does with it.

const ORACLE_EXTERNAL: String = "external"
const ORACLE_COMPUTED: String = "computed"
const ORACLE_INVARIANT: String = "invariant"
const ORACLE_GOLDEN: String = "golden"
const ORACLE_NONE: String = "none"

const REQUIRED_KEYS: Array[String] = [
    "name", "proves", "oracle", "threshold", "why", "budget_s", "needs_gpu", "milestone",
]

const VALID_ORACLES: Array[String] = [
    ORACLE_EXTERNAL, ORACLE_COMPUTED, ORACLE_INVARIANT, ORACLE_GOLDEN, ORACLE_NONE,
]


## Override. Must return every key in REQUIRED_KEYS.
static func meta() -> Dictionary:
    return {}


## Override. Returns {"pass": bool, "detail": String, "measured": Variant}.
## A failure must report the measured value, the threshold and the artifact path;
## "FAILED" with no number is a bug in the gate.
func run(_harness: Node) -> Dictionary:
    return fail("gate does not implement run()")


static func ok(detail: String, measured: Variant = null) -> Dictionary:
    return {"pass": true, "detail": detail, "measured": measured}


static func fail(detail: String, measured: Variant = null) -> Dictionary:
    return {"pass": false, "detail": detail, "measured": measured}


## Validates one gate's metadata. Used by the gate_metadata meta-gate and by the
## runner before a gate is allowed to execute.
static func validate_meta(meta_dict: Dictionary) -> String:
    for key: String in REQUIRED_KEYS:
        if not meta_dict.has(key):
            return "missing required metadata key '%s'" % key
        if meta_dict[key] is String and (meta_dict[key] as String).strip_edges().is_empty():
            return "metadata key '%s' is empty" % key
    var oracle: String = meta_dict["oracle"] as String
    if not VALID_ORACLES.has(oracle):
        return "oracle '%s' is not one of %s" % [oracle, VALID_ORACLES]
    if float(meta_dict["budget_s"]) <= 0.0:
        return "budget_s must be positive"
    # A gate whose measured value is a wall-clock time says so, and the order check then holds it
    # to its verdict alone: a frame time is not a function of what ran before, and a 1e-5 bound on
    # it would be asking the machine to be a clock.
    if meta_dict.has("measured_is_wall_clock") and not (meta_dict["measured_is_wall_clock"] is bool):
        return "measured_is_wall_clock must be true or false"
    if meta_dict.has("builds_on"):
        if not (meta_dict["builds_on"] is Array):
            return "builds_on must be an array of gate names"
        for edge: Variant in meta_dict["builds_on"] as Array:
            if not (edge is String) or (edge as String).strip_edges().is_empty():
                return "builds_on must hold gate names"
    return ""


## Turns the distance haze off for a measurement.
##
## Fog is grading, and a gate that measures light or framing is measuring neither the grading nor
## the weather: with haze on, a body lit from the front and one lit from behind wash to the same
## number, and distant ground takes the colour of the sky and counts as sky. Sessions see fog by
## default; measurements of contrast and of framing ask for it to be taken away first.
func clear_fog(harness: Node) -> void:
    var holder: WorldEnvironment = harness.world.get_node_or_null(
        ^"WorldEnvironment"
    ) as WorldEnvironment
    if holder != null and holder.environment != null:
        holder.environment.fog_enabled = false


## Hides everything that draws or lights, wherever it is in the tree. What a furnace or a
## reflectance measurement needs is an enclosure with nothing in it but the thing being measured.
static func hide_everything(node: Node) -> void:
    for child: Node in node.get_children():
        var light: Light3D = child as Light3D
        var drawn: VisualInstance3D = child as VisualInstance3D
        if light != null or drawn != null:
            (child as Node3D).visible = false
        hide_everything(child)


## One radiance from every direction, and nothing else whatsoever: no sun, no fog, no glow, no
## grading, a linear tonemapper. A furnace has one correct answer and no setup to agree about.
## **A new `Environment`, not the world's own with these written over it** — the weather's carries
## glow, colour adjustment, fog and an ambient of its own, and edited in place every white ball
## read 2.95 times the sky behind it.
static func furnace_environment(radiance: float) -> Environment:
    var environment: Environment = Environment.new()
    var sky: Sky = Sky.new()
    sky.process_mode = Sky.PROCESS_MODE_QUALITY
    sky.radiance_size = RenderCfg.SKY_RADIANCE_SIZE as Sky.RadianceSize
    var paint: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
    paint.sky_top_color = Color.WHITE
    paint.sky_horizon_color = Color.WHITE
    paint.ground_bottom_color = Color.WHITE
    paint.ground_horizon_color = Color.WHITE
    # One multiplier and not three: they compound, so setting all of them makes the furnace the
    # cube of what it says.
    paint.sky_energy_multiplier = 1.0
    paint.ground_energy_multiplier = 1.0
    paint.energy_multiplier = radiance
    paint.sun_angle_max = 0.0
    sky.sky_material = paint
    environment.background_mode = Environment.BG_SKY
    environment.sky = sky
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    environment.ambient_light_sky_contribution = 1.0
    environment.ambient_light_energy = 1.0
    environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
    environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    environment.tonemap_exposure = 1.0
    return environment
