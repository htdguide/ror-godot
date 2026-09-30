extends SceneTree
## Finds the lowest substep rate a rig stays stable at, and says what let go first.
##
##   godot --path game --headless --script res://harness/dev/stability_probe.gd -- <path to .truck>
##
## The point is the number, not the verdict: every change aimed at the 2 kHz gap has to move
## this, and anything that does not move it was not the cause.

const RATES: Array[float] = [1000.0, 1500.0, 2000.0, 3000.0, 4000.0, 6000.0, 10000.0]
const SECONDS: float = 2.0
const DROP_M: float = 0.02
const EXPLOSION_SPEED: float = 100.0


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    if argv.is_empty():
        printerr("usage: stability_probe.gd -- <path to .truck>")
        quit(2)
        return
    var lowest_stable: float = 0.0
    for rate: float in RATES:
        var result: Dictionary = _try(argv[0], rate)
        if (result["error"] as String) != "":
            printerr(result["error"])
            quit(1)
            return
        print(result["report"])
        if bool(result["stable"]) and lowest_stable == 0.0:
            lowest_stable = rate
    if lowest_stable == 0.0:
        print("no rate in the sweep was stable")
    else:
        print("lowest stable rate: %.0f Hz (upstream runs 2000 Hz)" % lowest_stable)
    quit(0)


func _try(path: String, rate: float) -> Dictionary:
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_file(path)
    if error != "":
        return {"error": error}
    var built: Dictionary = RigBuilder.build(truck, DROP_M)
    if (built["error"] as String) != "":
        return {"error": built["error"]}
    var solver: RefCounted = built["solver"] as RefCounted
    solver.set_ground(0.0, true)

    var dt: float = 1.0 / rate
    var steps: int = int(SECONDS * rate)
    var start_energy: float = solver.total_energy()
    var worst_energy: float = start_energy
    for step: int in steps:
        solver.step(dt, 1)
        if step % 200 != 0:
            continue
        var energy: float = solver.total_energy()
        if is_finite(energy):
            worst_energy = maxf(worst_energy, energy)
        var culprit: int = _runaway(solver)
        if culprit < 0 and is_finite(energy):
            continue
        return {
            "error": "",
            "stable": false,
            "report": "%6.0f Hz  UNSTABLE after %.4f s: %s" % [
                rate, float(step) * dt, _describe(solver, truck, culprit)],
        }
    var energy_ratio: float = worst_energy / maxf(absf(start_energy), 0.001)
    var lowest: float = INF
    var moving: float = 0.0
    for n: int in solver.node_count():
        lowest = minf(lowest, solver.get_node_position(n).y)
        moving = maxf(moving, solver.get_node_velocity(n).length())
    var stable: bool = energy_ratio <= 1.05
    return {
        "error": "",
        "stable": stable,
        "report": "%6.0f Hz  %s  energy %.0f%% of start, lowest node %.3f m, residual %.2f m/s" % [
            rate, "stable  " if stable else "GAINING ", energy_ratio * 100.0, lowest, moving],
    }


## The first node that is not finite or is past the explosion speed, or -1.
func _runaway(solver: RefCounted) -> int:
    for n: int in solver.node_count():
        var speed: float = solver.get_node_velocity(n).length()
        # Explicitly, because every comparison against NaN is false: an exploded rig sails
        # through a greater-than check and the probe reports it stable.
        if not is_finite(speed) or speed > EXPLOSION_SPEED:
            return n
    return -1


## What the runaway node is, and what is attached to it — which is the part that says whether
## the fault is a mass, a spring or a damper.
func _describe(solver: RefCounted, truck: TruckParser, node: int) -> String:
    if node < 0:
        return "energy went non-finite"
    var beams: int = 0
    var worst_spring: float = 0.0
    var worst_damp: float = 0.0
    var total_damp: float = 0.0
    for i: int in range(0, truck.beams.size(), 2):
        if truck.beams[i] != node and truck.beams[i + 1] != node:
            continue
        beams += 1
        worst_spring = maxf(worst_spring, truck.beam_spring[i / 2])
        worst_damp = maxf(worst_damp, truck.beam_damp[i / 2])
        total_damp += truck.beam_damp[i / 2]
    var mass: float = solver.get_node_mass(node)
    var tyre: String = " (tread)" if node >= truck.generated_from else ""
    # Explicit Euler is stable while dt is under 2m/d for a damper and 2*sqrt(m/k) for a
    # spring, so these two are the rates this node's own attachments imply.
    var damp_limit: float = 0.0 if total_damp <= 0.0 else total_damp / (2.0 * mass)
    var spring_limit: float = 0.0 if worst_spring <= 0.0 else sqrt(
        float(beams) * worst_spring / mass
    ) * 0.5
    return (
        "node %d%s, %.2f kg, %d beams, worst spring %.0f N/m, worst damp %.0f, total damp %.0f"
        % [node, tyre, mass, beams, worst_spring, worst_damp, total_damp]
        + "; damper needs over %.0f Hz, springs over %.0f Hz"
        % [damp_limit, spring_limit]
    )
