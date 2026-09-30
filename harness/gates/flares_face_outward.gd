extends GateBase
## Every lamp sits on the vehicle and faces away from it.
##
## A flare is placed from a triad of nodes, and its facing is the cross product of two edges
## of that triad. Cross products have a handedness: take the two edges the other way round and
## every lamp on the vehicle points into the bodywork instead of out of it. Nothing about that
## is visible in a still of a parked truck in daylight — the lens is drawn either way — and it
## is entirely visible the moment the headlights are switched on at night, by which time it
## looks like a lighting bug rather than a parsing one.
##
## So the check is geometric and needs no lighting: a lamp must lie within the vehicle's own
## bounds, and its normal must have a positive component along the direction from the
## vehicle's centre to the lamp. That is true of every real lamp on every vehicle and false
## for all of them at once if the cross product is the wrong way round.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
## The hero truck declares 12. Stated so that losing the section silently fails here.
const EXPECTED_FLARES: int = 12
## A lamp is mounted on the skin, so it may sit a little proud of the bodywork's bounds.
const BOUNDS_MARGIN_M: float = 0.25
## How squarely a lamp must face away from the vehicle's centre. Lamps are mounted on curved
## panels and raked bumpers, so this is not demanding — it is catching a sign, not measuring
## aim.
const MIN_OUTWARD: float = 0.1


static func meta() -> Dictionary:
    return {
        "name": "flares_face_outward",
        "proves": "every parsed flare becomes a lamp that sits on the vehicle and faces away from it",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "%d lamps, each within %.2f m of the body bounds and facing outward by at least"
            % [EXPECTED_FLARES, BOUNDS_MARGIN_M]
            + " %.2f" % MIN_OUTWARD
        ),
        "why": (
            "a flare's facing is a cross product, and the wrong handedness points every lamp"
            + " on the vehicle inward at once. That is invisible in daylight and looks like a"
            + " lighting fault at night, so it is worth catching as the geometry question it"
            + " actually is."
        ),
        "budget_s": 60.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var err: String = harness.setup_for("hero_3q")
    if err != "":
        return fail(err)

    var built: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    var truck: TruckParser = built["truck"] as TruckParser
    harness.world.add_child(built["root"] as Node3D)

    if truck.flares.size() != EXPECTED_FLARES:
        return fail(
            "%s declares %d flares, expected %d: the section is not being read as it was"
            % [TRUCK, truck.flares.size(), EXPECTED_FLARES],
            truck.flares.size()
        )
    var lamps: Array[Node3D] = built["lamps"] as Array[Node3D]
    if lamps.size() != truck.flares.size():
        return fail(
            "%d flares were parsed but %d lamps were built" % [truck.flares.size(), lamps.size()]
        )

    # The bodywork, not the whole vehicle: the wheels stick out past the panels a lamp is on.
    var body: AABB = VehicleBuilder.world_bounds(built["root"] as Node3D)
    var centre: Vector3 = body.get_center()
    var grown: AABB = body.grow(BOUNDS_MARGIN_M)
    var worst_outward: float = INF
    var worst_at: int = 0
    var outside: PackedStringArray = PackedStringArray()
    for index: int in lamps.size():
        var lamp: Node3D = lamps[index]
        var position: Vector3 = lamp.global_transform.origin
        if not grown.has_point(position):
            outside.append("%s at %v" % [lamp.name, position])
            continue
        # The lamp looks down its own -Z, and outward is away from the vehicle's centre.
        var facing: Vector3 = -lamp.global_transform.basis.z
        var outward: Vector3 = position - centre
        if outward.length_squared() == 0.0:
            continue
        var alignment: float = facing.dot(outward.normalized())
        if alignment < worst_outward:
            worst_outward = alignment
            worst_at = index
    if outside.size() > 0:
        return fail(
            "%d lamps are not on the vehicle: %s" % [outside.size(), ", ".join(outside)],
            outside.size()
        )
    if worst_outward < MIN_OUTWARD:
        return fail(
            "lamp %d (%s) faces %.2f against the outward direction: the lamps are pointing"
            % [worst_at, lamps[worst_at].name, worst_outward]
            + " into the bodywork",
            worst_outward
        )
    return ok(
        "%d lamps on the bodywork, all facing outward; the squarest-on is %s and the most"
        % [lamps.size(), lamps[worst_at].name]
        + " oblique faces outward by %.2f" % worst_outward,
        worst_outward
    )
