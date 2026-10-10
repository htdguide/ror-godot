extends GateBase
## The hero settled 3.9 km, 100 km and 10 000 km from the world origin does what it does beside it.
##
## PLAN §0.12, per-actor frames. Positions are float32 and resolve a coordinate to about
## `distance * 2^-23`; every beam force starts from the difference of two node positions, so a rig
## stored in world coordinates carries phantom stretch that grows with its distance from the
## origin. Measured 2026-10-11 before frames existed: parked at La Paz's own spawn, 3915.8 m out,
## the hero's body nodes moved thirty times faster than at the origin and settling bent 78 beams;
## at 10 km it broke 30. Each rig now stores its nodes relative to a frame that follows it.
##
## **The tolerance is the instrument's own.** The settled rig's worst node speed is a peak taken
## off a ringing system, and moving the rig a few centimetres changes it by a fair fraction. So the
## near-origin rig is settled at several placements and the far rig is held to that envelope,
## widened by no more than the near runs differ among themselves. Counts of bent and broken beams
## are held the same way, which for a spread of zero means exactly.
##
## **The control runs in the gate**: the same rig at La Paz's spawn with the frame pinned to the
## world origin, the way nodes were stored before. It has to land outside the envelope, or the gate
## could not have seen the fault it is there for.
##
## And a rig has to cross frames, not only sit in one: the far rig is driven at full throttle from
## 100 km out until its frame has moved, and must cover the ground the near rig covers.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const SUBSTEP_HZ: float = 2000.0
const FRAME_HZ: float = 60.0
const SETTLE_FRAMES: int = 180
const WATCH_FRAMES: int = 60
## Near the origin, at several placements, so the envelope has width. In metres along x and z.
const NEAR: Array[Vector2] = [
    Vector2(50.0, 50.0), Vector2(50.37, 49.71), Vector2(-31.2, 47.9), Vector2(12.5, -40.3),
    Vector2(-44.4, -21.6),
]
## La Paz's spawn, where the fault was found, and two that are only reachable with frames.
const FAR: Array[Vector2] = [
    Vector2(3915.8, 3915.8), Vector2(100000.0, 100000.0), Vector2(1.0e7, 1.0e7),
]
## A beam counts as bent when its rest length has moved this much.
const BENT_M: float = 0.001
## Ground: a flat heightfield centred on the rig, so the ground query runs at world magnitude too.
const FIELD_SAMPLES: int = 129
const FIELD_SPACING: float = 2.0
const DRIVE_FRAMES: int = 360
const METRICS: Array[String] = ["worst", "body", "bent", "broken"]


static func meta() -> Dictionary:
    return {
        "name": "a_rig_far_from_the_origin_is_the_rig_at_it",
        "proves": "the hero settled at 3.9 km, 100 km and 10 000 km from the origin rings, bends and breaks within the envelope of %d placements near it, the same rig with its frame pinned to the origin does not, and a drive from 100 km out crosses frames and covers the near drive's ground" % NEAR.size(),
        "builds_on": ["solver_settles_vehicle"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "each far metric (worst node speed, worst body node speed, beams bent > 1 mm, beams"
            + " broken) within [near min - spread, near max + spread], spread = near max - near"
            + " min; the pinned-frame control outside it; the far drive moves its frame and its"
            + " distance is within the same envelope of near drives"
        ),
        "why": (
            "measured before frames: at La Paz's own spawn the settled hero's body nodes moved 30x"
            + " faster than at the origin and settling bent 78 beams; at 10 km it broke 30. Beam"
            + " forces start from differences of float32 positions, whose error grows with"
            + " distance from the origin, not from each other."
        ),
        "budget_s": 120.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)

    var near: Array[Dictionary] = []
    for at: Vector2 in NEAR:
        var row: Dictionary = _settle(mod_dir, at, true)
        if (row["error"] as String) != "":
            return fail(row["error"] as String)
        near.append(row)
    var envelope: Dictionary = _envelope(near, METRICS)

    var reports: PackedStringArray = PackedStringArray()
    for at: Vector2 in FAR:
        var row: Dictionary = _settle(mod_dir, at, true)
        if (row["error"] as String) != "":
            return fail(row["error"] as String)
        var outside: String = _outside(row, envelope, METRICS)
        if outside != "":
            return fail("at %.0f m from the origin %s" % [at.length(), outside], row["worst"])
        reports.append("%.0f m: %s" % [at.length(), _describe(row)])

    var control: Dictionary = _settle(mod_dir, FAR[0], false)
    if (control["error"] as String) == "" and _outside(control, envelope, METRICS) == "":
        return fail(
            "with the frame pinned to the origin the rig at %.0f m stayed inside the envelope (%s):"
            % [FAR[0].length(), _describe(control)]
            + " this gate could not have seen the fault it is for",
            control["worst"]
        )

    var near_drives: Array[Dictionary] = []
    for at: Vector2 in NEAR:
        near_drives.append(_drive(mod_dir, at))
    var far_drive: Dictionary = _drive(mod_dir, FAR[1])
    if (far_drive["moves"] as int) < 1:
        return fail("the drive from %.0f m never moved its frame: nothing crossed" % FAR[1].length())
    var drive_envelope: Dictionary = _envelope(near_drives, ["distance", "broken"])
    var drive_outside: String = _outside(far_drive, drive_envelope, ["distance", "broken"])
    if drive_outside != "":
        return fail("the drive from %.0f m: %s" % [FAR[1].length(), drive_outside], far_drive["distance"])

    return ok(
        "near envelope %s; %s; pinned control %s; drive from 100 km covered %.2f m across %d"
        % [_describe_envelope(envelope), "; ".join(reports), _describe(control),
            far_drive["distance"], far_drive["moves"]]
        + " frame moves, near drives %.2f to %.2f m"
        % [drive_envelope["distance"][0], drive_envelope["distance"][1]],
        reports.size()
    )


