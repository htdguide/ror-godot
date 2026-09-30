extends SceneTree
## Drives a rig in a straight line and reports what it did.
##
##   godot --path game --headless --script res://harness/dev/drive_probe.gd -- \
##       <path to .truck> [substep_hz] [seconds] [steer]


var rate: float = 10000.0
var seconds: float = 6.0
var steer: float = 0.0


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    if argv.is_empty():
        printerr("usage: drive_probe.gd -- <path to .truck> [substep_hz] [seconds] [steer]")
        quit(2)
        return
    if argv.size() > 1:
        rate = argv[1].to_float()
    if argv.size() > 2:
        seconds = argv[2].to_float()
    if argv.size() > 3:
        steer = argv[3].to_float()

    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_file(argv[0])
    if error != "":
        printerr(error)
        quit(1)
        return
    var built: Dictionary = RigBuilder.build(truck, 0.02)
    if (built["error"] as String) != "":
        printerr(built["error"])
        quit(1)
        return
    var solver: RefCounted = built["solver"] as RefCounted
    solver.set_ground(0.0, true)
    print("rig: %d nodes, %d beams, %d wheels, %d hydros, %.1f kg, engine %s" % [
        solver.node_count(), solver.beam_count(), solver.wheel_count(), solver.hydro_count(),
        solver.total_mass(), "yes" if solver.has_engine() else "no"])

    var dt: float = 1.0 / rate
    var chunk: int = int(rate / 60.0)
    # Let it settle on its springs first, so the run measures driving and not the drop.
    for i: int in 60:
        solver.step(dt, chunk)
    var start: Vector3 = _centre(solver)
    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(1.0)
    solver.set_steer_command(steer)

    var frames: int = int(seconds * 60.0)
    var peak_speed: float = 0.0
    for frame: int in frames:
        solver.step(dt, chunk)
        var speed: float = absf(solver.road_speed())
        if not is_finite(speed):
            print("frame %d (%.2f s): solver diverged" % [frame, float(frame) / 60.0])
            quit(1)
            return
        peak_speed = maxf(peak_speed, speed)
        if frame % 30 == 0:
            print(("%5.2f s  %5.0f rpm  gear %d  clutch %.2f  torque %7.0f Nm  road %5.2f m/s"
                + "  moved %5.2f m  steer %+.2f") % [
                float(frame) / 60.0, solver.engine_rpm(), solver.engine_gear(),
                solver.engine_clutch(), solver.engine_torque(), solver.road_speed(),
                _centre(solver).distance_to(start), solver.steer_state()])
    var moved: Vector3 = _centre(solver) - start
    print("after %.1f s: moved %.2f m (%.2f, %.2f, %.2f), peak %.2f m/s (%.0f km/h), %.0f rpm gear %d"
        % [seconds, moved.length(), moved.x, moved.y, moved.z, peak_speed, peak_speed * 3.6,
           solver.engine_rpm(), solver.engine_gear()])
    for w: int in solver.wheel_count():
        print("wheel %d: %.2f m/s tread, %.1f rad, torque %.0f Nm" % [
            w, solver.get_wheel_speed(w), solver.get_wheel_rotation(w),
            solver.get_wheel_torque(w)])
    quit(0)


func _centre(solver: RefCounted) -> Vector3:
    var sum: Vector3 = Vector3.ZERO
    var positions: PackedVector3Array = solver.get_positions()
    for position: Vector3 in positions:
        sum += position
    return sum / float(positions.size())
