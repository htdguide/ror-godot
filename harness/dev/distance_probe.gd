extends SceneTree
## The hero settled at growing distances from the origin, and what goes first as it gets further.
##
##   godot --path . --headless --script res://harness/dev/distance_probe.gd
##
## PLAN §0.12, order of work, step 2. The same rig, the same flat ground, the same settle, with
## only the world position changed: at each distance, how much the settled rig still rings (worst
## node speed and its frequency, the measure the tyre-ringing finding uses), whether any beam
## bent or broke from nothing, how far the actor frame wanders, and how wrong the ground query is
## against an exact plane. Positions are float32, so the resolution at distance d is
## d * 2^-23; the question is which of these feels it first.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const DISTANCES: Array[float] = [50.0, 1000.0, 3915.8, 10000.0, 100000.0, 1.0e6, 1.0e7]
const SUBSTEP_HZ: float = 2000.0
const SETTLE_SECONDS: float = 3.0
const WATCH_SECONDS: float = 1.0
## The ground: a flat heightfield centred on the rig, so the ground query runs at world magnitude
## the way a terrain's does.
const FIELD_SAMPLES: int = 129
const FIELD_SPACING: float = 2.0
## The ground query against an exact plane: a 1-in-50 slope sampled across the field.
const SLOPE: float = 0.02
const BENT_M: float = 0.001


func _initialize() -> void:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    for distance: float in DISTANCES:
        var row: Dictionary = _settle(mod_dir, distance)
        var query: float = _query_error(distance)
        print(
            "d %10.1f m  ulp %8.4f mm | %s | ground query worst %.4f mm"
            % [distance, _ulp(distance) * 1000.0, row["text"], query * 1000.0]
        )
    quit(0)


func _ulp(value: float) -> float:
    return pow(2.0, floorf(log(absf(value)) / log(2.0)) - 23.0)


func _field(distance: float, slope: float) -> Dictionary:
    var half: float = float(FIELD_SAMPLES - 1) * FIELD_SPACING * 0.5
    var origin: Vector3 = Vector3(distance - half, 0.0, distance - half)
    var heights: PackedFloat32Array = PackedFloat32Array()
    heights.resize(FIELD_SAMPLES * FIELD_SAMPLES)
    for z: int in FIELD_SAMPLES:
        for x: int in FIELD_SAMPLES:
            heights[z * FIELD_SAMPLES + x] = slope * float(x) * FIELD_SPACING
    return {"heights": heights, "origin": origin}


## How far the solver's ground query is from the plane it was given, worst over a grid of points
## off the samples.
func _query_error(distance: float) -> float:
    var solver: RorSolver = RorSolver.new()
    var field: Dictionary = _field(distance, SLOPE)
    var origin: Vector3 = field["origin"] as Vector3
    solver.set_heightfield(field["heights"], FIELD_SAMPLES, FIELD_SAMPLES, origin, FIELD_SPACING)
    var worst: float = 0.0
    for i: int in 40:
        for j: int in 40:
            # Points 0.37 of a cell off the sample grid, across the middle of the field.
            var dx: float = 64.0 + (float(i) + 0.37) * 3.1
            var dz: float = 64.0 + (float(j) + 0.37) * 3.1
            var at: Vector3 = Vector3(origin.x + dx, 0.0, origin.z + dz)
            # Exact for the point actually asked about: `at` and `origin` are float32 as the
            # solver receives them, and the difference is taken in float64 here.
            var exact: float = SLOPE * (at.x - origin.x)
            worst = maxf(worst, absf(solver.ground_height_at(at) - exact))
    return worst


func _settle(mod_dir: String, distance: float) -> Dictionary:
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        return {"text": rig["error"]}
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    var field: Dictionary = _field(distance, 0.0)
    # Contact is off until asked for; the heightfield is only the shape of what it meets.
    solver.set_ground(0.0, true)
    # `plane` on the command line leaves the heightfield out: the control that says whether a
    # change with distance is the beams or the ground query.
    if not OS.get_cmdline_user_args().has("plane"):
        solver.set_heightfield(
            field["heights"], FIELD_SAMPLES, FIELD_SAMPLES, field["origin"] as Vector3,
            FIELD_SPACING
        )
    RigBuilder.place(solver, truck, Vector3(distance, 0.0, distance), 0.0, 0.15)
    var references: PackedFloat32Array = PackedFloat32Array()
    for beam: int in solver.beam_count():
        references.append(solver.get_beam_reference_length(beam))
    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    for _i: int in int(SETTLE_SECONDS * 60.0):
        solver.step(dt, chunk)
    var count: int = solver.node_count()
    var peak: PackedFloat32Array = PackedFloat32Array()
    var crossings: PackedInt32Array = PackedInt32Array()
    var last_sign: PackedFloat32Array = PackedFloat32Array()
    peak.resize(count)
    crossings.resize(count)
    last_sign.resize(count)
    var origins: PackedVector3Array = PackedVector3Array()
    for _f: int in int(WATCH_SECONDS * 60.0):
        for _s: int in chunk:
            solver.step(dt, 1)
            for n: int in count:
                var v: Vector3 = solver.get_node_velocity(n)
                if not is_finite(v.length()):
                    return {"text": "non-finite at node %d" % n}
                peak[n] = maxf(peak[n], v.length())
                var s: float = signf(v.y)
                if s != 0.0 and last_sign[n] != 0.0 and s != last_sign[n]:
                    crossings[n] += 1
                if s != 0.0:
                    last_sign[n] = s
        origins.append(ActorFrame.of(solver.get_positions(), truck.camera_nodes).origin)
    var worst: int = 0
    var body: int = 0
    for n: int in count:
        if peak[n] > peak[worst]:
            worst = n
        if n < truck.generated_from and peak[n] > peak[body]:
            body = n
    var bent: int = 0
    for beam: int in solver.beam_count():
        if absf(solver.get_beam_rest_length(beam) - references[beam]) > BENT_M:
            bent += 1
    var wander: float = 0.0
    for origin: Vector3 in origins:
        wander = maxf(wander, origin.distance_to(origins[0]))
    return {"text": (
        "worst %.3f m/s %3.0f Hz (%s) body %.3f m/s | bent %d broken %d | frame wanders %.2f mm"
        % [
            peak[worst], float(crossings[worst]) / (2.0 * WATCH_SECONDS),
            "tread" if worst >= truck.generated_from else "body", peak[body],
            bent, solver.broken_beam_count(), wander * 1000.0,
        ]
    )}
