extends SceneTree
## When a wheel folds under power, and what the drivetrain and the contact were doing at the time.
##
## `drive_stance` reports the worst lean over a run and `fold_report` what holds the hub at the
## end of it. Neither says *when* — whether the hub leans with the first torque, with the first
## wheelspin, or with the upshift that doubles the tread speed — and the timing is what tells a
## stiffness fault from a load fault. This prints a line every tenth of a second.
##
##   godot --path . --headless --script res://harness/dev/fold_trace.gd -- <mod dir> <truck> \
##       [throttle] [friction override] [hold gear 0|1]

const SUBSTEP_HZ: float = 2000.0
const SETTLE_SECONDS: float = 2.0
const DRIVE_SECONDS: float = 4.0
const REPORT_EVERY_FRAMES: int = 6


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    var throttle: float = float(argv[2]) if argv.size() > 2 else 1.0
    var friction_override: float = float(argv[3]) if argv.size() > 3 else -1.0
    var hold_gear: bool = argv.size() > 4 and argv[4] == "1"
    var truck: TruckParser = TruckParser.new()
    if truck.parse_file(SourceScan.repo_root().path_join(argv[0]).path_join(argv[1])) != "":
        quit(1)
        return
    var rig: Dictionary = RigBuilder.build(truck, 0.0)
    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.0)
    if friction_override > 0.0:
        for i: int in range(truck.generated_from, truck.nodes.size()):
            solver.set_node_friction(i, friction_override)
    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    for _i: int in int(SETTLE_SECONDS * 60.0):
        solver.step(dt, chunk)
    var driven: Array[int] = []
    for index: int in truck.wheels.size():
        if int(truck.wheels[index]["propulsed"]) != 0:
            driven.append(index)
    print("%s: throttle %.2f, friction %s, %s; driven wheels %s" % [
        argv[1], throttle,
        "file's" if friction_override <= 0.0 else str(friction_override),
        "gear held" if hold_gear else "auto", str(driven)])
    print("%6s %4s %6s %8s %8s %8s %7s %7s %8s %8s %9s" % [
        "t", "gear", "rpm", "tread", "road", "slip", "lean0", "lean1", "wtorque", "hubF kN", "beam"])
    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(throttle)
    var frames: int = int(DRIVE_SECONDS * 60.0)
    for frame: int in frames + 1:
        if frame % REPORT_EVERY_FRAMES == 0:
            _report(solver, truck, driven, float(frame) / 60.0)
        if frame == frames:
            break
        if hold_gear:
            solver.set_gear_selector(1)
        solver.step(dt, chunk)
    quit(0)


func _report(solver: RefCounted, truck: TruckParser, driven: Array[int], t: float) -> void:
    var at: PackedVector3Array = solver.get_positions()
    var leans: Array[float] = []
    var tread: float = 0.0
    var torque: float = 0.0
    var slip: float = 0.0
    for w: int in driven:
        var wheel: Dictionary = truck.wheels[w]
        var axis: Vector3 = at[wheel["node2"] as int] - at[wheel["node1"] as int]
        leans.append(rad_to_deg(asin(clampf(absf(axis.normalized().y), 0.0, 1.0))))
        tread = maxf(tread, absf(solver.get_wheel_speed(w)))
        torque = maxf(torque, absf(solver.get_wheel_torque(w)))
        slip = maxf(slip, _contact_slip(solver, truck, w, at))
    var worst: Dictionary = _worst_hub_beam(solver, truck, driven, at)
    print("%6.2f %4d %6.0f %8.1f %8.1f %8.1f %7.1f %7.1f %8.0f %8.1f %9s" % [
        t, solver.engine_gear(), solver.engine_rpm(), tread, solver.road_speed(), slip,
        leans[0] if leans.size() > 0 else 0.0, leans[1] if leans.size() > 1 else 0.0,
        torque, float(worst["force"]) / 1000.0, "%d-%d" % [worst["a"], worst["b"]]])


## The horizontal speed of the lowest tread node of a wheel: what the ground sees slipping.
func _contact_slip(solver: RefCounted, truck: TruckParser, w: int, at: PackedVector3Array) -> float:
    var wheel: Dictionary = truck.wheels[w]
    var first: int = wheel["first_tread"] as int
    var count: int = wheel["tread_count"] as int
    var lowest: int = first
    for i: int in range(first, first + count):
        if at[i].y < at[lowest].y:
            lowest = i
    var v: Vector3 = solver.get_node_velocity(lowest)
    return Vector2(v.x, v.z).length()


func _worst_hub_beam(solver: RefCounted, truck: TruckParser, driven: Array[int], at: PackedVector3Array) -> Dictionary:
    var hub: Array[int] = []
    for w: int in driven:
        hub.append(truck.wheels[w]["node1"] as int)
        hub.append(truck.wheels[w]["node2"] as int)
    var worst: Dictionary = {"force": 0.0, "a": -1, "b": -1}
    for beam: int in solver.beam_count():
        var a: int = truck.beams[beam * 2]
        var b: int = truck.beams[beam * 2 + 1]
        if not (hub.has(a) or hub.has(b)):
            continue
        var force: float = (at[a].distance_to(at[b]) - solver.get_beam_rest_length(beam)) * truck.beam_spring[beam]
        if absf(force) > absf(worst["force"] as float):
            worst = {"force": force, "a": a, "b": b}
    return worst
