extends GateBase
## No node moves further in one substep than the speed limit allows, even when it is thrown far
## past that limit, and a drive that never comes near the limit is untouched by it.
##
## PLAN §0.12's first prerequisite. The causality bound there — two actors further apart than
## `2 * v_max * dt` cannot touch this substep — is a theorem only if no node can exceed v_max, and
## the solver had no ceiling: a bad collision launches nodes far above any vehicle's top speed,
## which is why `drive_route.gd` keeps an explosion threshold at all. A bound that holds except
## when physics misbehaves fails exactly when it matters, and a contact missed that way does not
## reproduce.
##
## Three runs of the hero, each from a fresh solver:
##
## - **Thrown.** Settled, then a handful of nodes are given eight times the limit — a stand-in for
##   the bad collision — and the rig is stepped one substep at a time. Every node's travel in every
##   substep has to be inside `limit * dt`, and every node's speed inside the limit.
## - **The control, in the same run.** The same throw with the limit lifted to infinity. Some
##   node's travel in some substep has to exceed `limit * dt`, or the measurement could not have
##   seen a violation and the first run proves nothing.
## - **Untouched.** Settle, full throttle into a wall, brakes: the drive and crash
##   `the_solver_is_deterministic` uses. The limit's own counter has to read zero, which says the
##   clamp changed nothing — not approximately nothing — on a run a person would call normal.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const SUBSTEP_HZ: float = 2000.0
const FRAME_HZ: float = 60.0
const SETTLE_FRAMES: int = 30
## PLAN §0.12's v_max, which is also the solver's default. Read back from the solver and compared,
## so a changed default is a finding here rather than a silently moved bound.
const LIMIT: float = 1000.0 / 3.6
## The throw: every `THROW_STRIDE`th node, sent sideways and up at this multiple of the limit.
const THROW_STRIDE: int = 25
const THROW_FACTOR: float = 8.0
const THROWN_SUBSTEPS: int = 400
## Positions are 32-bit floats. Within a few hundred metres of the origin one is quantised to
## 3e-5 m at worst, and a travel is a difference of two of them; the allowance is that and no more.
const POSITION_ULP_M: float = 6.0e-5
## The drive: frames of full throttle, then brakes, with a wall across the road ahead.
const DRIVE_FRAMES: int = 420
const BRAKE_FROM: int = 360
const WALL_AHEAD_M: float = 45.0
const WALL_HALF: Vector3 = Vector3(6.0, 1.5, 0.6)


static func meta() -> Dictionary:
    return {
        "name": "no_node_outruns_the_speed_limit",
        "proves": "nodes thrown at %.0fx the %.1f m/s limit never travel more than limit * dt in a substep, the same throw with no limit does, and a drive into a wall never reaches the limit" % [THROW_FACTOR, LIMIT],
        "builds_on": ["solver_settles_vehicle"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "thrown: every node's per-substep travel <= limit * dt + %.0f um and speed <= limit;"
            % (POSITION_ULP_M * 1.0e6)
            + " unlimited control: some travel > limit * dt; drive and crash: zero limit hits"
        ),
        "why": (
            "PLAN §0.12's causality bound is derived from a node-velocity clamp that did not"
            + " exist; a bad collision launches nodes far past any vehicle's speed, so without a"
            + " clamp the bound fails exactly when physics misbehaves, and the contact it misses"
            + " does not reproduce."
        ),
        "budget_s": 90.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)

    var thrown: Dictionary = _throw(mod_dir, LIMIT)
    if (thrown["error"] as String) != "":
        return fail(thrown["error"] as String)
    var control: Dictionary = _throw(mod_dir, INF)
    if (control["error"] as String) != "":
        return fail(control["error"] as String)
    var drive: Dictionary = _drive(mod_dir)
    if (drive["error"] as String) != "":
        return fail(drive["error"] as String)

    var allowed: float = LIMIT / SUBSTEP_HZ + POSITION_ULP_M
    if absf((thrown["limit"] as float) - LIMIT) > 1.0e-3:
        return fail(
            "the solver's default limit is %.4f m/s where PLAN §0.12 states %.4f"
            % [thrown["limit"], LIMIT], thrown["limit"]
        )
    if (control["travel"] as float) <= allowed:
        return fail(
            "with no limit the throw's worst travel was %.4f m in a substep, inside the %.4f m"
            % [control["travel"], allowed]
            + " the limit allows: this measurement could not have seen a violation",
            control["travel"]
        )
    if (thrown["travel"] as float) > allowed:
        return fail(
            "a thrown node travelled %.6f m in one substep (substep %d), over the %.6f m a %.1f"
            % [thrown["travel"], thrown["at"], allowed, LIMIT] + " m/s limit allows",
            thrown["travel"]
        )
    if (thrown["speed"] as float) > LIMIT:
        return fail(
            "a thrown node reached %.4f m/s, over the %.4f m/s limit" % [thrown["speed"], LIMIT],
            thrown["speed"]
        )
    if (thrown["hits"] as int) == 0:
        return fail("the throw never reached the limit: it tested nothing", 0)
    if (drive["hits"] as int) != 0:
        return fail(
            "a drive into a wall hit the limit %d times (fastest node %.1f m/s): the clamp is"
            % [drive["hits"], drive["fastest"]] + " rewriting a normal run",
            drive["hits"]
        )
    return ok(
        "thrown at %.0f m/s: worst travel %.5f of %.5f m allowed, fastest %.2f m/s, %d cuts;"
        % [LIMIT * THROW_FACTOR, thrown["travel"], allowed, thrown["speed"], thrown["hits"]]
        + " unlimited control travelled %.4f m; drive and crash: fastest node %.1f m/s, %d"
        % [control["travel"], drive["fastest"], drive["broken"]]
        + " beams broken, 0 cuts",
        thrown["travel"]
    )


