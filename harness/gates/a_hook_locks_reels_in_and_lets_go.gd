extends GateBase
## A hook (a node with option `h`) locks to the nearest node in range on another vehicle, reels its
## rope in, locks, pulls the other vehicle with it, and lets go again, by upstream's `hookToggle`
## and `CalcHooks`; lock groups, `selflock` and auto-lock behave as upstream's do, and a respawn lets
## every hook go.
##
## Hooks were read nowhere: 117 corpus files declare them, and every trailer and load waits on one.
##
## The oracle is upstream's code, rule by rule, on small rigs in a `RorWorld`, the hooking vehicle
## held still in free space:
## - the toggle takes the nearest node within the hook's range (0.4 m by default), not one further;
## - each substep the rope shortens by 0.00025 m (`HOOK_SPEED_DEFAULT` times `speedcoef`) until it is
##   no longer than that, then is 0.001 m and locked, and the other vehicle has come with it;
## - locked, the two vehicles are one island at any distance; toggled again, it lets go;
## - a hook with a lock group takes only nodes of that group; a node in group 9999 is never taken;
## - without `selflock` a hook ignores its own vehicle's nodes, with it it takes them;
## - an `autolock` hook locks by itself on the world's step, and let go with the auto-lock key it
##   waits its `timer` (5 s, 10000 substeps) before trying again;
## - a respawn lets go.

const SUBSTEP: float = 1.0 / 2000.0
const LOCK_SPEED: float = 0.00025
const HOOKER: String = """hooker
globals
300, 0, tracks/semi
nodes
0, 0.0, 0.0, 0.0
1, 1.0, 0.0, 0.0
2, 0.5, 1.0, 0.0, h
3, 0.5, 1.0, 0.35
beams
0, 1
1, 2
0, 2
0, 3
hooks
2%s
end"""
const LOAD: String = """load
globals
30, 0, tracks/semi
nodes
0, 0.5, 1.3, 0.0
1, 0.5, 1.38, 0.0
2, 1.5, 1.3, 0.0
beams
0, 1
1, 2
0, 2
%s
end"""


