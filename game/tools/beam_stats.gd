extends SceneTree
## Prints the spring and damping actually parsed from a vehicle, so a solver blow-up can
## be traced to its inputs rather than guessed at.


func _initialize() -> void:
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_file(OS.get_cmdline_user_args()[0])
    if error != "":
        printerr(error)
        quit(1)
        return
    var min_spring: float = INF
    var max_spring: float = -INF
    var min_damp: float = INF
    var max_damp: float = -INF
    for i: int in truck.beam_spring.size():
        min_spring = minf(min_spring, truck.beam_spring[i])
        max_spring = maxf(max_spring, truck.beam_spring[i])
        min_damp = minf(min_damp, truck.beam_damp[i])
        max_damp = maxf(max_damp, truck.beam_damp[i])
    print("beams=%d spring %.1f..%.1f damp %.1f..%.1f minimass=%.2f" % [
        truck.beams.size() / 2, min_spring, max_spring, min_damp, max_damp, truck.minimass_kg
    ])
    var zero_length: int = 0
    for i: int in range(0, truck.beams.size(), 2):
        if truck.nodes[truck.beams[i]].distance_to(truck.nodes[truck.beams[i + 1]]) < 0.0001:
            zero_length += 1
    print("zero_length_beams=%d" % zero_length)
    quit(0)
