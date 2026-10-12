extends GateBase
## A tie (`ties`) takes the nearest free ropable (`ropables`) within its reach, on another vehicle or
## its own, shortens at its rate until it is as short as its file allows or as tight as its stress
## limit, pulls the other vehicle with it, and lets go again, by upstream's `tieToggle`, `CalcTies`,
## `ParseTies` and `ParseRopables`.
##
## Ties were read and dropped: 543 corpus files declare ropables, and no tie could take one.
##
## The oracle is upstream's code, rule by rule, on small rigs in a `RorWorld`, the tying vehicle held
## still in free space:
## - a `ties` row needs five fields; a `ropables` row's group and multilock are optional;
## - the toggle takes the nearest ropable nearer than the reach (2 m), not the first listed, and not
##   one beyond it;
## - each substep the rope shortens by its rate times the substep, 0.5 m/s here, until its length is
##   no more than `min_length` (0.3) of its reach, then stops: 0.6 m;
## - it stops early once its stress passes `max_stress`;
## - tied, the other vehicle comes with it, and the two are one island at any distance;
## - a ropable without multilock takes one tie, with it any number; toggled again every tie lets go
##   and gives its ropable back;
## - a tie takes its own vehicle's ropables unless it says `s`;
## - a respawn lets go.

const SUBSTEP: float = 1.0 / 2000.0
const RATE: float = 0.5
const TIER: String = """tier
globals
300, 0, tracks/semi
nodes
0, 0.0, 0.0, 0.0
1, 1.0, 0.0, 0.0
2, 0.5, 1.0, 0.0
3, 0.5, 1.0, 0.6
beams
0, 1
1, 2
0, 2
0, 3
ties
%s
ropables
3
end"""
const LOAD: String = """load
globals
30, 0, tracks/semi
nodes
0, 0.5, 2.0, 0.0
1, 0.5, 2.5, 0.0
2, 1.5, 3.2, 0.0
beams
0, 1
1, 2
0, 2
ropables
%s
end"""
const ONE_TIE: String = "2, 2.0, 0.5, 0.3, 2.0, s"