## The settled hero with a fresh solver at `limit`, or an error.
func _settled(mod_dir: String, limit: float) -> Dictionary:
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        return {"error": rig["error"]}
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    var default_limit: float = solver.speed_limit()
    solver.set_speed_limit(limit)
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.15)
    var chunk: int = int(SUBSTEP_HZ / FRAME_HZ)
    for _i: int in SETTLE_FRAMES:
        solver.step(1.0 / SUBSTEP_HZ, chunk)
    return {"error": "", "solver": solver, "truck": truck, "default_limit": default_limit}


## Throws every `THROW_STRIDE`th node and steps one substep at a time, recording the worst travel
## and speed any node reaches.
func _throw(mod_dir: String, limit: float) -> Dictionary:
    var settled: Dictionary = _settled(mod_dir, limit)
    if (settled["error"] as String) != "":
        return settled
    var solver: RefCounted = settled["solver"] as RefCounted
    var count: int = solver.node_count()
    var throw: Vector3 = Vector3(1.0, 0.6, -0.3).normalized() * LIMIT * THROW_FACTOR
    for node: int in range(0, count, THROW_STRIDE):
        solver.set_node_velocity(node, throw if node % 2 == 0 else -throw)
    var before: PackedVector3Array = solver.get_positions()
    var worst: float = 0.0
    var worst_at: int = -1
    var fastest: float = 0.0
    for substep: int in THROWN_SUBSTEPS:
        solver.step(1.0 / SUBSTEP_HZ, 1)
        var after: PackedVector3Array = solver.get_positions()
        for node: int in count:
            var travel: float = (after[node] - before[node]).length()
            if not is_finite(travel):
                return {"error": "node %d went non-finite at substep %d" % [node, substep]}
            if travel > worst:
                worst = travel
                worst_at = substep
            fastest = maxf(fastest, solver.get_node_velocity(node).length())
        before = after
    return {
        "error": "", "travel": worst, "at": worst_at, "speed": fastest,
        "hits": solver.speed_limit_hits(), "limit": settled["default_limit"],
    }


## The deterministic gate's drive and crash at the default limit: the counter and the fastest node.
func _drive(mod_dir: String) -> Dictionary:
    var settled: Dictionary = _settled(mod_dir, LIMIT)
    if (settled["error"] as String) != "":
        return settled
    var solver: RefCounted = settled["solver"] as RefCounted
    var truck: TruckParser = settled["truck"] as TruckParser
    var pose: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
    var forward: Vector3 = Vector3(-pose.basis.z.x, 0.0, -pose.basis.z.z).normalized()
    var wall_at: Vector3 = pose.origin + forward * WALL_AHEAD_M
    solver.add_obstacle_box(
        Transform3D(Basis.looking_at(-forward, Vector3.UP), Vector3(wall_at.x, WALL_HALF.y, wall_at.z)),
        WALL_HALF, 0
    )
    solver.start_engine()
    solver.set_gear_selector(1)
    var chunk: int = int(SUBSTEP_HZ / FRAME_HZ)
    var count: int = solver.node_count()
    var fastest: float = 0.0
    for frame: int in DRIVE_FRAMES:
        solver.set_throttle(0.0 if frame >= BRAKE_FROM else 1.0)
        solver.set_brake(1.0 if frame >= BRAKE_FROM else 0.0)
        solver.step(1.0 / SUBSTEP_HZ, chunk)
        for node: int in count:
            fastest = maxf(fastest, solver.get_node_velocity(node).length())
    return {
        "error": "", "hits": solver.speed_limit_hits(), "fastest": fastest,
        "broken": solver.broken_beam_count(),
    }