## [min - spread, max + spread] per metric.
func _envelope(rows: Array[Dictionary], metrics: Array[String]) -> Dictionary:
    var out: Dictionary = {}
    for metric: String in metrics:
        var low: float = INF
        var high: float = -INF
        for row: Dictionary in rows:
            low = minf(low, float(row[metric]))
            high = maxf(high, float(row[metric]))
        var spread: float = high - low
        out[metric] = [low, high, low - spread, high + spread]
    return out


## Which metric of `row` lies outside the envelope, said in words; empty if none does.
func _outside(row: Dictionary, envelope: Dictionary, metrics: Array[String]) -> String:
    for metric: String in metrics:
        var bounds: Array = envelope[metric] as Array
        var value: float = float(row[metric])
        if value < (bounds[2] as float) or value > (bounds[3] as float):
            return "%s is %.4f, outside %.4f to %.4f (near runs %.4f to %.4f)" % [
                metric, value, bounds[2], bounds[3], bounds[0], bounds[1]]
    return ""


func _describe(row: Dictionary) -> String:
    return "worst %.3f, body %.3f m/s, %d bent, %d broken" % [
        row["worst"], row["body"], row["bent"], row["broken"]]


func _describe_envelope(envelope: Dictionary) -> String:
    var parts: PackedStringArray = PackedStringArray()
    for metric: String in METRICS:
        var bounds: Array = envelope[metric] as Array
        parts.append("%s %.3f-%.3f" % [metric, bounds[0], bounds[1]])
    return ", ".join(parts)


func _flat_field(solver: RefCounted, at: Vector2) -> void:
    var half: float = float(FIELD_SAMPLES - 1) * FIELD_SPACING * 0.5
    var heights: PackedFloat32Array = PackedFloat32Array()
    heights.resize(FIELD_SAMPLES * FIELD_SAMPLES)
    solver.set_ground(0.0, true)
    solver.set_heightfield(
        heights, FIELD_SAMPLES, FIELD_SAMPLES, Vector3(at.x - half, 0.0, at.y - half), FIELD_SPACING
    )


func _build(mod_dir: String, at: Vector2, frames: bool) -> Dictionary:
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        return {"error": rig["error"]}
    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_frame_follows(frames)
    _flat_field(solver, at)
    RigBuilder.place(solver, rig["truck"] as TruckParser, Vector3(at.x, 0.0, at.y), 0.0, 0.15)
    return {"error": "", "solver": solver, "truck": rig["truck"]}


## Settles, then watches a second substep by substep: the worst node speed, the worst body node
## speed, and the beams bent and broken since the rig was built.
func _settle(mod_dir: String, at: Vector2, frames: bool) -> Dictionary:
    var built: Dictionary = _build(mod_dir, at, frames)
    if (built["error"] as String) != "":
        return built
    var solver: RefCounted = built["solver"] as RefCounted
    var truck: TruckParser = built["truck"] as TruckParser
    var references: PackedFloat32Array = PackedFloat32Array()
    for beam: int in solver.beam_count():
        references.append(solver.get_beam_reference_length(beam))
    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / FRAME_HZ)
    for _i: int in SETTLE_FRAMES:
        solver.step(dt, chunk)
    var count: int = solver.node_count()
    var worst: float = 0.0
    var body: float = 0.0
    for _s: int in WATCH_FRAMES * chunk:
        solver.step(dt, 1)
        for node: int in count:
            var speed: float = solver.get_node_velocity(node).length()
            if not is_finite(speed):
                return {"error": "node %d went non-finite at %s" % [node, at]}
            worst = maxf(worst, speed)
            if node < truck.generated_from:
                body = maxf(body, speed)
    var bent: int = 0
    for beam: int in solver.beam_count():
        if absf(solver.get_beam_rest_length(beam) - references[beam]) > BENT_M:
            bent += 1
    return {
        "error": "", "worst": worst, "body": body, "bent": bent,
        "broken": solver.broken_beam_count(),
    }


## Settles, then full throttle in first for `DRIVE_FRAMES`: how far the rig's frame-built origin
## went, and how many times the solver's frame moved under it.
func _drive(mod_dir: String, at: Vector2) -> Dictionary:
    var built: Dictionary = _build(mod_dir, at, true)
    var solver: RefCounted = built["solver"] as RefCounted
    var truck: TruckParser = built["truck"] as TruckParser
    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / FRAME_HZ)
    for _i: int in 30:
        solver.step(dt, chunk)
    var moves_before: int = solver.frame_moves()
    # Read in world coordinates, which at 100 km are 7.8 mm coarse: a centimetre on a drive of
    # tens of metres, far inside what a drive's envelope is measured to.
    var start: Vector3 = ActorFrame.of(solver.get_positions(), truck.camera_nodes).origin
    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(1.0)
    for _f: int in DRIVE_FRAMES:
        solver.step(dt, chunk)
    var end: Vector3 = ActorFrame.of(solver.get_positions(), truck.camera_nodes).origin
    return {
        "distance": Vector2(end.x - start.x, end.z - start.z).length(),
        "moves": solver.frame_moves() - moves_before, "broken": solver.broken_beam_count(),
    }