static func meta() -> Dictionary:
    return {
        "name": "a_tie_takes_the_nearest_ropable_and_shortens",
        "proves": "ties take the nearest free ropable in reach, shorten at their rate to min_length or max_stress, pull the other vehicle, join its island and let go, with multilock, no-self-lock and respawn as upstream",
        "builds_on": [],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "every rule in the header exactly: five fields, nearest ropable, 0.00025 m a substep, stop at 0.6 m within one substep, stress stop above 0.99 m, the load no further than 0.62 m, one island, multilock, s, respawn",
        "why": "543 corpus files declare ropables and ties were read and dropped: nothing could be tied down.",
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var short: TruckParser = TruckParser.new()
    short.parse_text(TIER % "2, 2.0, 0.5, 0.3")
    if short.links.ties.size() != 0 or short.links.ropables.size() != 1:
        return fail("a four-field tie row made %d ties (upstream takes none); ropables %d, not 1" % [short.links.ties.size(), short.links.ropables.size()])

    # Nearest, shorten, stop, pull, island, let go. The load's ropables are listed 1.5 m, 1.0 m, 2.4 m.
    var pair: Array = _pair(ONE_TIE, "1\n0\n2", false)
    var world: RorWorld = pair[0]
    var tier: RorSolver = pair[1]
    var load: RorSolver = pair[2]
    if tier.tie_count() != 1:
        return fail("the ties row made %d ties, not 1" % tier.tie_count())
    world.toggle_ties(tier, -1)
    if tier.tie_state(0) != "tying" or tier.tie_ropable(0) != 1 or tier.tie_locked_to_self(0):
        return fail("the toggle left the tie %s on ropable %d; the load's second, 1.0 m away, is nearest" % [tier.tie_state(0), tier.tie_ropable(0)])
    for i: int in 10:
        world.step(SUBSTEP, 1)
    var shortened: float = 2.0 - tier.tie_length(0)
    if absf(shortened - 10.0 * RATE * SUBSTEP) > 1e-6:
        return fail("10 substeps shortened the tie %.7f m, upstream's rate gives %.7f" % [shortened, 10.0 * RATE * SUBSTEP], shortened)
    var substeps: int = 10
    while tier.tie_state(0) == "tying" and substeps < 8000:
        world.step(SUBSTEP, 1)
        substeps += 1
    var length: float = tier.tie_length(0)
    if tier.tie_state(0) != "tied" or length > 0.6 or length < 0.6 - RATE * SUBSTEP:
        return fail("after %d substeps the tie is %s at %.5f m, not stopped at 0.6 m" % [substeps, tier.tie_state(0), length], length)
    for i: int in 2000:
        world.step(SUBSTEP, 1)
    var gap: float = tier.get_node_position(2).distance_to(load.get_node_position(0))
    if gap > 0.62:
        return fail("tied at 0.6 m, the load's node is %.3f m from the tie: the rope did not pull" % gap, gap)
    for node: int in load.node_count():
        load.set_node_position(node, load.get_node_position(node) + Vector3(50.0, 0.0, 0.0))
    if not world.shares_island(0, 1, SUBSTEP, 1):
        return fail("tied together 50 m apart, the two vehicles are not one island")
    world.toggle_ties(tier, -1)
    if tier.tie_state(0) != "free":
        return fail("toggled again, the tie is %s" % tier.tie_state(0))
    var report: String = "nearest ropable, %.5f m in 10 substeps, stopped at %.5f m after %d, load within %.3f m, one island, let go" % [shortened, length, substeps, gap]

    # The stress limit: the load held, the rope goes tight at 1.0 m and the tie stops there.
    pair = _pair(ONE_TIE + ", 50", "0", true)
    world = pair[0]
    tier = pair[1]
    world.toggle_ties(tier, -1)
    world.step(SUBSTEP, 6000)
    if tier.tie_state(0) != "tied" or tier.tie_length(0) < 0.99:
        return fail("with max_stress 50 against a held load the tie is %s at %.4f m, not stopped near 1.0 m" % [tier.tie_state(0), tier.tie_length(0)])

    # Multilock: two ties, the 1.0 m ropable takes one unless it is multilock; let go and retied, the
    # first gets it back.
    var two: String = ONE_TIE + "\n" + ONE_TIE
    pair = _pair(two, "0\n1", true)
    world = pair[0]
    tier = pair[1]
    world.toggle_ties(tier, -1)
    if tier.tie_ropable(0) != 0 or tier.tie_ropable(1) != 1:
        return fail("two ties on a single-lock ropable took %d and %d, not 0 then 1" % [tier.tie_ropable(0), tier.tie_ropable(1)])
    world.toggle_ties(tier, -1)
    world.toggle_ties(tier, -1)
    if tier.tie_ropable(0) != 0:
        return fail("let go and retied, the first tie took ropable %d: the ropable was not given back" % tier.tie_ropable(0))
    pair = _pair(two, "0, -1, 1\n1", true)
    world = pair[0]
    tier = pair[1]
    world.toggle_ties(tier, -1)
    if tier.tie_ropable(0) != 0 or tier.tie_ropable(1) != 0:
        return fail("two ties on a multilock ropable took %d and %d, not both 0" % [tier.tie_ropable(0), tier.tie_ropable(1)])

    # Own ropable, 0.6 m away: taken without `s`, never with it.
    pair = _pair("2, 2.0, 0.5, 0.3, 2.0", "0", true)
    world = pair[0]
    tier = pair[1]
    world.toggle_ties(tier, -1)
    if not tier.tie_locked_to_self(0):
        return fail("without `s` the tie did not take its own ropable, 0.6 m away (%s, %d)" % [tier.tie_state(0), tier.tie_ropable(0)])

    # A respawn lets go.
    var truck: TruckParser = TruckParser.new()
    truck.parse_text(TIER % "2, 2.0, 0.5, 0.3, 2.0")
    RigBuilder.place(tier, truck, Vector3.ZERO, 0.0, 0.15)
    if tier.tie_state(0) != "free":
        return fail("respawned, the tie is still %s" % tier.tie_state(0))
    return ok(report + "; stress stop, multilock, own ropable and respawn as upstream", 0)


## A tier (its `ties` rows) and a load (its `ropables` rows) in one world.
func _pair(ties: String, ropables: String, load_held: bool) -> Array:
    var world: RorWorld = RorWorld.new()
    var tier: RorSolver = _build(TIER % ties, true)
    var load: RorSolver = _build(LOAD % ropables, load_held)
    world.add_solver(tier)
    world.add_solver(load)
    return [world, tier, load]


func _build(text: String, held: bool) -> RorSolver:
    var truck: TruckParser = TruckParser.new()
    truck.parse_text(text)
    var solver: RorSolver = RigBuilder.build(truck, 0.0)["solver"] as RorSolver
    solver.set_gravity(Vector3.ZERO)
    solver.set_ground(-100.0, false)
    if held:
        for node: int in solver.node_count():
            solver.set_node_immovable(node, true)
    return solver
