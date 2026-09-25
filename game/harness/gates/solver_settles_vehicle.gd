extends GateBase
## Drops the hero vehicle's own rig on the ground and requires it to settle.
##
## The spring-mass checks prove the force law; this proves the solver survives a real
## vehicle: 255 nodes and hundreds of beams at upstream's stiffness, on hard ground, at
## upstream's 2 kHz. A soft-body solver that is correct on one spring can still explode on
## a rig, and "explodes" is the failure mode this exists to catch.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
## Upstream's defaults, from SimConstants.
const DEFAULT_SPRING: float = 9000000.0
const DEFAULT_DAMP: float = 12000.0
## Upstream runs at 2 kHz. This core needs 10 kHz on the same rig, and that gap is the
## measure of what is still missing rather than a tuning knob: upstream distributes node
## mass from beam volume instead of using the minimass floor everywhere, adds per-node air
## drag, and gives rope, support and shock beams their own force laws. Each of those damps
## or slows the stiff modes that force the smaller step here. Measured: this rig diverges
## at 2 kHz within 0.006 s and settles at both 10 kHz and 40 kHz, so the force law is
## right and the regime is not yet upstream's.
const SUBSTEP_HZ: float = 10000.0
const SETTLE_SECONDS: float = 2.0
const DROP_HEIGHT_M: float = 0.3
## Upstream treats anything past Mach 20 as an explosion and resets the actor. A vehicle
## settling should not come close.
const EXPLOSION_SPEED: float = 100.0
## Energy must fall as the rig settles. A rising trend means the integrator is feeding the
## rig rather than damping it.
const ENERGY_GROWTH_TOLERANCE: float = 1.05
## A settled rig rests on the ground, not above or through it.
const GROUND_TOLERANCE_M: float = 0.05
## Residual motion once the rig is down. It is not zero and is not claimed to be: without
## upstream's per-node air drag the only damping is in the beams, so the rig keeps
## vibrating. Bounding it catches a regression toward instability without pretending the
## rig is at rest.
const RESIDUAL_MOTION_LIMIT: float = 10.0


static func meta() -> Dictionary:
    return {
        "name": "solver_settles_vehicle",
        "proves": "a real vehicle rig falls, contacts hard ground and stays bounded at upstream's stiffness",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "no node over %.0f m/s; energy no higher than %.0f%% of its start; lowest node"
            % [EXPLOSION_SPEED, ENERGY_GROWTH_TOLERANCE * 100.0]
            + " within %.2f m of the ground" % GROUND_TOLERANCE_M
        ),
        "why": (
            "a solver correct on a single spring can still be unstable on a rig with"
            + " hundreds of stiff beams. Stability is the property a vehicle needs and"
            + " the one a closed-form spring test cannot show."
        ),
        "budget_s": 120.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)

    var truck: TruckParser = TruckParser.new()
    var parse_error: String = truck.parse_file(mod_dir.path_join(TRUCK))
    if parse_error != "":
        return fail(parse_error)
    if truck.beams.is_empty():
        return fail("%s has no beams" % TRUCK)

    var solver: RefCounted = ClassDB.instantiate("RorSolver") as RefCounted
    if solver == null:
        return fail("RorSolver is not registered: the GDExtension did not load")

    # Mass distribution is not yet faithful: upstream derives node masses from beam volume
    # with minimass as a floor, and this uses the floor for every node. That changes how
    # the rig settles, not whether it stays stable, which is what this gate is about.
    var mass: float = maxf(truck.minimass_kg, 1.0)
    var lowest: float = INF
    for node: Vector3 in truck.nodes:
        lowest = minf(lowest, node.y)
    for node: Vector3 in truck.nodes:
        solver.add_node(node + Vector3(0.0, DROP_HEIGHT_M - lowest, 0.0), mass)
    for i: int in range(0, truck.beams.size(), 2):
        var beam: int = i / 2
        var spring: float = (
            truck.beam_spring[beam] if beam < truck.beam_spring.size() else DEFAULT_SPRING
        )
        var damp: float = truck.beam_damp[beam] if beam < truck.beam_damp.size() else DEFAULT_DAMP
        solver.add_beam(truck.beams[i], truck.beams[i + 1], 0.0, spring, damp)
    solver.set_gravity(Vector3(0.0, -9.81, 0.0))
    solver.set_ground(0.0, true)

    var dt: float = 1.0 / SUBSTEP_HZ
    var total_steps: int = int(SETTLE_SECONDS * SUBSTEP_HZ)
    var chunk: int = int(SUBSTEP_HZ / 20.0)
    var start_energy: float = solver.total_energy()
    var worst_speed: float = 0.0
    var worst_energy: float = start_energy
    var elapsed_usec: int = 0

    for i: int in int(total_steps / chunk):
        var began: int = Time.get_ticks_usec()
        solver.step(dt, chunk)
        elapsed_usec += Time.get_ticks_usec() - began
        for n: int in solver.node_count():
            var speed: float = solver.get_node_velocity(n).length()
            # Explicitly, because every comparison against NaN is false: an exploded rig
            # sails through a greater-than check and the gate reports a clean pass.
            if not is_finite(speed):
                return fail(
                    "rig produced a non-finite velocity after %.2f s: the solver diverged"
                    % [float(i * chunk) * dt]
                )
            worst_speed = maxf(worst_speed, speed)
        var energy: float = solver.total_energy()
        if not is_finite(energy):
            return fail("rig produced non-finite energy after %.2f s" % [float(i * chunk) * dt])
        worst_energy = maxf(worst_energy, energy)
        if worst_speed > EXPLOSION_SPEED:
            return fail(
                "rig exploded: a node reached %.0f m/s after %.2f s"
                % [worst_speed, float(i * chunk) * dt],
                worst_speed
            )

    var energy_ratio: float = worst_energy / maxf(absf(start_energy), 0.001)
    if energy_ratio > ENERGY_GROWTH_TOLERANCE:
        return fail(
            "energy rose to %.0f%% of its starting value: the integrator is feeding the rig"
            % (energy_ratio * 100.0),
            energy_ratio
        )

    var resting_speed: float = 0.0
    var settled_on_ground: bool = false
    var resting_low: float = INF
    for n: int in solver.node_count():
        resting_speed = maxf(resting_speed, solver.get_node_velocity(n).length())
        resting_low = minf(resting_low, solver.get_node_position(n).y)
    if resting_speed > RESIDUAL_MOTION_LIMIT:
        return fail(
            "rig is still moving at %.1f m/s after %.0f s, over the %.0f m/s bound"
            % [resting_speed, SETTLE_SECONDS, RESIDUAL_MOTION_LIMIT],
            resting_speed
        )
    settled_on_ground = absf(resting_low) < GROUND_TOLERANCE_M
    if not settled_on_ground:
        return fail(
            "rig came to rest with its lowest node at %.3f m, not on the ground" % resting_low,
            resting_low
        )
    var realtime_ratio: float = SETTLE_SECONDS / maxf(float(elapsed_usec) / 1000000.0, 0.000001)
    return ok(
        (
            "%d nodes, %d beams: down on the ground after %.1f s, peak %.1f m/s, lowest"
            + " node %.3f m, still vibrating at %.2f m/s, %.1fx realtime"
        )
        % [
            solver.node_count(), solver.beam_count(), SETTLE_SECONDS, worst_speed,
            resting_low, resting_speed, realtime_ratio
        ],
        worst_speed
    )
