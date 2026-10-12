extends GateBase
## A rope (`ropes`) locks its end node to the nearest free ropable within its length, on any vehicle
## of the world, its own too; locked, the end node rides on the ropable and the ropable takes every
## force the end node gathers, so a load hangs from the rope; toggled again it lets go. By upstream's
## `ropeToggle` and `CalcRopes`.
##
## Ropes were plain beams: 131 corpus files declare them, and the rope key did nothing.
##
## The oracle is upstream's code, rule by rule, on small rigs in a `RorWorld`, the roping vehicle
## held still:
## - the toggle takes the nearest ropable nearer the rope's root than its length (1.5 m), not the
##   first listed, and not one beyond it;
## - locked to a held load, the end node sits exactly on the ropable, step after step;
## - locked to a free load under gravity, the load hangs at the rope's length: the end node's force
##   is the ropable's (upstream moves it in `CalcRopes`);
## - locked, the two vehicles are one island at any distance;
## - a ropable without multilock takes one rope, with it any number; toggled again every rope lets
##   go and gives its ropable back;
## - unlike a tie, a rope takes its own vehicle's ropables: upstream's search has no self test;
## - a respawn lets go.

const SUBSTEP: float = 1.0 / 2000.0
const LENGTH: float = 1.5
const TIER: String = """tier
globals
300, 0, tracks/semi
nodes
0, 0.0, 0.0, 0.0
1, 1.0, 0.0, 0.0
2, 0.5, 1.0, 0.0
3, 0.5, 1.0, -0.6
4, 0.5, -0.5, 0.0
beams
0, 1
1, 2
0, 2
0, 3
ropes
%s
ropables
%s
end"""
const LOAD: String = """load
globals
30, 0, tracks/semi
nodes
0, 0.5, 1.0, 1.0
1, 0.5, 1.0, 1.3
2, 1.5, 1.0, 2.5
beams
0, 1
1, 2
0, 2
ropables
%s
end"""
const ONE_ROPE: String = "2, 4"


static func meta() -> Dictionary:
    return {
        "name": "a_rope_rides_on_the_nearest_ropable",
        "proves": "ropes lock their end node to the nearest free ropable within their length, ride on it, hand it their force, join its island and let go, with multilock, own ropables and respawn as upstream",
        "builds_on": [],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "every rule in the header exactly: nearest ropable, the end node on a held ropable exactly, a hung load within 2 cm of 1.5 m after 3 s, one island, multilock, own ropable, respawn",
        "why": "131 corpus files declare ropes and they were plain beams: nothing could be roped.",
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    # Nearest, ride, island, let go. The load's ropables are listed 1.3 m, 1.0 m, 2.3 m from the root.
    var pair: Array = _pair(ONE_ROPE, "", "1\n0\n2", true)
    var world: RorWorld = pair[0]
    var tier: RorSolver = pair[1]
    var load: RorSolver = pair[2]
    if tier.rope_count() != 1:
        return fail("the ropes row made %d ropes, not 1" % tier.rope_count())
    world.toggle_ropes(tier, -1)
    if tier.rope_ropable(0) != 1 or tier.rope_locked_to_self(0):
        return fail("the toggle locked the rope to ropable %d; the load's second, 1.0 m away, is nearest" % tier.rope_ropable(0))
    for i: int in 50:
        world.step(SUBSTEP, 1)
    var off: float = tier.get_node_position(4).distance_to(load.get_node_position(0))
    if off != 0.0:
        return fail("locked to a held ropable, the end node is %.7f m off it after 50 substeps" % off, off)
    for node: int in load.node_count():
        load.set_node_position(node, load.get_node_position(node) + Vector3(50.0, 0.0, 0.0))
    if not world.shares_island(0, 1, SUBSTEP, 1):
        return fail("roped together 50 m apart, the two vehicles are not one island")
    world.toggle_ropes(tier, -1)
    if tier.rope_ropable(0) != -1:
        return fail("toggled again, the rope is still on ropable %d" % tier.rope_ropable(0))
    var report: String = "nearest ropable, the end node exactly on it, one island, let go"

    # Under gravity a free load hangs from the rope at its length.
    pair = _pair(ONE_ROPE, "", "0", false)
    world = pair[0]
    tier = pair[1]
    load = pair[2]
    load.set_gravity(Vector3(0.0, -9.81, 0.0))
    world.toggle_ropes(tier, -1)
    world.step(SUBSTEP, 6000)
    var hang: float = tier.get_node_position(2).distance_to(load.get_node_position(0))
    if absf(hang - LENGTH) > 0.02:
        return fail("after 3 s under gravity the load hangs %.3f m from the rope's root, not at its %.1f m" % [hang, LENGTH], hang)
    report += "; a load hangs at %.3f m" % hang

    # Multilock: two ropes, the 1.0 m ropable takes one unless it is multilock; let go and relocked,
    # the first gets it back.
    var two: String = ONE_ROPE + "\n" + ONE_ROPE
    pair = _pair(two, "", "0\n1", true)
    world = pair[0]
    tier = pair[1]
    world.toggle_ropes(tier, -1)
    if tier.rope_ropable(0) != 0 or tier.rope_ropable(1) != 1:
        return fail("two ropes on a single-lock ropable took %d and %d, not 0 then 1" % [tier.rope_ropable(0), tier.rope_ropable(1)])
    world.toggle_ropes(tier, -1)
    world.toggle_ropes(tier, -1)
    if tier.rope_ropable(0) != 0:
        return fail("let go and relocked, the first rope took ropable %d: the ropable was not given back" % tier.rope_ropable(0))
    pair = _pair(two, "", "0, -1, 1\n1", true)
    world = pair[0]
    tier = pair[1]
    world.toggle_ropes(tier, -1)
    if tier.rope_ropable(0) != 0 or tier.rope_ropable(1) != 0:
        return fail("two ropes on a multilock ropable took %d and %d, not both 0" % [tier.rope_ropable(0), tier.rope_ropable(1)])

    # Its own ropable, 0.6 m from the root, is taken, and the end node rides on it.
    pair = _pair(ONE_ROPE, "3", "0", true)
    world = pair[0]
    tier = pair[1]
    world.toggle_ropes(tier, -1)
    world.step(SUBSTEP, 10)
    if not tier.rope_locked_to_self(0) or tier.get_node_position(4) != tier.get_node_position(3):
        return fail("the rope did not ride on its own ropable 0.6 m away (ropable %d, end node %s)" % [tier.rope_ropable(0), tier.get_node_position(4)])

    # A respawn lets go.
    var truck: TruckParser = TruckParser.new()
    truck.parse_text(TIER % [ONE_ROPE, "3"])
    RigBuilder.place(tier, truck, Vector3.ZERO, 0.0, 0.15)
    if tier.rope_ropable(0) != -1:
        return fail("respawned, the rope is still on ropable %d" % tier.rope_ropable(0))
    return ok(report + "; multilock, own ropable and respawn as upstream", hang)


## A tier (its `ropes` and `ropables` rows) and a load (its `ropables` rows) in one world.
func _pair(ropes: String, own: String, ropables: String, load_held: bool) -> Array:
    var world: RorWorld = RorWorld.new()
    var tier: RorSolver = _build(TIER % [ropes, own], true)
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
