extends SceneTree
## What is holding a wheel's hub when it folds under power, and how hard each thing is working.
##
## The axle's two nodes are what rotate, so the answer is in the beams attached to them: which
## ones stretch, by how much, and at what rate.

const SUBSTEP_HZ: float = 2000.0
const SETTLE_SECONDS: float = 2.0
const DRIVE_SECONDS: float = 4.0


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
    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    for _i: int in int(SETTLE_SECONDS * 60.0):
        solver.step(dt, chunk)
    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(1.0)
    for _i: int in int(DRIVE_SECONDS * 60.0):
        solver.step(dt, chunk)
    var at: PackedVector3Array = solver.get_positions()

    # The wheel that folded worst, and the beams on its hub.
    var worst_wheel: int = -1
    var worst_lean: float = 0.0
    for index: int in truck.wheels.size():
        var wheel: Dictionary = truck.wheels[index]
        var axis: Vector3 = at[wheel["node2"] as int] - at[wheel["node1"] as int]
        var lean: float = rad_to_deg(asin(clampf(absf(axis.normalized().y), 0.0, 1.0)))
        if lean > worst_lean:
            worst_lean = lean
            worst_wheel = index
    if worst_wheel < 0:
        quit(0)
        return
    var hub: Array[int] = [
        truck.wheels[worst_wheel]["node1"] as int, truck.wheels[worst_wheel]["node2"] as int
    ]
    print("%s: wheel %d leans %.1f degrees, hub nodes %d and %d" % [
        argv[1], worst_wheel, worst_lean, hub[0], hub[1]])
    var rows: Array[Dictionary] = []
    for beam: int in solver.beam_count():
        var a: int = truck.beams[beam * 2]
        var b: int = truck.beams[beam * 2 + 1]
        if not (hub.has(a) or hub.has(b)):
            continue
        var rest: float = solver.get_beam_rest_length(beam)
        var now: float = at[a].distance_to(at[b])
        rows.append({
            "beam": beam, "a": a, "b": b, "strain": (now - rest) / maxf(rest, 0.0001),
            "spring": truck.beam_spring[beam], "force": (now - rest) * truck.beam_spring[beam],
            "generated": a >= truck.generated_from or b >= truck.generated_from,
        })
    rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
        return absf(x["force"] as float) > absf(y["force"] as float))
    print("  %d beams on the hub, worst by force:" % rows.size())
    for i: int in mini(rows.size(), 10):
        var row: Dictionary = rows[i]
        print("    beam %4d %3d-%3d  strain %+6.1f%%  k %9.0f  force %+9.0f N  %s" % [
            row["beam"], row["a"], row["b"], float(row["strain"]) * 100.0,
            row["spring"], row["force"], "wheel" if bool(row["generated"]) else "body"])
    quit(0)
