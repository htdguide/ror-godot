extends GateBase
## Proves the C++ bridge loads and that it computes exactly what the GDScript reference
## computes.
##
## Two claims in one place on purpose: a parity check is worthless if the binary silently
## failed to load, and a load check is worthless if the maths then disagrees. Keeping the
## readable GDScript version honest matters because it is what everyone reads when asking
## what the bridge does.

const POSE_COUNT: int = 64
## 0.1 mm. The C++ side works in float32 and GDScript in float64, so exact agreement is
## impossible; the cross product and normalise in the triad frame amplify float32's
## relative epsilon to a few micrometres on metre-scale operands. This bound sits an
## order of magnitude above that and an order of magnitude below the 1 mm visual bound
## from ADR 0002, so it catches a real divergence such as a transposed basis or a
## swapped axis while ignoring precision.
const MAX_DELTA_M: float = 0.0001
const SPREAD_M: float = 4.0


static func meta() -> Dictionary:
    return {
        "name": "extension_parity",
        "proves": "the C++ GDExtension loads and reproduces the GDScript FlexBody reference exactly",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "max difference < %s m over %d randomised triads" % [MAX_DELTA_M, POSE_COUNT],
        "why": (
            "float32 in C++ against float64 in GDScript cannot agree bit for bit: the"
            + " cross product and normalise in the triad frame amplify float32 epsilon to"
            + " a few micrometres on metre-scale operands. 0.1 mm sits an order of"
            + " magnitude above that and an order below the 1 mm visual bound from ADR"
            + " 0002, so it catches a transposed basis or swapped axis, not precision."
        ),
        "budget_s": 20.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    if not ClassDB.class_exists("RorFlex"):
        return fail(
            "RorFlex is not registered: the GDExtension did not load."
            + " Build it with 'cd extension && scons target=template_debug'."
        )
    var flex: RefCounted = ClassDB.instantiate("RorFlex") as RefCounted
    if flex == null:
        return fail("RorFlex is registered but could not be instantiated")

    var rng: RandomNumberGenerator = harness.rng
    var worst: float = 0.0
    var worst_case: String = ""
    for pose: int in POSE_COUNT:
        var nodes: PackedVector3Array = PackedVector3Array()
        for i: int in 3:
            nodes.append(
                Vector3(
                    rng.randf_range(-SPREAD_M, SPREAD_M),
                    rng.randf_range(-SPREAD_M, SPREAD_M),
                    rng.randf_range(-SPREAD_M, SPREAD_M)
                )
            )
        var coords: Vector3 = Vector3(
            rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)
        )
        var expected: Vector3 = FlexReference.deform_vertex(nodes, 0, 1, 2, coords, Vector3.ZERO)
        var actual: Vector3 = flex.deform_vertex(nodes, 0, 1, 2, coords, Vector3.ZERO)
        var delta: float = (expected - actual).length()
        if delta > worst:
            worst = delta
            worst_case = "pose %d: gdscript %s vs c++ %s" % [pose, expected, actual]

        # Bind coordinates must round-trip: deforming the bind coordinates of a vertex
        # has to land back on that vertex.
        var round_trip: Vector3 = flex.deform_vertex(
            nodes, 0, 1, 2, flex.bind_coords(nodes, 0, 1, 2, expected), Vector3.ZERO
        )
        var round_delta: float = (round_trip - expected).length()
        if round_delta > worst:
            worst = round_delta
            worst_case = "pose %d round trip: %s vs %s" % [pose, expected, round_trip]

    if worst > MAX_DELTA_M:
        return fail("max difference %s m exceeds %s m; %s" % [worst, MAX_DELTA_M, worst_case], worst)
    return ok(
        "%s: %d triads agree within %s m" % [flex.version(), POSE_COUNT, worst], worst
    )
