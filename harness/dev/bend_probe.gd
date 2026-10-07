extends SceneTree
## Which beams of a rig take a permanent set over a gentle drive, and what they are made of.
##
## The crash gate reports a count; this reports the beams. Run it when a change moves that count:
##
##   godot --path . --headless --script res://harness/dev/bend_probe.gd -- assets/mods/ChevyS1023 S10offroad.truck

const SUBSTEP_HZ: float = 2000.0
const SETTLE_SECONDS: float = 1.5
const DRIVE_SECONDS: float = 6.0
const THROTTLE: float = 0.12
const WALL_AT_M: float = 22.0
const WALL_HALF: Vector3 = Vector3(9.0, 1.6, 1.0)
const BENT_M: float = 0.01


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    var mod_dir: String = SourceScan.repo_root().path_join(argv[0])
    var rig: Dictionary = RigBuilder.from_file(mod_dir, argv[1], 0.0)
    if (rig["error"] as String) != "":
        printerr(rig["error"])
        quit(1)
        return
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.15)
    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    for _i: int in int(SETTLE_SECONDS * 60.0):
        solver.step(dt, chunk)
    var before: PackedFloat32Array = _rest(solver)
    var pose: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
    var forward: Vector3 = -pose.basis.z
    forward = Vector3(forward.x, 0.0, forward.z).normalized()
    solver.add_obstacle_box(
        Transform3D(
            Basis.looking_at(-forward, Vector3.UP),
            pose.origin + forward * WALL_AT_M + Vector3(0.0, WALL_HALF.y, 0.0)
        ), WALL_HALF, 0
    )
    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(THROTTLE)
    for _i: int in int(DRIVE_SECONDS * 60.0):
        solver.step(dt, chunk)
    solver.set_throttle(0.0)
    solver.set_brake(1.0)
    for _i: int in int(2.0 * 60.0):
        solver.step(dt, chunk)
    var after: PackedFloat32Array = _rest(solver)
    print("%d beams, %d nodes, generated from %d" % [
        before.size(), truck.nodes.size(), truck.generated_from])
    var bent: int = 0
    for i: int in before.size():
        if absf(after[i] - before[i]) < BENT_M:
            continue
        bent += 1
        if bent > 24:
            continue
        var a: int = truck.beams[i * 2]
        var b: int = truck.beams[i * 2 + 1]
        print("  beam %4d  %5.1f -> %5.1f mm  nodes %d(%s) - %d(%s)  k %.0f d %.0f deform %.0f" % [
            i, before[i] * 1000.0, after[i] * 1000.0,
            a, truck.node_ids[a], b, truck.node_ids[b],
            truck.beam_spring[i], truck.beam_damp[i], truck.beam_deform[i]])
    print("bent: %d" % bent)
    quit(0)


func _rest(solver: RefCounted) -> PackedFloat32Array:
    var out: PackedFloat32Array = PackedFloat32Array()
    for i: int in solver.beam_count():
        out.append(solver.get_beam_rest_length(i))
    return out
