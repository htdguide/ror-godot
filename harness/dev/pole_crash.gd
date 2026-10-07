extends SceneTree
## What a vehicle does against a pole, against what it does on a wall.
##
## A wall meets a rig along its whole width; a pole meets one or two nodes. The deform law is the
## same for both, so a rig that bends on a wall and not on a pole is a contact question and not a
## damage one.
##
##   godot --path . --headless --script res://harness/dev/pole_crash.gd -- <mod dir> <actor file>

const SUBSTEP_HZ: float = 2000.0
const SETTLE_SECONDS: float = 1.5
const IMPACT_SECONDS: float = 6.0
const AT_M: float = 22.0
const THROTTLE: float = 1.0
const BENT_M: float = 0.01
## La Paz's own pole, measured off its collision mesh: 0.17 by 0.15 m and 8.1 m tall.
const POLE_HALF: Vector3 = Vector3(0.087, 4.05, 0.074)
const WALL_HALF: Vector3 = Vector3(9.0, 1.6, 1.0)


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    for against: Dictionary in [
        {"name": "wall", "half": WALL_HALF}, {"name": "pole", "half": POLE_HALF}
    ]:
        var out: Dictionary = _hit(argv[0], argv[1], against["half"] as Vector3)
        print("%-5s: hit at %5.1f m/s, %3d beams bent, %2d broken, nose moved %.2f m past it" % [
            against["name"], out["speed"], out["bent"], out["broken"], out["through"]])
    quit(0)


func _hit(dir: String, file: String, half: Vector3) -> Dictionary:
    var rig: Dictionary = RigBuilder.from_file(SourceScan.repo_root().path_join(dir), file, 0.0)
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
    var centre: Vector3 = pose.origin + forward * AT_M + Vector3(0.0, half.y, 0.0)
    solver.add_obstacle_box(
        Transform3D(Basis.looking_at(-forward, Vector3.UP), centre), half, 0
    )
    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(THROTTLE)
    var fastest: float = 0.0
    for _i: int in int(IMPACT_SECONDS * 60.0):
        solver.step(dt, chunk)
        fastest = maxf(fastest, absf(solver.road_speed()))
    var after: PackedFloat32Array = _rest(solver)
    var bent: int = 0
    for i: int in mini(before.size(), after.size()):
        if absf(after[i] - before[i]) > BENT_M:
            bent += 1
    # How far the furthest-forward node ended up past the obstacle's own face.
    var at: PackedVector3Array = solver.get_positions()
    var furthest: float = -INF
    for node: Vector3 in at:
        furthest = maxf(furthest, (node - centre).dot(forward))
    return {
        "speed": fastest, "bent": bent, "broken": solver.broken_beam_count(),
        "through": furthest + half.z,
    }


func _rest(solver: RefCounted) -> PackedFloat32Array:
    var out: PackedFloat32Array = PackedFloat32Array()
    for beam: int in solver.beam_count():
        out.append(solver.get_beam_rest_length(beam))
    return out
