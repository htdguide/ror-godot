extends SceneTree
## Steps a vehicle rig one substep at a time and reports the first non-finite node.


## Substep rate, overridable so the same rig can be run at different steps.
var RATE: float = 2000.0


func _lowest(solver: RefCounted) -> float:
    var lowest: float = INF
    for n: int in solver.node_count():
        lowest = minf(lowest, solver.get_node_position(n).y)
    return lowest


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    if argv.size() > 1:
        RATE = argv[1].to_float()
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_file(argv[0])
    if error != "":
        printerr(error)
        quit(1)
        return
    var solver: RefCounted = ClassDB.instantiate("RorSolver") as RefCounted
    for node: Vector3 in truck.nodes:
        solver.add_node(node, truck.minimass_kg)
    for i: int in range(0, truck.beams.size(), 2):
        solver.add_beam(
            truck.beams[i], truck.beams[i + 1], 0.0,
            truck.beam_spring[i / 2], truck.beam_damp[i / 2]
        )
    var lowest: float = INF
    for node: Vector3 in truck.nodes:
        lowest = minf(lowest, node.y)
    for n: int in solver.node_count():
        solver.set_node_position(n, truck.nodes[n] + Vector3(0.0, 0.3 - lowest, 0.0))
    solver.set_gravity(Vector3(0.0, -9.81, 0.0))
    solver.set_ground(0.0, true)
    print("nodes=%d beams=%d (gravity and ground on)" % [solver.node_count(), solver.beam_count()])

    # What is attached to the node that runs away, and is any of it pre-stretched?
    var watch: int = 104
    var attached: int = 0
    var worst_extension: float = 0.0
    for i: int in range(0, truck.beams.size(), 2):
        var a: int = truck.beams[i]
        var b: int = truck.beams[i + 1]
        if a != watch and b != watch:
            continue
        attached += 1
        var rest: float = truck.nodes[a].distance_to(truck.nodes[b])
        worst_extension = maxf(worst_extension, absf(rest - truck.nodes[a].distance_to(truck.nodes[b])))
        if rest < 0.01:
            print("node %d has a beam to %d of rest length %.5f m (spring %.0f)"
                % [watch, a if b == watch else b, rest, truck.beam_spring[i / 2]])
    print("node %d has %d beams attached" % [watch, attached])

    for step: int in int(RATE * 2.0):
        solver.step(1.0 / RATE, 1)
        for n: int in solver.node_count():
            var velocity: Vector3 = solver.get_node_velocity(n)
            if not is_finite(velocity.length()):
                print("step %d: node %d velocity non-finite" % [step, n])
                quit(0)
                return
            if velocity.length() > 50.0:
                print("step %d (%.3f s): node %d reached %.1f m/s at height %.3f"
                    % [step, float(step) / RATE, n, velocity.length(),
                       solver.get_node_position(n).y])
                quit(0)
                return
    print("2 s at %.0f Hz: rig stayed bounded" % RATE + ": , lowest node at %.3f m"
        % _lowest(solver))
    quit(0)
