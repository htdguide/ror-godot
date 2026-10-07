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
        {"name": "wall", "half": WALL_HALF, "tri": false},
        {"name": "pole", "half": POLE_HALF, "tri": false},
        {"name": "pole/tri", "half": POLE_HALF, "tri": true},
        {"name": "lapaz", "half": POLE_HALF, "tri": true, "hull": "lapaz"},
    ]:
        var out: Dictionary = _hit(argv[0], argv[1], against["half"] as Vector3,
                                   bool(against["tri"]), against.get("hull", "") as String)
        print("%-8s: hit %5.1f m/s, %3d bent, %2d broken, body centre %+.2f m of the obstacle, left at %4.1f m/s" % [
            against["name"], out["speed"], out["bent"], out["broken"], out["through"],
            out["stopped"]])
    quit(0)


## The twelve triangles of a box, wound so every face's normal points outward.
static func _box_triangles(at: Transform3D, half: Vector3) -> Array:
    var corner: Array[Vector3] = []
    for i: int in 8:
        corner.append(at * Vector3(
            half.x if (i & 1) != 0 else -half.x,
            half.y if (i & 2) != 0 else -half.y,
            half.z if (i & 4) != 0 else -half.z
        ))
    var faces: Array = [
        [0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4],
        [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5],
    ]
    var out: Array = []
    for face: Array in faces:
        out.append([corner[face[0]], corner[face[1]], corner[face[2]]])
        out.append([corner[face[0]], corner[face[2]], corner[face[3]]])
    return out


## One of a terrain's own collision hulls, moved so that its base sits at `at`. The real thing,
## with the winding the loader gives it.
static func _terrain_hull(map: String, at: Vector3) -> Array:
    var loaded: Dictionary = RorTerrainLibrary.load_named(map)
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain
    var tris: Array[Dictionary] = RorObjectCollision.triangles(terrain)
    if tris.is_empty():
        return []
    var first: String = tris[0]["name"] as String
    var low: Vector3 = tris[0]["a"] as Vector3
    var kept: Array = []
    for tri: Dictionary in tris:
        if (tri["name"] as String) != first:
            continue
        for key: String in ["a", "b", "c"]:
            low = low.min(tri[key] as Vector3)
        kept.append(tri)
        if kept.size() >= 64:
            break
    var shift: Vector3 = at - low
    var out: Array = []
    for tri: Dictionary in kept:
        out.append([
            (tri["a"] as Vector3) + shift, (tri["b"] as Vector3) + shift,
            (tri["c"] as Vector3) + shift
        ])
    return out


func _hit(dir: String, file: String, half: Vector3, as_triangles: bool,
          hull: String = "") -> Dictionary:
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
    var at: Transform3D = Transform3D(Basis.looking_at(-forward, Vector3.UP), centre)
    if hull != "":
        for tri: Array in _terrain_hull(hull, Vector3(centre.x, 0.0, centre.z)):
            solver.add_collision_triangle(tri[0], tri[1], tri[2], 0)
    elif as_triangles:
        for tri: Array in _box_triangles(at, half):
            solver.add_collision_triangle(tri[0], tri[1], tri[2], 0)
    else:
        solver.add_obstacle_box(at, half, 0)
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
    # **Where the body ended up, not its furthest node.** A car that wraps around a pole has
    # nodes well past it and is not through it; a car that is through it has its whole mass past.
    var settled: PackedVector3Array = solver.get_positions()
    var middle: Vector3 = Vector3.ZERO
    for i: int in truck.generated_from:
        middle += settled[i]
    middle /= maxf(float(truck.generated_from), 1.0)
    return {
        "speed": fastest,
        "bent": bent,
        "broken": solver.broken_beam_count(),
        "through": (middle - centre).dot(forward),
        "stopped": absf(solver.road_speed()),
    }


func _rest(solver: RefCounted) -> PackedFloat32Array:
    var out: PackedFloat32Array = PackedFloat32Array()
    for beam: int in solver.beam_count():
        out.append(solver.get_beam_rest_length(beam))
    return out
