extends GateBase
## Two vehicles meet, push each other by Newton's third law, and leave each other alone when apart.
##
## Each `RorSolver` knew only its own nodes, so splitscreen's two trucks drove through each other.
## `RorWorld` steps several actors together: it groups them into islands from their bounds and the
## causality bound, steps lone actors on their own workers, and steps an island of several in
## lockstep with upstream's inter-actor contact (`ResolveInterActorCollisions`) after every substep.
##
## Four claims, three of them against laws rather than numbers:
##
## - **Islands follow the bound.** Two trucks 200 m apart are two islands; 6 m apart, one.
## - **Lockstep changes nothing when nothing touches.** Two trucks 3 m apart share an island and
##   step in lockstep; their nodes must equal, to the bit, the same two trucks stepped alone.
## - **Contact obeys the third law.** In free space — no gravity, no ground, no drag — truck A is
##   thrown at a resting truck B. Every contact force goes to a node and comes back off a triangle's
##   corners, so the pair's total momentum is conserved; and B, struck, must take up a real share
##   of it.
## - **The control**: the same throw with each truck stepped on its own. B gets nothing, so a gate
##   that saw momentum moved without contact would fail here.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const SUBSTEP_HZ: float = 2000.0
const CHUNK: int = 33
const FAR_M: float = 200.0
const NEAR_M: float = 6.0
const SIDE_BY_SIDE_M: float = 3.0
const QUIET_FRAMES: int = 90
## The throw: A's centre starts this far behind B's, every node of A moving at this speed.
const GAP_M: float = 9.0
const THROW_MS: float = 8.0
const THROW_FRAMES: int = 90
## Momentum the struck truck must end with, as a share of what was thrown at it. A head-on hit
## between equal masses hands over between a half and all of it.
const MIN_TRANSFER: float = 0.25
## Momentum the pair may gain or lose overall: float sums over two thousand forces a substep. A
## contact that drops one corner's share of the force — the third law broken once — drifts 1.2%.
const MAX_MOMENTUM_DRIFT: float = 0.001


