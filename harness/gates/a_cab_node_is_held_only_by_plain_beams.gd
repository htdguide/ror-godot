extends GateBase
## Upstream will not break a beam that would leave a collision-triangle node held by fewer than
## three live beams, and it counts only plain beams: a shock, rope or support beam on the node does
## not hold it (`GetNumActiveConnectedBeams` skips every beam with a bound).
##
## Ours counted every beam, so a cab node held by two plain beams and a support beam let its
## overloaded beam snap where upstream keeps it, softened, and keeps the triangle closed.
##
## The oracle is that rule on four nodes: a cab node joined to three others, one of its beams
## stretched far past its strength in one substep. With the third beam plain the node has three and
## the overloaded beam breaks; with it a support beam, a rope or a shock the node has two and the
## beam holds. A support beam turned into a plain one is counted again.

const SUBSTEP_HZ: float = 2000.0
const SPRING: float = 1000000.0
const DAMPING: float = 100.0
const DEFORM_N: float = 500.0
const STRENGTH_N: float = 1000.0
const STRETCH_M: float = 0.1
## The solver's bound kinds, as `BeamRows` names them.
const KINDS: Dictionary = {"plain": 0, "shock": 1, "rope": 2, "support": 3}


static func meta() -> Dictionary:
    return {
        "name": "a_cab_node_is_held_only_by_plain_beams",
        "proves": "the cab-node break rule counts only beams without a bound, as upstream's GetNumActiveConnectedBeams does",
        "builds_on": ["beams_deform_and_break"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "cab node with 2 plain beams + 1 shock, rope or support: overloaded beam holds; + 1 plain: it breaks",
        "why": "a shock or support beam on a cab node counted as holding it, so cab beams snapped where upstream keeps them and its collision triangles stay closed.",
        "budget_s": 10.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var report: PackedStringArray = PackedStringArray()
    for kind: String in KINDS:
        var broke: bool = _overload(KINDS[kind] as int, -1)
        if broke != (kind == "plain"):
            return fail("a cab node with two plain beams and a %s: the overloaded beam %s" % [
                kind, "broke" if broke else "held"])
        report.append("%s %s" % [kind, "broke" if broke else "held"])
    if not _overload(KINDS["support"] as int, KINDS["plain"] as int):
        return fail("a support beam made plain again was not counted: the overloaded beam held")
    return ok("third beam %s; support made plain broke" % ", ".join(report), 0)


## Overloads beam 0 of a cab node whose third beam has bound `kind` (then `then`, unless -1).
## Whether beam 0 broke.
func _overload(kind: int, then: int) -> bool:
    var solver: RefCounted = ClassDB.instantiate("RorSolver") as RefCounted
    solver.set_gravity(Vector3.ZERO)
    solver.set_ground(-100.0, false)
    var ends: Array[Vector3] = [Vector3(1.0 + STRETCH_M, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0)]
    solver.add_node(Vector3.ZERO, 1.0)
    for end: Vector3 in ends:
        solver.add_node(end, 1.0)
    for node: int in 4:
        solver.set_node_immovable(node, true)
    solver.set_node_cab(0, true)
    for i: int in 3:
        var beam: int = solver.add_beam(0, i + 1, 1.0, SPRING, DAMPING)
        solver.set_beam_limits(beam, DEFORM_N, STRENGTH_N if i == 0 else STRENGTH_N * 1000.0, 0.0, false)
    solver.set_beam_bounds(2, kind, 0.0, 0.0, 0.0, 0.0, 1.0)
    if then >= 0:
        solver.set_beam_bounds(2, then, 0.0, 0.0, 0.0, 0.0, 1.0)
    solver.step(1.0 / SUBSTEP_HZ, 1)
    return solver.beam_broken(0)
