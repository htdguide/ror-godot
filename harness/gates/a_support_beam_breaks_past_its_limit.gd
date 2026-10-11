extends GateBase
## A support beam (`beams` option `s`) stretched past its break limit breaks, the way upstream's
## does: at the row's own limit in lengths of itself, or at 4 when the row gives none or 0.
##
## Upstream's `CalcBeams`, `SUPPORTBEAM` branch: a support beam carries no tension, and once its
## extension passes `L * longbound` (`SUPPORT_BEAM_LIMIT_DEFAULT` = 4 when unset) it is broken and
## disabled. The limit was parsed and kept, and nothing broke: a support beam held on however far
## the parts it joined were pulled apart.
##
## The oracle is that rule on a 1 m beam in free space: one end held, the other drawn away from it
## at a steady pace, stepped one substep at a time. (Thrown free, the end stops: a slack support beam
## keeps a tenth of its damping, which upstream's law says it should.) It has to break on the first substep its length passes 1 + limit,
## measured as upstream measures it (the Quake reciprocal square root, within 0.2%), and not before.

const SUBSTEP_HZ: float = 2000.0
const THROW_MS: float = 5.0
## Upstream's beam length is a fast inverse square root, about 0.2% off the exact one.
const LENGTH_TOLERANCE: float = 0.002
const CASES: Array[Dictionary] = [
    {"row": "0, 1, s, 2.0", "limit": 2.0},
    {"row": "0, 1, s", "limit": 4.0},
    {"row": "0, 1, s, 0", "limit": 4.0},
]


static func meta() -> Dictionary:
    return {
        "name": "a_support_beam_breaks_past_its_limit",
        "proves": "a support beam breaks on the substep it is stretched past its limit (the row's, else upstream's 4), and not before",
        "builds_on": ["beams_deform_and_break"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "1 m beam drawn out at %.0f m/s, limits 2 / unset / 0: breaks at length 1 + limit within %.1f%% plus one substep of travel" % [THROW_MS, LENGTH_TOLERANCE * 100.0],
        "why": "support beams never broke, so parts joined by one stayed tied together however far they were pulled.",
        "budget_s": 20.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var report: PackedStringArray = PackedStringArray()
    for case: Dictionary in CASES:
        var broke_at: float = _broke_at(case["row"] as String)
        if is_nan(broke_at):
            return fail("\"%s\" did not build" % case["row"])
        var want: float = 1.0 + (case["limit"] as float)
        var low: float = want * (1.0 - LENGTH_TOLERANCE)
        var high: float = want * (1.0 + LENGTH_TOLERANCE) + THROW_MS / SUBSTEP_HZ
        if broke_at < 0.0:
            return fail("\"%s\" never broke, pulled to %.3f m against its limit of %.2f m" % [case["row"], -broke_at, want], broke_at)
        if broke_at < low or broke_at > high:
            return fail("\"%s\" broke at %.4f m, its limit says %.2f m" % [case["row"], broke_at, want], broke_at)
        report.append("\"%s\" at %.4f m (limit %.1f m)" % [case["row"], broke_at, want])
    return ok("drawn out at %.0f m/s: %s" % [THROW_MS, ", ".join(report)], 0)


## The length at which the beam of `row` broke; minus the length reached if it had not in four
## seconds; NAN if the rig did not build.
func _broke_at(row: String) -> float:
    var text: String = "\n".join([
        "supporttest",
        "globals", "20, 0, tracks/semi",
        "nodes", "0, 0.0, 1.0, 0.0", "1, 1.0, 1.0, 0.0",
        "beams", row,
        "end",
    ])
    var truck: TruckParser = TruckParser.new()
    if truck.parse_text(text) != "":
        return NAN
    var built: Dictionary = RigBuilder.build(truck, 0.0)
    if (built["error"] as String) != "":
        return NAN
    var solver: RefCounted = built["solver"] as RefCounted
    solver.set_gravity(Vector3.ZERO)
    solver.set_node_immovable(0, true)
    solver.set_node_immovable(1, true)
    var origin: Vector3 = solver.get_node_position(0)
    var length: float = 1.0
    for substep: int in int(4.0 * SUBSTEP_HZ):
        length += THROW_MS / SUBSTEP_HZ
        solver.set_node_position(1, origin + Vector3(length, 0.0, 0.0))
        solver.step(1.0 / SUBSTEP_HZ, 1)
        if solver.beam_broken(0):
            return length
    return -length
