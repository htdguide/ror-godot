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
