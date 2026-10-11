extends GateBase
## Separate islands of colliding vehicles step at the same time, on separate cores, and come out
## exactly as they would have stepped one after another.
##
## `RorWorld` steps a lone vehicle on its own worker, but an island of several — vehicles close
## enough to touch — stepped in lockstep on the calling thread, so two pairs of colliding trucks
## cost twice one pair. Now each island's lockstep runs on its first member's worker. PLAN's gate
## for it (Parallelism, "SMP across islands"): N islands on N workers bit-equal to the same N
## stepped serially, and the wall time of N under 1.5x one.
##
## The oracle for the first half is the serial run itself: the world with parallel stepping off
## steps every island on the calling thread, in order, before `step` returns, which is what it did
## before this. Four pairs of hero trucks, 200 m apart, each pair a truck thrown at 8 m/s into the
## other so contact is resolved every frame of the measurement; every node of every truck has to be
## bit-equal across the two runs. Islands share nothing, so any difference is a race.
##
## The second half is a wall clock: a frame of four islands against a frame of one, medians of
## frames after warm-up, each frame timed to the moment every solver has finished. This machine
## has 8 performance cores; four islands need four.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const SUBSTEP_HZ: float = 2000.0
const CHUNK: int = 33
const ISLANDS: int = 4
const APART_M: float = 200.0
const GAP_M: float = 9.0
const THROW_MS: float = 8.0
const FRAMES: int = 90
const WARM_FRAMES: int = 10
const TIMED_FRAMES: int = 40
const MAX_RATIO: float = 1.5


