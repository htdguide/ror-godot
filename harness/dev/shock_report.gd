extends SceneTree
## How much of a settled rig's suspension is still inside its own travel.
##
## A shock past its bound has handed over to the structural rates and is a bump stop, not a
## spring: a vehicle resting on level ground with its shocks bottomed has no suspension left.
##
##   godot --path . --headless --script res://harness/dev/shock_report.gd -- <mod dir> <actor>

const SUBSTEP_HZ: float = 2000.0
const SETTLE_SECONDS: float = 2.5


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    var truck: TruckParser = TruckParser.new()
    if truck.parse_file(SourceScan.repo_root().path_join(argv[0]).path_join(argv[1])) != "":
        quit(1)
        return
    var rig: Dictionary = RigBuilder.build(truck, 0.0)
    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.0)
    for _i: int in int(SETTLE_SECONDS * 60.0):
        solver.step(1.0 / SUBSTEP_HZ, int(SUBSTEP_HZ / 60.0))
    var at: PackedVector3Array = solver.get_positions()

    var shocks: int = 0
    var bottomed: int = 0
    var topped: int = 0
    var worst: float = 0.0
    for entry: Dictionary in truck.bounded_beams:
        if (entry["bound"] as int) != BeamRows.BOUND_SHOCK:
            continue
        var beam: int = entry["beam"] as int
        shocks += 1
        var a: int = truck.beams[beam * 2]
        var b: int = truck.beams[beam * 2 + 1]
        var rest: float = solver.get_beam_rest_length(beam)
        var extension: float = at[a].distance_to(at[b]) - rest
        var short_at: float = -(entry["short_bound"] as float) * rest
        var long_at: float = (entry["long_bound"] as float) * rest
        if extension < short_at:
            bottomed += 1
            worst = maxf(worst, (short_at - extension) / maxf(rest, 0.0001))
        elif extension > long_at:
            topped += 1
            worst = maxf(worst, (extension - long_at) / maxf(rest, 0.0001))
    print("%-24s %3d shocks: %3d bottomed, %3d topped out, worst %.0f%% of its length past" % [
        argv[1], shocks, bottomed, topped, worst * 100.0])
    quit(0)