static func meta() -> Dictionary:
    return {
        "name": "a_hook_locks_reels_in_and_lets_go",
        "proves": "hooks lock to the nearest node in range, reel in by upstream's speed, lock, pull the other vehicle, join its island and let go, with lock groups, selflock, autolock and respawn as upstream",
        "builds_on": ["islands_step_in_parallel_as_they_would_in_turn"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "every rule in the header exactly: nearest node, 0.00025 m a substep, 0.001 m locked, the load within 2 cm, one island, lock groups, selflock, autolock timer 10000 substeps, respawn",
        "why": "117 corpus files declare hooks and none was read: no trailer or load could be hitched.",
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    # Lock, reel, pull, island, let go.
    var pair: Array = _pair("", "")
    var world: RorWorld = pair[0]
    var hooker: RorSolver = pair[1]
    var load: RorSolver = pair[2]
    if hooker.hook_count() != 1:
        return fail("the `h` node made %d hooks, not 1" % hooker.hook_count())
    world.toggle_hooks(hooker, 2, -1)
    if hooker.hook_state(0) != "prelock" or hooker.hook_lock_node(0) != 0:
        return fail("the toggle left the hook %s on node %d; the load's node 0 is nearest at 0.3 m" % [hooker.hook_state(0), hooker.hook_lock_node(0)])
    var start: float = hooker.hook_length(0)
    for i: int in 10:
        world.step(SUBSTEP, 1)
    var reeled: float = start - hooker.hook_length(0)
    if absf(reeled - 10.0 * LOCK_SPEED) > 1e-6:
        return fail("10 substeps reeled the rope in %.7f m, upstream's speed gives %.7f" % [reeled, 10.0 * LOCK_SPEED], reeled)
    var substeps: int = 10
    while hooker.hook_state(0) == "prelock" and substeps < 4000:
        world.step(SUBSTEP, 1)
        substeps += 1
    if hooker.hook_state(0) != "locked" or absf(hooker.hook_length(0) - 0.001) > 1e-9:
        return fail("after %d substeps the hook is %s at %.4f m, not locked at 0.001 m" % [substeps, hooker.hook_state(0), hooker.hook_length(0)])
    for i: int in 400:
        world.step(SUBSTEP, 1)
    var gap: float = hooker.get_node_position(2).distance_to(load.get_node_position(0))
    if gap > 0.02:
        return fail("locked, the load's node is still %.3f m from the hook: the rope did not pull" % gap, gap)
    # Far apart, only the hook can join them: 50 m is past any contact reach in one substep.
    for node: int in load.node_count():
        load.set_node_position(node, load.get_node_position(node) + Vector3(50.0, 0.0, 0.0))
    if not world.shares_island(0, 1, SUBSTEP, 1):
        return fail("hooked together 50 m apart, the two vehicles are not one island")
    world.toggle_hooks(hooker, 2, -1)
    if hooker.hook_state(0) != "unlocked":
        return fail("toggled again, the hook is %s" % hooker.hook_state(0))
    var report: String = "locked to the nearest node, %.4f m reeled in 10 substeps, locked after %d, load within %.3f m, one island, let go" % [reeled, substeps, gap]

    # Lock groups: group 5 takes only the load's node 2; 9999 is never taken.
    pair = _pair(", lockgroup, 5, hookrange, 1.2", "lockgroups\n5, 2\n9999, 0")
    world = pair[0]
    hooker = pair[1]
    world.toggle_hooks(hooker, 2, -1)
    if hooker.hook_lock_node(0) != 2:
        return fail("a lock group 5 hook took node %d, not the group's node 2" % hooker.hook_lock_node(0))
    pair = _pair("", "lockgroups\n9999, 0")
    world = pair[0]
    hooker = pair[1]
    world.toggle_hooks(hooker, 2, -1)
    if hooker.hook_lock_node(0) != 1:
        return fail("with node 0 closed (9999) the hook took node %d, not the next nearest, 1" % hooker.hook_lock_node(0))

    # Self-lock: node 3 of its own is 0.35 m away.
    var alone: RorSolver = _build(HOOKER % "", true)
    alone.toggle_hooks(2, -1)
    if alone.hook_state(0) != "unlocked":
        return fail("without selflock the hook locked to its own node %d" % alone.hook_lock_node(0))
    alone = _build(HOOKER % ", selflock", true)
    alone.toggle_hooks(2, -1)
    if not alone.hook_locked_to_self(0) or alone.hook_lock_node(0) != 3:
        return fail("with selflock the hook did not take its own node 3 (%s, %d)" % [alone.hook_state(0), alone.hook_lock_node(0)])

    # Auto-lock and its timer.
    pair = _pair(", autolock", "")
    world = pair[0]
    hooker = pair[1]
    world.step(SUBSTEP, 1)
    if hooker.hook_state(0) == "unlocked":
        return fail("an autolock hook did not lock by itself on the world's step")
    world.toggle_hooks(hooker, 1, -2)
    if hooker.hook_state(0) != "unlocked":
        return fail("the auto-lock key did not let the autolock hook go")
    world.step(SUBSTEP, 9998)
    if hooker.hook_state(0) != "unlocked":
        return fail("the autolock hook relocked inside its 5 s timer")
    world.step(SUBSTEP, 10)
    world.step(SUBSTEP, 1)
    if hooker.hook_state(0) == "unlocked":
        return fail("the autolock hook did not relock once its timer had run out")

    # A respawn lets go.
    var truck: TruckParser = TruckParser.new()
    truck.parse_text(HOOKER % "")
    RigBuilder.place(hooker, truck, Vector3.ZERO, 0.0, 0.15)
    if hooker.hook_state(0) != "unlocked":
        return fail("respawned, the hook is still %s" % hooker.hook_state(0))
    return ok(report + "; lock groups, selflock, autolock timer and respawn as upstream", 0)


## A hooker (its `hooks` row given `options`) and a load (with `extra` rows) in one world.
func _pair(options: String, extra: String) -> Array:
    var world: RorWorld = RorWorld.new()
    var hooker: RorSolver = _build(HOOKER % options, true)
    var load: RorSolver = _build(LOAD % extra, false)
    world.add_solver(hooker)
    world.add_solver(load)
    return [world, hooker, load]


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
