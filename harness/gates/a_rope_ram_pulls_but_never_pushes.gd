extends GateBase
## A command ram with upstream's option `r` is a rope: shortened it pulls its end in, lengthened it
## goes slack and pushes nothing, where an ordinary ram pushes its end away.
##
## Upstream's `ProcessCommand` sets such a beam's bound to `ROPE`, and `CalcBeams` then drops its
## spring and nine tenths of its damping whenever it is shorter than its rest length. 45 corpus files
## have 192 such rams; ours pushed like struts.
##
## The oracle is that law on a two-node rig in free space: one end held, the other free and at rest.
## Lengthening a rope ram leaves the free end where it was, to the bit, because a slack rope with no
## closing speed exerts exactly nothing; the same row without `r` pushes it away. Shortening either
## pulls the free end in.

const SUBSTEP_HZ: float = 2000.0
const CHUNK: int = 33
const RATE: float = 0.25
const HOLD_S: float = 1.0
## How far an ordinary ram has to push or either pull, metres: a tenth of what it was commanded.
const MOVED_M: float = RATE * HOLD_S * 0.1


static func meta() -> Dictionary:
    return {
        "name": "a_rope_ram_pulls_but_never_pushes",
        "proves": "a command ram with option r pulls when shortened and pushes nothing when lengthened, as upstream's ROPE bound does",
        "builds_on": ["a_ram_moves_by_its_rate_and_stops_at_its_bounds"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "lengthened 1 s: rope end moved exactly 0, plain ram over %.3f m; shortened 1 s: both pulled over %.3f m" % [MOVED_M, MOVED_M],
        "why": "option r was read and ignored: 192 rope rams in 45 corpus files pushed like struts.",
        "budget_s": 20.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var report: PackedStringArray = PackedStringArray()
    for rope: bool in [true, false]:
        var pushed: float = _moved(rope, 2)
        var pulled: float = _moved(rope, 1)
        if is_nan(pushed) or is_nan(pulled):
            return fail("the %s rig did not build" % ("rope" if rope else "plain"))
        var kind: String = "rope" if rope else "plain ram"
        if rope and pushed != 0.0:
            return fail("lengthened, the rope moved its free end %.9f m: a slack rope pushed" % pushed, pushed)
        if not rope and pushed < MOVED_M:
            return fail("lengthened, the plain ram moved its free end %.6f m: it should push" % pushed, pushed)
        if pulled > -MOVED_M:
            return fail("shortened, the %s moved its free end %.6f m: it should pull" % [kind, pulled], pulled)
        report.append("%s pushed %.6f m, pulled %.6f m" % [kind, pushed, pulled])
    return ok("1 s at %.2f m/s: %s" % [RATE, "; ".join(report)], 0)


## How far the free end moved away from the held one in `HOLD_S` with `key` held: 1 shortens the
## ram, 2 lengthens it. NAN if the rig did not build.
func _moved(rope: bool, key: int) -> float:
    var text: String = "\n".join([
        "ropetest",
        "globals", "20, 0, tracks/semi",
        "nodes", "0, 0.0, 1.0, 0.0", "1, 1.0, 1.0, 0.0",
        "commands2",
        "0, 1, %.2f, %.2f, 0.5, 2.0, 1, 2, %s" % [RATE, RATE, "r" if rope else "n"],
        "end",
    ])
    var truck: TruckParser = TruckParser.new()
    if truck.parse_text(text) != "" or truck.commands.size() != 1:
        return NAN
    var built: Dictionary = RigBuilder.build(truck, 0.0)
    if (built["error"] as String) != "":
        return NAN
    var solver: RefCounted = built["solver"] as RefCounted
    solver.set_gravity(Vector3.ZERO)
    solver.set_node_immovable(0, true)
    var start: float = solver.get_node_position(1).distance_to(solver.get_node_position(0))
    solver.set_command_key(key, 1.0)
    var left: int = int(round(HOLD_S * SUBSTEP_HZ))
    while left > 0:
        var take: int = mini(CHUNK, left)
        solver.step(1.0 / SUBSTEP_HZ, take)
        left -= take
    return solver.get_node_position(1).distance_to(solver.get_node_position(0)) - start
