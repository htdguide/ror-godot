extends GateBase
## A vehicle respawned lets go of every hook, tie and rope another vehicle has on it, and of
## nothing else, as upstream's `DisjoinInterActorBeams` does on `SyncReset`: each other actor's
## `HOOK_RESET`, `TIE_RESET` and `ROPE_RESET` filtered to links locked to the respawned one.
##
## Before, a respawn let go only of the vehicle's own links: a trailer respawned elsewhere stayed
## hooked to the truck, and its rope beam spanned the map.
##
## The oracle is upstream's code on three held rigs in one world: a linker with two hooks, two ties
## and two ropes, the first of each on load A and the second on load B. Respawning A lets go of the
## first of each, gives A's ropable back (no tie and no rope on it), and leaves every link to B.

const LINKER: String = """linker
globals
300, 0, tracks/semi
nodes
0, 0.0, 0.0, 0.0
1, 1.0, 0.0, 0.0
2, 0.5, 1.0, 0.0, h
3, 0.5, 1.0, -1.0, h
4, 0.5, -0.5, 0.0
beams
0, 1
1, 2
0, 2
0, 3
ropes
2, 4
2, 4
ties
2, 2.0, 0.5, 0.3, 2.0, s
2, 2.0, 0.5, 0.3, 2.0, s
hooks
2, hookrange, 1.2
end"""
const LOAD: String = """load
globals
30, 0, tracks/semi
nodes
0, 0.5, 1.0, %s
1, 0.5, 1.5, %s
2, 1.5, 1.0, %s
beams
0, 1
1, 2
0, 2
ropables
0
end"""


static func meta() -> Dictionary:
    return {
        "name": "a_respawn_lets_go_of_every_link_to_it",
        "proves": "a respawn lets go of every other vehicle's hooks, ties and ropes on it, gives its ropables back, and leaves links to other vehicles, as upstream's DisjoinInterActorBeams",
        "builds_on": [],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "exact states: the links to A free and A's ropable held by nothing; the links to B as they were",
        "why": "a respawned trailer stayed hooked, tied or roped to the truck it had left.",
        "budget_s": 10.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var world: RorWorld = RorWorld.new()
    var linker: RorSolver = _build(LINKER)
    var load_a: RorSolver = _build(LOAD % ["1.0", "1.0", "1.0"])
    var load_b: RorSolver = _build(LOAD % ["-1.3", "-1.3", "-1.3"])
    for solver: RorSolver in [linker, load_a, load_b]:
        world.add_solver(solver)
    world.toggle_hooks(linker, 2, -1)
    world.toggle_ties(linker, -1)
    world.toggle_ropes(linker, -1)
    var before: String = _links(linker, load_a, load_b)
    if before != "hooks prelock/prelock ties tying/tying ropes 0/0 A 1/1 B 1/1":
        return fail("the links did not take A then B: %s" % before)
    var truck: TruckParser = TruckParser.new()
    truck.parse_text(LOAD % ["1.0", "1.0", "1.0"])
    RigBuilder.place(load_a, truck, Vector3(20.0, 0.0, 0.0), 0.0, 0.15)
    var after: String = _links(linker, load_a, load_b)
    if after != "hooks unlocked/prelock ties free/tying ropes -1/0 A 0/0 B 1/1":
        return fail("respawning A left %s; upstream lets go of A's links only" % after)
    return ok("before %s; after A's respawn %s" % [before, after], 0)


## The two hooks' and ties' states, the two ropes' ropables, and how many ties/ropes hold A's and
## B's ropable.
func _links(linker: RorSolver, load_a: RorSolver, load_b: RorSolver) -> String:
    var a: Vector2i = load_a.ropable_attached(0)
    var b: Vector2i = load_b.ropable_attached(0)
    return "hooks %s/%s ties %s/%s ropes %d/%d A %d/%d B %d/%d" % [
        linker.hook_state(0), linker.hook_state(1), linker.tie_state(0), linker.tie_state(1),
        linker.rope_ropable(0), linker.rope_ropable(1), a.x, a.y, b.x, b.y,
    ]


func _build(text: String) -> RorSolver:
    var truck: TruckParser = TruckParser.new()
    truck.parse_text(text)
    var solver: RorSolver = RigBuilder.build(truck, 0.0)["solver"] as RorSolver
    solver.set_gravity(Vector3.ZERO)
    solver.set_ground(-100.0, false)
    for node: int in solver.node_count():
        solver.set_node_immovable(node, true)
    return solver
