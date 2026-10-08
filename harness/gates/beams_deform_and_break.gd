extends GateBase
## A beam pulled past its yield stress bends permanently, and one pulled past its strength breaks.
##
## Before this, every beam in the project was a perfect spring: a rig could be driven into a wall
## at any speed, bounce off, and be exactly the shape it started. A human session reported it as
## "too stiff and not bending as it is supposed to", which is precisely what a structure with no
## plasticity does.
##
## Upstream's law is in `ActorForcesEuler.cpp`, and the arithmetic is quotable, which is what this
## gate checks against. Past the yield stress the beam's *rest length* moves by the part of the
## extension that was not elastic:
##
##     yield_length = maxneg / k                      (negative: maxneg is the tension yield)
##     deform       = extension + yield_length * (1 - plastic_coef)
##     L           += deform
##
## So with no plastic coefficient a beam stretched by `e` past a yield at stress `D` keeps `D / k`
## of elastic travel and takes the rest as a permanent set. That is one line of arithmetic, and it
## is checked here as arithmetic rather than looked at.

## The test beam. A metre long, a stiff-ish structural rate, and a yield well inside what the test
## stretches it by.
const REST_LENGTH_M: float = 1.0
const SPRING: float = 1000000.0
const DAMPING: float = 0.0
const DEFORM_N: float = 100000.0
const STRENGTH_N: float = 400000.0
const SUBSTEP_HZ: float = 2000.0
## How far the beam is stretched in the yielding case: past the yield at 0.1 m, inside the
## strength at 0.4 m.
const STRETCH_M: float = 0.25
## And in the case that has to stay elastic: inside the yield.
const ELASTIC_STRETCH_M: float = 0.05
## Past the strength, which is 0.4 m of stretch at this rate.
const BREAKING_STRETCH_M: float = 0.6
## How far the measured rest length may sit from the closed-form answer.
##
## Not float noise: upstream never computes an exact beam length. Every length in a Rigs of Rods
## rig is divided by the Quake reciprocal square root, which is accurate to about 0.2%, and this
## project reproduces that bit for bit because the force laws were tuned against it. So a closed
## form derived from the exact extension is off by 0.2% of the beam's length — 2.5 mm here,
## measured at 1.9 mm — and the allowance is that error with a little margin, as the parity work
## says any closed-form oracle here needs.
const TOLERANCE_M: float = 0.004
## A beam that does not yield must not move its rest length at all, and that one is exact.
const UNCHANGED_TOLERANCE_M: float = 0.0005