static func meta() -> Dictionary:
    return {
        "name": "islands_step_in_parallel_as_they_would_in_turn",
        "proves": "islands of colliding vehicles step on separate workers bit-equal to stepping them one after another, and %d islands cost under %.1fx one" % [ISLANDS, MAX_RATIO],
        "builds_on": ["two_vehicles_collide", "the_solver_steps_on_its_own_thread"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "%d islands x 2 trucks, %d frames: every node bit-equal parallel vs serial; median frame of %d islands under %.1fx one" % [ISLANDS, FRAMES, ISLANDS, MAX_RATIO],
        "why": "lockstep islands ran serially on the caller, so every pair of touching vehicles added its whole cost to the frame: splitscreen, traffic and 64 players all need them in parallel.",
        "budget_s": 120.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)

    var parallel: Dictionary = _crash(mod_dir, true)
    var serial: Dictionary = _crash(mod_dir, false)
    if (parallel["islands"] as int) != ISLANDS or (parallel["lockstep"] as int) != ISLANDS * 2:
        return fail("the world made %d islands with %d trucks in lockstep, not %d and %d" % [
            parallel["islands"], parallel["lockstep"], ISLANDS, ISLANDS * 2])
    if (parallel["contacts"] as int) == 0:
        return fail("no contact was resolved: the pairs did not collide, so nothing was tested")
    var states_a: Array = parallel["states"] as Array
    var states_b: Array = serial["states"] as Array
    for i: int in states_a.size():
        if states_a[i] != states_b[i]:
            return fail("truck %d differs between the parallel and the serial run: a race" % i)
    if (parallel["contacts"] as int) != (serial["contacts"] as int):
        return fail("contacts %d parallel, %d serial" % [parallel["contacts"], serial["contacts"]])

    var one: float = _frame_ms(mod_dir, 1, true)
    var many: float = _frame_ms(mod_dir, ISLANDS, true)
    var ratio: float = many / one
    if ratio > MAX_RATIO:
        return fail("a frame of %d islands took %.2f ms against %.2f for one: %.2fx, over %.1fx" % [
            ISLANDS, many, one, ratio, MAX_RATIO], ratio)
    return ok(
        "%d islands, %d trucks bit-equal over %d frames (%d contacts); frame %.2f ms for %d islands"
        % [ISLANDS, ISLANDS * 2, FRAMES, parallel["contacts"], many, ISLANDS]
        + " against %.2f for one: %.2fx" % [one, ratio],
        ratio
    )


## Four thrown pairs stepped for `FRAMES` frames. Returns each truck's final state as bytes, and
## what the world counted.
func _crash(mod_dir: String, parallel: bool) -> Dictionary:
    var world: RorWorld = _islands(mod_dir, ISLANDS, true)
    world.set_parallel(parallel)
    var contacts: int = 0
    var islands: int = 0
    var lockstep: int = 0
    var states: Array[PackedByteArray] = []
    for f: int in FRAMES:
        world.step(1.0 / SUBSTEP_HZ, CHUNK)
        if f == FRAMES - 1:
            states = _states()
        contacts += world.last_contact_count()
        islands = world.last_island_count()
        lockstep = world.last_lockstep_count()
    return {"states": states, "contacts": contacts, "islands": islands, "lockstep": lockstep}


## Every truck's positions and velocities as bytes, read the way a caller reads one vehicle: each
## solver asked on its own, straight after the world's step, struck trucks before the throwers. A
## struck truck's own solver has to wait for the island its thrower's worker is stepping.
func _states() -> Array[PackedByteArray]:
    var order: Array[int] = []
    for i: int in _solvers.size():
        if i % 2 == 1:
            order.append(i)
    for i: int in _solvers.size():
        if i % 2 == 0:
            order.append(i)
    var states: Array[PackedByteArray] = []
    states.resize(_solvers.size())
    for i: int in order:
        var solver: RorSolver = _solvers[i]
        var state: PackedByteArray = solver.get_positions().to_byte_array()
        var velocities: PackedVector3Array = PackedVector3Array()
        for node: int in solver.node_count():
            velocities.append(solver.get_node_velocity(node))
        state.append_array(velocities.to_byte_array())
        states[i] = state
    return states


## Median wall time of a frame of `count` quiet islands, to the moment every solver is done.
func _frame_ms(mod_dir: String, count: int, parallel: bool) -> float:
    var world: RorWorld = _islands(mod_dir, count, false)
    world.set_parallel(parallel)
    var times: Array[float] = []
    for f: int in WARM_FRAMES + TIMED_FRAMES:
        var began: int = Time.get_ticks_usec()
        world.step(1.0 / SUBSTEP_HZ, CHUNK)
        world.last_contact_count()
        if f >= WARM_FRAMES:
            times.append(float(Time.get_ticks_usec() - began) / 1000.0)
    times.sort()
    return times[times.size() / 2]


var _solvers: Array[RorSolver] = []


## `count` pairs of hero trucks in free space, `APART_M` apart along the first truck's side; in
## each pair one stands `GAP_M` ahead of the other, and with `thrown` the one behind is moving at
## `THROW_MS` towards it.
func _islands(mod_dir: String, count: int, thrown: bool) -> RorWorld:
    var world: RorWorld = RorWorld.new()
    _solvers.clear()
    var side: Vector3 = Vector3.ZERO
    var forward: Vector3 = Vector3.ZERO
    for k: int in count:
        for i: int in 2:
            var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
            var solver: RorSolver = rig["solver"] as RorSolver
            var truck: TruckParser = rig["truck"] as TruckParser
            solver.set_ground(0.0, false)
            solver.set_gravity(Vector3.ZERO)
            RigBuilder.place(solver, truck, side * APART_M * float(k) + forward * GAP_M * float(i), 0.0, 0.15)
            if k == 0 and i == 0:
                var pose: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
                side = Vector3(pose.basis.x.x, 0.0, pose.basis.x.z).normalized()
                forward = Vector3(-pose.basis.z.x, 0.0, -pose.basis.z.z).normalized()
            if thrown and i == 0:
                for node: int in solver.node_count():
                    solver.set_node_velocity(node, forward * THROW_MS)
            world.add_solver(solver)
            _solvers.append(solver)
    return world
