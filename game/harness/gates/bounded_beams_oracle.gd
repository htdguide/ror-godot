extends GateBase
## Checks each bounded beam law against the force it is defined to produce.
##
## A shock, a rope and a support beam are all springs with a rule about which way they work.
## Every rule has a closed form, so the force each one produces at a stated extension can be
## computed and compared rather than eyeballed:
##
##   normal    F = -k*e everywhere
##   rope      F = -k*e stretched, 0 slack
##   support   F = -k*e compressed, 0 stretched
##   shock     F = -k*e inside its travel; past a bound k ramps towards the structural rate
##             in proportion to how far past it is, so F = -(k + (K-k)*overshoot)*e
##
## The force is measured from what the solver actually does to a node — its change in velocity
## over one step, times its mass — so nothing here reads the implementation's own arithmetic
## back to itself.
##
## These laws are the difference between suspension and springs. Without them a shock has no
## bump stop and travels straight through its limits, a rope pushes as hard as it pulls, and a
## support beam holds a part down as well as up.

const SUBSTEP_HZ: float = 2000.0
const MASS: float = 10.0
const REST_LENGTH: float = 1.0
const SPRING: float = 20000.0
## What a shock hands over to past its travel, standing in for a rig's structural default.
const BOUND_SPRING: float = 2000000.0
const SHORT_BOUND: float = 0.1
const LONG_BOUND: float = 0.2
## Float arithmetic over one step, not physics: the comparison is exact in principle.
const TOLERANCE: float = 0.001


static func meta() -> Dictionary:
    return {
        "name": "bounded_beams_oracle",
        "proves": "shock, rope and support beams produce the force their law defines, inside their travel and past it",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "measured force within %.1f%% of the law at every extension tested" % (
            TOLERANCE * 100.0
        ),
        "why": (
            "each law has a closed form, and the force is read back from what the solver did"
            + " to a node rather than from the code that computed it. A rope that pushes and"
            + " a shock with no bump stop both look like an ordinary spring until something"
            + " reaches the end of its travel, which is exactly when it matters."
        ),
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var cases: Array[Dictionary] = [
        {"name": "normal stretched", "bound": BeamRows.BOUND_NORMAL, "extension": 0.05},
        {"name": "normal compressed", "bound": BeamRows.BOUND_NORMAL, "extension": -0.05},
        {"name": "rope taut", "bound": BeamRows.BOUND_ROPE, "extension": 0.05},
        {"name": "rope slack", "bound": BeamRows.BOUND_ROPE, "extension": -0.05},
        {"name": "support loaded", "bound": BeamRows.BOUND_SUPPORT, "extension": -0.05},
        {"name": "support lifted", "bound": BeamRows.BOUND_SUPPORT, "extension": 0.05},
        {"name": "shock in travel", "bound": BeamRows.BOUND_SHOCK, "extension": 0.1},
        {"name": "shock past its stop", "bound": BeamRows.BOUND_SHOCK, "extension": 0.3},
        {"name": "shock in bump", "bound": BeamRows.BOUND_SHOCK, "extension": -0.05},
        {"name": "shock through the bump stop", "bound": BeamRows.BOUND_SHOCK, "extension": -0.25},
    ]
    var report: PackedStringArray = PackedStringArray()
    var worst: float = 0.0
    for test: Dictionary in cases:
        var extension: float = test["extension"] as float
        var bound: int = test["bound"] as int
        var measured: float = _measure(bound, extension)
        if not is_finite(measured):
            return fail("%s produced a non-finite force" % test["name"])
        var expected: float = -_effective_spring(bound, extension) * extension
        var scale: float = maxf(absf(expected), SPRING * absf(extension))
        var relative: float = absf(measured - expected) / scale
        worst = maxf(worst, relative)
        if relative > TOLERANCE:
            return fail(
                "%s at %+.3f m: the beam pulled %.1f N against %.1f N from its own law"
                % [test["name"], extension, measured, expected],
                relative
            )
        report.append("%s %+.0f N" % [test["name"], measured])
    return ok(
        "10 extensions, worst %.4f%% from the law: %s" % [worst * 100.0, ", ".join(report)],
        worst
    )


## The spring the law says applies at this extension.
func _effective_spring(bound: int, extension: float) -> float:
    match bound:
        BeamRows.BOUND_ROPE:
            return 0.0 if extension < 0.0 else SPRING
        BeamRows.BOUND_SUPPORT:
            return 0.0 if extension > 0.0 else SPRING
        BeamRows.BOUND_SHOCK:
            var overshoot: float = 0.0
            if extension > LONG_BOUND * REST_LENGTH:
                overshoot = extension - LONG_BOUND * REST_LENGTH
            elif extension < -SHORT_BOUND * REST_LENGTH:
                overshoot = -extension - SHORT_BOUND * REST_LENGTH
            return SPRING + (BOUND_SPRING - SPRING) * overshoot
    return SPRING


## The force the solver puts on the free node of a two-node beam held at `extension`.
##
## Read from the node's change in velocity over one step rather than from the beam: a step
## integrates the force accumulated during the one before it, so the second step moves the
## node by exactly the force computed at the position it started from.
func _measure(bound: int, extension: float) -> float:
    var solver: RefCounted = ClassDB.instantiate("RorSolver") as RefCounted
    if solver == null:
        return NAN
    solver.add_node(Vector3.ZERO, MASS)
    solver.add_node(Vector3(REST_LENGTH + extension, 0.0, 0.0), MASS)
    solver.set_node_immovable(0, true)
    # No damping, so the force is the spring law alone and does not depend on a velocity the
    # test would also have to predict.
    solver.add_beam(0, 1, REST_LENGTH, SPRING, 0.0)
    solver.set_beam_bounds(0, bound, SHORT_BOUND, LONG_BOUND, BOUND_SPRING, 0.0, 1.0)
    solver.set_gravity(Vector3.ZERO)
    solver.set_air_drag(0.0, false)

    var dt: float = 1.0 / SUBSTEP_HZ
    solver.step(dt, 1)
    solver.step(dt, 1)
    return solver.get_node_velocity(1).x * MASS / dt