static func meta() -> Dictionary:
    return {
        "name": "two_vehicles_collide",
        "proves": "trucks 200 m apart are two islands and 6 m apart one; lockstep without contact is bit-equal to stepping alone; a truck thrown at another in free space hands over at least %.0f%% of its momentum with the total conserved, and none without the world" % (MIN_TRANSFER * 100.0),
        "builds_on": ["no_node_outruns_the_speed_limit", "the_solver_is_deterministic"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "islands 2 then 1; lockstep positions bit-equal; transfer >= %.0f%%, total momentum"
            % (MIN_TRANSFER * 100.0) + " within %.1f%%; control transfer under 1%%"
            % (MAX_MOMENTUM_DRIFT * 100.0)
        ),
        "why": (
            "each solver knew only its own nodes, so two vehicles in one window drove through"
            + " each other; contact has to obey the third law, and stepping actors together must"
            + " not change an actor that touches nothing."
        ),
        "budget_s": 120.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var dt: float = 1.0 / SUBSTEP_HZ

    # Islands.
    for case: Array in [[FAR_M, false], [NEAR_M, true]]:
        var pair: Array[Dictionary] = _pair(mod_dir, case[0] as float, true)
        var world: RorWorld = _world(pair)
        if world.shares_island(0, 1, dt, CHUNK) != (case[1] as bool):
            return fail("trucks %.0f m apart %s one island" % [
                case[0], "are not" if case[1] else "are"])

    # Lockstep without contact, against stepping alone.
    var together: Array[Dictionary] = _pair(mod_dir, SIDE_BY_SIDE_M, true)
    var alone: Array[Dictionary] = _pair(mod_dir, SIDE_BY_SIDE_M, true)
    var world: RorWorld = _world(together)
    var locked: int = 0
    for _f: int in QUIET_FRAMES:
        world.step(dt, CHUNK)
        locked += world.last_lockstep_count()
        if world.last_contact_count() != 0:
            return fail("two trucks %.0f m apart touched" % SIDE_BY_SIDE_M)
        for entry: Dictionary in alone:
            (entry["solver"] as RefCounted).step(dt, CHUNK)
    if locked == 0:
        return fail("trucks %.0f m apart never shared an island: lockstep was not tested" % SIDE_BY_SIDE_M)
    for i: int in 2:
        var a: PackedVector3Array = (together[i]["solver"] as RefCounted).get_positions()
        var b: PackedVector3Array = (alone[i]["solver"] as RefCounted).get_positions()
        if a != b:
            return fail("truck %d stepped in lockstep differs from the same truck stepped alone" % i)

    # The throw, with the world and without.
    var hit: Dictionary = _throw(mod_dir, true)
    var missed: Dictionary = _throw(mod_dir, false)
    var thrown: float = hit["thrown"] as float
    var transfer: float = (hit["struck"] as float) / thrown
    var drift: float = absf((hit["total"] as float) - thrown) / thrown
    var control: float = (missed["struck"] as float) / thrown
    if control > 0.01:
        return fail("without the world the struck truck still took %.1f%% of the momentum" % (control * 100.0))
    if transfer < MIN_TRANSFER:
        return fail(
            "the struck truck took %.1f%% of the momentum thrown at it (%d contacts): the"
            % [transfer * 100.0, hit["contacts"]] + " vehicles are not pushing each other",
            transfer
        )
    if drift > MAX_MOMENTUM_DRIFT:
        return fail(
            "the pair's momentum changed by %.2f%% through the collision: contact is not equal"
            % (drift * 100.0) + " and opposite",
            drift
        )
    return ok(
        "islands 2 at %.0f m, 1 at %.0f m; %d frames of lockstep bit-equal to stepping alone;"
        % [FAR_M, NEAR_M, QUIET_FRAMES]
        + " thrown at %.0f m/s: struck truck took %.1f%%, total momentum within %.3f%% (%d"
        % [THROW_MS, transfer * 100.0, drift * 100.0, hit["contacts"]]
        + " contacts); without the world %.2f%%" % (control * 100.0),
        transfer
    )


func _world(pair: Array[Dictionary]) -> RorWorld:
    var world: RorWorld = RorWorld.new()
    for entry: Dictionary in pair:
        world.add_solver(entry["solver"] as RorSolver)
    return world


## Two hero trucks side by side, `apart` metres between their centres along the first one's own
## sideways axis — read off the placed rig, not assumed — both facing the same way.
func _pair(mod_dir: String, apart: float, grounded: bool) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var side: Vector3 = Vector3.ZERO
    for i: int in 2:
        var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
        var solver: RefCounted = rig["solver"] as RefCounted
        var truck: TruckParser = rig["truck"] as TruckParser
        solver.set_ground(0.0, grounded)
        RigBuilder.place(solver, truck, side * apart * float(i), 0.0, 0.15)
        if i == 0:
            var pose: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
            side = Vector3(pose.basis.x.x, 0.0, pose.basis.x.z).normalized()
        out.append({"solver": solver, "truck": truck})
    return out


## A thrown at B along A's own forward in free space. Returns the momentum thrown, the struck
## truck's along the throw afterwards, the pair's total along it, and the contacts resolved.
func _throw(mod_dir: String, with_world: bool) -> Dictionary:
    var pair: Array[Dictionary] = _pair(mod_dir, 0.0, false)
    var a: RefCounted = pair[0]["solver"] as RefCounted
    var b: RefCounted = pair[1]["solver"] as RefCounted
    var truck: TruckParser = pair[0]["truck"] as TruckParser
    var pose: Transform3D = ActorFrame.of(a.get_positions(), truck.camera_nodes)
    var forward: Vector3 = Vector3(-pose.basis.z.x, 0.0, -pose.basis.z.z).normalized()
    for solver: RefCounted in [a, b]:
        solver.set_gravity(Vector3.ZERO)
        solver.set_air_drag(0.05, false)
        solver.set_fuselage_drag(0, 0.0, false)
    RigBuilder.place(b, truck, forward * GAP_M, 0.0, 0.15)
    for node: int in a.node_count():
        a.set_node_velocity(node, forward * THROW_MS)
    var thrown: float = _momentum(a, forward)
    var world: RorWorld = _world(pair)
    var contacts: int = 0
    var dt: float = 1.0 / SUBSTEP_HZ
    for _f: int in THROW_FRAMES:
        if with_world:
            world.step(dt, CHUNK)
            contacts += world.last_contact_count()
        else:
            a.step(dt, CHUNK)
            b.step(dt, CHUNK)
    return {
        "thrown": thrown, "struck": _momentum(b, forward),
        "total": _momentum(a, forward) + _momentum(b, forward), "contacts": contacts,
    }


func _momentum(solver: RefCounted, along: Vector3) -> float:
    var total: float = 0.0
    for node: int in solver.node_count():
        total += solver.get_node_mass(node) * solver.get_node_velocity(node).dot(along)
    return total
