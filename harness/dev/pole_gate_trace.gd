extends SceneTree
## The scenery gate's own run, frame by frame, with the one knob the gate does not have.
##
## `a_terrains_own_scenery_is_solid` drives the hero at La Paz's nearest pole and reads two
## numbers at the end. This prints what happened in between — body speed, how many nodes are
## inside a solid box, how many beams have broken — and can raise every beam's yield stress to a
## floor, which is what the rig had before `2587ebe` read `enable_advanced_deformation` at all.
##
##   godot --path . --headless --script res://harness/dev/pole_gate_trace.gd -- \
##       <mod dir> <truck> [yield floor N | 0] [throttle]

const TERRAIN_DIR: String = "assets/terrains/lapaz2"
const SUBSTEP_HZ: float = 2000.0
const RUN_UP_M: float = 30.0
const DRIVE_SECONDS: float = 8.0


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    var floor_n: float = argv[2].to_float() if argv.size() > 2 else 0.0
    var throttle: float = argv[3].to_float() if argv.size() > 3 else 1.0
    # Metres to move the start along the rig's own lateral axis, so a chosen node row meets the
    # pole instead of whichever one the drift delivers.
    var shift: float = argv[4].to_float() if argv.size() > 4 else 0.0
    # A driver: steer so the pole crosses the rig at `aim_x` (rig frame), with this gain per metre
    # of error. Zero gain is hands off.
    var gain: float = argv[5].to_float() if argv.size() > 5 else 0.0
    var aim_x: float = argv[6].to_float() if argv.size() > 6 else 0.0
    var loaded: Dictionary = RorTerrain.load_from(SourceScan.repo_root().path_join(TERRAIN_DIR))
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain
    var boxes: Array[Dictionary] = RorObjectCollision.boxes(terrain)
    var start: Vector3 = terrain.start_position()
    var target: Vector3 = Vector3.ZERO
    var nearest: float = INF
    for box: Dictionary in boxes:
        var at: Vector3 = (box["transform"] as Transform3D).origin
        var away: float = Vector2(at.x - start.x, at.z - start.z).length()
        if away < nearest and away > RUN_UP_M:
            nearest = away
            target = at
    var pole: Array[Dictionary] = []
    for box: Dictionary in boxes:
        if ((box["transform"] as Transform3D).origin - target).length() < 1.5:
            pole.append(box)
    print("target pole at %s, %d boxes within 1.5 m:" % [target, pole.size()])
    for box: Dictionary in pole:
        var tf: Transform3D = box["transform"] as Transform3D
        var h: Vector3 = box["half"] as Vector3
        var reach: Vector3 = (tf.basis.x * h.x).abs() + (tf.basis.y * h.y).abs() + (tf.basis.z * h.z).abs()
        print("   origin %s half %s  basis z %s  world aabb y %.2f..%.2f x %.2f..%.2f z %.2f..%.2f" % [
            tf.origin, h, tf.basis.z, tf.origin.y - reach.y, tf.origin.y + reach.y,
            tf.origin.x - reach.x, tf.origin.x + reach.x, tf.origin.z - reach.z, tf.origin.z + reach.z])

    var rig: Dictionary = RigBuilder.from_file(SourceScan.repo_root().path_join(argv[0]), argv[1], 0.0)
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    var grid: Dictionary = terrain.lattice()
    var size: int = grid["size"] as int
    var heights: PackedFloat32Array = PackedFloat32Array()
    heights.resize(size * size)
    for z: int in size:
        for x: int in size:
            heights[z * size + x] = terrain.height_at(x, z)
    solver.set_heightfield(heights, size, size, grid["origin"] as Vector3, grid["spacing"] as float)
    RorObjectCollision.apply(terrain, solver)
    solver.set_ground(0.0, true)
    if floor_n > 0.0:
        var raised: int = 0
        for beam: int in solver.beam_count():
            if truck.beam_deform[beam] < floor_n:
                solver.set_beam_limits(beam, floor_n, maxf(truck.beam_strength[beam], floor_n * 2.0),
                                       truck.beam_plastic[beam], truck.beam_deformable[beam] != 0)
                raised += 1
        print("yield floor %.0f N applied to %d of %d beams" % [floor_n, raised, solver.beam_count()])

    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    RigBuilder.place(solver, truck, Vector3(start.x, 0.0, start.z), 0.0, 0.15)
    for _i: int in 60:
        solver.step(dt, chunk)
    var pose: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
    var forward: Vector3 = -pose.basis.z
    forward = Vector3(forward.x, 0.0, forward.z).normalized()
    var lateral: Vector3 = Vector3(pose.basis.x.x, 0.0, pose.basis.x.z).normalized()
    var from: Vector3 = target - forward * RUN_UP_M + lateral * shift
    RigBuilder.place(solver, truck, Vector3(from.x, 0.0, from.z), 0.0, 0.15)
    for _i: int in 120:
        solver.step(dt, chunk)
    print("%s: throttle %.2f; %d nodes" % [argv[1], throttle, truck.nodes.size()])
    print("ground under the pole (solver): %.2f; at the rig's start: %.2f" % [
        solver.ground_height_at(target), solver.ground_height_at(Vector3(from.x, 0.0, from.z))])
    var lo: float = INF
    var hi: float = -INF
    for q: Vector3 in solver.get_positions():
        lo = minf(lo, q.y)
        hi = maxf(hi, q.y)
    print("rig node y range after settling: %.2f..%.2f" % [lo, hi])
    print("%6s %8s %8s %7s %7s %8s %6s" % ["t", "km/h", "to pole", "in box", "broken", "max depth", "swept"])
    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(throttle)
    var previous: Vector3 = ActorFrame.of(solver.get_positions(), truck.camera_nodes).origin
    var was: PackedVector3Array = solver.get_positions()
    var swept_hits: int = 0
    var closest: float = INF
    var peak: float = 0.0
    var last_kmh: float = 0.0
    for frame: int in int(DRIVE_SECONDS * 60.0):
        # A negative throttle argument is a speed to hold, in km/h, with a proportional throttle.
        if throttle < 0.0:
            solver.set_throttle(clampf((-throttle - last_kmh) / 10.0, 0.0, 1.0))
        if gain != 0.0:
            var now: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
            var ahead_m: float = (target - now.origin).dot(forward)
            if ahead_m > 2.0:
                var px: float = (now.affine_inverse() * Vector3(target.x, now.origin.y, target.z)).x
                # Pursuit: steer on the bearing to the aim point, not on the offset. Offset alone
                # oscillated 2 m either side of the pole at every gain tried.
                var bearing: float = atan2(px - aim_x, ahead_m)
                solver.set_steer_command(DriveCfg.steer_command(clampf(gain * bearing, -1.0, 1.0)))
                if frame % 30 == 0:
                    print("   t %.1f  pole x %+.2f  ahead %.1f  km/h %.1f" % [float(frame) / 60.0, px, ahead_m, last_kmh])
            else:
                solver.set_steer_command(0.0)
        solver.step(dt, chunk)
        var here: Vector3 = ActorFrame.of(solver.get_positions(), truck.camera_nodes).origin
        last_kmh = previous.distance_to(here) * 60.0 * 3.6
        previous = here
        var away: float = Vector2(here.x - target.x, here.z - target.z).length()
        if away < closest:
            closest = away
            peak = maxf(peak, last_kmh)
            if away < 2.5:
                _lateral_census(solver, truck, target)
        var in_box: int = 0
        var deepest: float = 0.0
        var swept: int = 0
        var at: PackedVector3Array = solver.get_positions()
        if away < 8.0:
            for i: int in at.size():
                var hit: Dictionary = solver.obstacle_contact(at[i])
                if bool(hit["hit"]):
                    in_box += 1
                    deepest = maxf(deepest, float(hit.get("penetration", 0.0)))
                # The path the node took this frame, in centimetre steps: did it cross a box the
                # solver's own substeps should have caught?
                var path: Vector3 = at[i] - was[i]
                var steps: int = maxi(1, int(ceil(path.length() / 0.01)))
                for k: int in steps:
                    var p: Vector3 = was[i] + path * (float(k) / float(steps))
                    if bool(solver.obstacle_contact(p)["hit"]):
                        swept += 1
                        break
        swept_hits += swept
        was = at
        if frame % 6 == 0 or (away < 6.0 and frame % 2 == 0):
            print("%6.2f %8.1f %8.2f %7d %7d %8.3f %6d" % [
                float(frame) / 60.0, last_kmh, away, in_box, solver.broken_beam_count(), deepest,
                swept])
        if away > 12.0 and closest < 4.0:
            break
    print("nodes whose frame path crossed a box, summed over frames: %d" % swept_hits)
    print("peak before closest approach %.1f km/h; closest %.2f m; leaving at %.1f km/h (%.0f%% kept)" % [
        peak, closest, last_kmh, 100.0 * last_kmh / maxf(peak, 0.1)])
    quit(0)


## Where the pole sits across the rig, and where the rig's nodes sit across the rig, both in the
## rig's own frame at the moment it is over the pole. A pole between two node rows is never hit.
func _lateral_census(solver: RefCounted, truck: TruckParser, target: Vector3) -> void:
    var frame: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
    var inverse: Transform3D = frame.affine_inverse()
    var pole_x: float = (inverse * Vector3(target.x, frame.origin.y, target.z)).x
    var bins: Dictionary = {}
    for q: Vector3 in solver.get_positions():
        var local: Vector3 = inverse * q
        var bin: int = int(floor(local.x / 0.05))
        bins[bin] = int(bins.get(bin, 0)) + 1
    var keys: Array = bins.keys()
    keys.sort()
    var row: PackedStringArray = PackedStringArray()
    var mean: float = 0.0
    var n: int = 0
    for k: int in keys:
        var lo: float = float(k) * 0.05
        row.append("%+.2f:%d" % [lo, bins[k]])
        mean += (lo + 0.025) * float(bins[k])
        n += int(bins[k])
    print("   pole across the rig at x=%+.2f m; mean node x %+.2f; nodes per 5 cm lateral bin: %s" % [
        pole_x, mean / float(n), " ".join(row)])
