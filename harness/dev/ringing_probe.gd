extends SceneTree
## Measures what a settled rig is still doing, and whether the rendered frame makes it worse.
##
##   godot --path game --headless --script res://harness/dev/ringing_probe.gd -- <truck> [rate]
##
## Three questions, because "the body looks like it is shaking" could be any of them: how fast
## are the nodes actually moving, at what frequency, and how much does the actor frame — built
## from three nodes and carrying the whole rendered vehicle — amplify it.

var rate: float = 2000.0
const SETTLE_SECONDS: float = 3.0
const WATCH_SECONDS: float = 1.0


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    if argv.is_empty():
        printerr("usage: ringing_probe.gd -- <path to .truck> [substep_hz]")
        quit(2)
        return
    if argv.size() > 1:
        rate = argv[1].to_float()
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_file(argv[0])
    if error != "":
        printerr(error)
        quit(1)
        return
    var built: Dictionary = RigBuilder.build(truck, 0.02)
    var solver: RefCounted = built["solver"] as RefCounted
    solver.set_ground(0.0, true)

    var dt: float = 1.0 / rate
    var chunk: int = int(rate / 60.0)
    # Ride height before the rig has taken up its own weight, per axle: the difference is the
    # static deflection, which is what "the suspension feels stiff" is a statement about.
    var before: PackedFloat32Array = _ride_heights(solver, truck)
    for _i: int in int(SETTLE_SECONDS * 60.0):
        solver.step(dt, chunk)
    var after: PackedFloat32Array = _ride_heights(solver, truck)

    # Per node: peak speed and how often its vertical velocity changes sign, which is the
    # ringing frequency without needing a transform.
    var count: int = solver.node_count()
    var peak: PackedFloat32Array = PackedFloat32Array()
    var crossings: PackedInt32Array = PackedInt32Array()
    var previous_sign: PackedFloat32Array = PackedFloat32Array()
    peak.resize(count)
    crossings.resize(count)
    previous_sign.resize(count)

    var frames: int = int(WATCH_SECONDS * 60.0)
    var frame_origins: PackedVector3Array = PackedVector3Array()
    var frame_angles: PackedFloat32Array = PackedFloat32Array()
    for _f: int in frames:
        # One substep at a time, so the crossing count is a real frequency and not aliased by
        # only looking once a rendered frame.
        for _s: int in chunk:
            solver.step(dt, 1)
            for n: int in count:
                var vertical: float = solver.get_node_velocity(n).y
                peak[n] = maxf(peak[n], solver.get_node_velocity(n).length())
                var sign_now: float = signf(vertical)
                if sign_now != 0.0 and previous_sign[n] != 0.0 and sign_now != previous_sign[n]:
                    crossings[n] += 1
                if sign_now != 0.0:
                    previous_sign[n] = sign_now
        var actor: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
        frame_origins.append(actor.origin)
        frame_angles.append(actor.basis.get_euler().z)

    var worst: int = 0
    var body_worst: int = 0
    for n: int in count:
        if peak[n] > peak[worst]:
            worst = n
        if n < truck.generated_from and peak[n] > peak[body_worst]:
            body_worst = n
    print("%s at %.0f Hz, %.1f s after settling" % [truck.name, rate, SETTLE_SECONDS])
    for label: String in ["any", "body"]:
        var n: int = worst if label == "any" else body_worst
        # Two zero crossings per cycle.
        var hz: float = float(crossings[n]) / (2.0 * WATCH_SECONDS)
        print("  worst %-4s node %3d: %.3f m/s peak, %.0f Hz, %.2f kg, %s" % [
            label, n, peak[n], hz, solver.get_node_mass(n),
            "tread" if n >= truck.generated_from else "body"])

    # How much the rendered vehicle moves as a whole, which is node vibration seen through a
    # frame built from three of them.
    var origin_spread: float = 0.0
    var roll_spread: float = 0.0
    var centre: Vector3 = Vector3.ZERO
    for origin: Vector3 in frame_origins:
        centre += origin / float(frame_origins.size())
    for i: int in frame_origins.size():
        origin_spread = maxf(origin_spread, frame_origins[i].distance_to(centre))
        roll_spread = maxf(roll_spread, absf(frame_angles[i] - frame_angles[0]))
    print("  actor frame over %.1f s: origin wanders %.2f mm, roll wanders %.3f deg" % [
        WATCH_SECONDS, origin_spread * 1000.0, rad_to_deg(roll_spread)])
    var travel: PackedStringArray = PackedStringArray()
    for i: int in before.size():
        travel.append("%.0f mm" % ((before[i] - after[i]) * 1000.0))
    print("  static suspension deflection per wheel: %s" % ", ".join(travel))
    _report_suspension(solver, truck)
    quit(0)


## What is actually carrying the vehicle's weight at the rear axle.
##
## A Rigs of Rods suspension springs on its shocks and is *located* by ordinary beams, which
## form a linkage that should allow vertical travel without any of them changing length. If
## the frame barely moves, something is resisting that travel, and the way to find it is to
## ask which beams on the axle are carrying force rather than to reason about the geometry.
func _report_suspension(solver: RefCounted, truck: TruckParser) -> void:
    var axle: int = truck.wheels[2]["node1"] as int
    print("  beams on rear axle node %d, by the force each is carrying:" % axle)
    var rows: Array[Dictionary] = []
    for i: int in range(0, truck.beams.size(), 2):
        var a: int = truck.beams[i]
        var b: int = truck.beams[i + 1]
        if a != axle and b != axle:
            continue
        var beam: int = i / 2
        var rest: float = truck.nodes[a].distance_to(truck.nodes[b])
        var now: float = solver.get_node_position(a).distance_to(solver.get_node_position(b))
        var spring: float = truck.beam_spring[beam]
        rows.append({
            "other": b if a == axle else a,
            "force": absf((now - rest) * spring),
            "spring": spring,
            "damp": truck.beam_damp[beam],
            "stretch_mm": (now - rest) * 1000.0,
            "tread": (b if a == axle else a) >= truck.generated_from,
        })
    rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
        return (x["force"] as float) > (y["force"] as float))
    var shown: int = 0
    for row: Dictionary in rows:
        if bool(row["tread"]):
            continue
        shown += 1
        if shown > 6:
            break
        print("    to node %3d: %8.0f N, spring %9.0f, damp %6.0f, stretched %+.2f mm" % [
            row["other"], row["force"], row["spring"], row["damp"], row["stretch_mm"]])


## Height of the frame above each axle, which is what the suspension carries.
func _ride_heights(solver: RefCounted, truck: TruckParser) -> PackedFloat32Array:
    var out: PackedFloat32Array = PackedFloat32Array()
    var frame: Vector3 = ActorFrame.of(solver.get_positions(), truck.camera_nodes).origin
    for wheel: Dictionary in truck.wheels:
        var axle: Vector3 = (
            solver.get_node_position(wheel["node1"] as int)
            + solver.get_node_position(wheel["node2"] as int)
        ) * 0.5
        out.append(frame.y - axle.y)
    return out