static func meta() -> Dictionary:
    return {
        "name": "beams_deform_and_break",
        "proves": "a beam past its yield stress takes a permanent set of exactly the inelastic part of its extension, a beam inside it returns unchanged, and a beam past its strength breaks and carries nothing",
        # the spring law has to be right before what happens past it can be.
        "builds_on": ["solver_physics_oracle"],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "rest length within %.3f m of upstream's own deform arithmetic — its approximate"
            % TOLERANCE_M + " square root's own error — and unchanged inside the"
            + " yield; broken and carrying no force past the strength"
        ),
        "why": (
            "without plasticity a vehicle is a very stiff spring: it can be driven into a wall at"
            + " any speed and come away the shape it started, which is what a session reported."
            + " Upstream's deform arithmetic is three lines and quotable, so it is checked as"
            + " arithmetic rather than by looking at a crumpled truck."
        ),
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var elastic: Dictionary = _stretch(ELASTIC_STRETCH_M)
    if (elastic["error"] as String) != "":
        return fail(elastic["error"] as String)
    if absf((elastic["rest_length"] as float) - REST_LENGTH_M) > UNCHANGED_TOLERANCE_M:
        return fail(
            "stretched %.3f m, inside its %.3f m of elastic travel, the beam's rest length moved"
            % [ELASTIC_STRETCH_M, DEFORM_N / SPRING]
            + " to %.4f m from %.4f: it is yielding when it should not"
            % [elastic["rest_length"] as float, REST_LENGTH_M],
            (elastic["rest_length"] as float) - REST_LENGTH_M
        )

    var yielded: Dictionary = _stretch(STRETCH_M)
    if (yielded["error"] as String) != "":
        return fail(yielded["error"] as String)
    # Upstream's arithmetic, quoted: the elastic part is the yield stress over the rate, and
    # everything beyond it becomes a permanent set.
    var elastic_travel: float = DEFORM_N / SPRING
    var wanted: float = REST_LENGTH_M + (STRETCH_M - elastic_travel)
    var measured: float = yielded["rest_length"] as float
    if absf(measured - wanted) > TOLERANCE_M:
        return fail(
            "stretched %.3f m past a yield at %.0f N, the beam's rest length is %.4f m where"
            % [STRETCH_M, DEFORM_N, measured]
            + " upstream's arithmetic gives %.4f m" % wanted,
            measured - wanted
        )
    if bool(yielded["broken"]):
        return fail("the beam broke at %.3f m of stretch, inside its strength" % STRETCH_M)

    var broken: Dictionary = _stretch(BREAKING_STRETCH_M)
    if (broken["error"] as String) != "":
        return fail(broken["error"] as String)
    if not bool(broken["broken"]):
        return fail(
            "stretched %.3f m, which is %.0f N against a strength of %.0f N, the beam did not"
            % [BREAKING_STRETCH_M, BREAKING_STRETCH_M * SPRING, STRENGTH_N]
            + " break",
            broken["rest_length"]
        )
    # A broken beam is not a weak beam: released, its far end must stay where it was left.
    if (broken["drift"] as float) > 0.01:
        return fail(
            "released after breaking, the beam's far end moved %.3f m: it is still pulling"
            % (broken["drift"] as float),
            broken["drift"]
        )
    if (yielded["drift"] as float) < 0.01:
        return fail(
            "released after yielding, the beam's far end moved %.4f m: a bent beam should still"
            % (yielded["drift"] as float) + " pull",
            yielded["drift"]
        )
    return ok(
        "elastic at %.0f mm; at %.0f mm the rest length is %.4f m against upstream's %.4f;"
        % [ELASTIC_STRETCH_M * 1000.0, STRETCH_M * 1000.0, measured, wanted]
        + " broken at %.0f mm, its end drifting %.4f m against %.3f m for the bent one"
        % [BREAKING_STRETCH_M * 1000.0, broken["drift"] as float, yielded["drift"] as float],
        measured - wanted
    )


## Builds a one-beam rig, holds it stretched by `stretch` for a step, and reports what became of
## the beam. Both nodes are immovable, so the extension is exactly what is asked for rather than
## whatever the two ends drifted to.
func _stretch(stretch: float) -> Dictionary:
    var solver: RefCounted = ClassDB.instantiate("RorSolver") as RefCounted
    if solver == null:
        return {"error": "RorSolver is not registered", "rest_length": 0.0, "broken": false,
            "drift": 0.0}
    solver.set_gravity(Vector3.ZERO)
    solver.set_ground(-100.0, false)
    solver.add_node(Vector3.ZERO, 1.0)
    solver.add_node(Vector3(REST_LENGTH_M + stretch, 0.0, 0.0), 1.0)
    solver.set_node_immovable(0, true)
    solver.set_node_immovable(1, true)
    var beam: int = solver.add_beam(0, 1, REST_LENGTH_M, SPRING, DAMPING)
    # A structural beam, so it may yield: the fifth argument is what `BEAM_HYDRO` actuators turn off.
    solver.set_beam_limits(beam, DEFORM_N, STRENGTH_N, 0.0, true)
    solver.step(1.0 / SUBSTEP_HZ, 1)
    var rest_length: float = solver.get_beam_rest_length(beam)
    var broken: bool = solver.beam_broken(beam)
    # Whether it is still pulling: let the far end go and see whether anything draws it back. A
    # broken beam is not a weak beam, it is no beam, so the node has to stay where it was left.
    var started: Vector3 = solver.get_node_position(1)
    solver.set_node_immovable(1, false)
    solver.step(1.0 / SUBSTEP_HZ, int(SUBSTEP_HZ * 0.25))
    var drift: float = solver.get_node_position(1).distance_to(started)
    return {
        "error": "",
        "rest_length": rest_length,
        "broken": broken,
        "drift": drift,
    }
