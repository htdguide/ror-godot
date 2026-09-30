extends GateBase
## Checks the ground contact law against the textbook result for a block on a slope.
##
## A mass on an incline stays put while the slope is shallower than the arctangent of the
## static friction coefficient, and slides at g·(sin θ − μ·cos θ) once it is steeper. Both
## numbers are closed form, come from the ground model's own coefficients, and were not
## chosen here — which is what makes this an oracle rather than a golden.
##
## The slope is applied by tilting gravity rather than the ground, which is the same problem
## in a rotated frame and needs nothing the solver does not already have.
##
## This is the gate that catches a friction law that is present but wrong. A rig that will
## not drive and a rig that slides downhill at rest are the same fault seen from two sides,
## and neither is visible in a test that only drops something onto flat ground.

const GRAVITY: float = 9.81
## Upstream's `concrete`: the default surface, and the one the solver starts with.
const STATIC_FRICTION: float = 1.2
const SLIDING_FRICTION: float = 0.75
const STRIBECK_VELOCITY: float = 6.0
const STRIBECK_ALPHA: float = 2.0
const HYDRODYNAMIC_FRICTION: float = 0.01
## Upstream caps the hydrodynamic term's contribution.
const HYDRODYNAMIC_CAP: float = 5.0
const SUBSTEP_HZ: float = 2000.0
const HOLD_SECONDS: float = 2.0
const SLIDE_SECONDS: float = 4.0
## A held node may creep by the smoothing term in the static branch, but not by a
## millimetre over two seconds.
const HOLD_TOLERANCE_M: float = 0.001
## The sliding acceleration is compared instant by instant against the model evaluated at
## the slip speed measured at that instant, so the comparison is exact and the tolerance is
## only integration error over one step.
const SLIDE_TOLERANCE: float = 0.005
## Well inside the static cone, and well outside it.
const SHALLOW_DEG: float = 40.0
const STEEP_DEG: float = 70.0
## A node with half the grip holds a correspondingly shallower slope, which is what proves
## the per-node coefficient is read at all.
const HALF_GRIP: float = 0.5


static func meta() -> Dictionary:
    return {
        "name": "ground_friction_oracle",
        "proves": "ground contact reproduces textbook static and sliding friction, and reads each node's own coefficient",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "held within %.0f mm below atan(mu); sliding acceleration within %.1f%% of"
            % [HOLD_TOLERANCE_M * 1000.0, SLIDE_TOLERANCE * 100.0]
            + " g(sin-mu*cos) at the measured slip; the limit angle scales with the node coefficient"
        ),
        "why": (
            "a vehicle drives through friction and nothing else, so a wrong friction law"
            + " shows up as a rig that will not pull or one that slides away at rest. Both"
            + " have a closed-form answer for a mass on a slope, so this needs no golden"
            + " and no number of this project's choosing."
        ),
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var shallow: Dictionary = _slide(SHALLOW_DEG, 1.0, HOLD_SECONDS)
    if (shallow["error"] as String) != "":
        return fail(shallow["error"] as String)
    if shallow["distance"] as float > HOLD_TOLERANCE_M:
        return fail(
            "on a %.0f deg slope the node moved %.4f m: static friction is not holding"
            % [SHALLOW_DEG, shallow["distance"]],
            shallow["distance"]
        )

    var steep: Dictionary = _slide(STEEP_DEG, 1.0, SLIDE_SECONDS)
    if (steep["error"] as String) != "":
        return fail(steep["error"] as String)
    var expected: float = _expected_acceleration(STEEP_DEG, steep["slip"] as float, 1.0)
    var measured: float = steep["acceleration"] as float
    var relative: float = absf(measured - expected) / expected
    if relative > SLIDE_TOLERANCE:
        return fail(
            "on a %.0f deg slope the node accelerated at %.3f m/s2 against %.3f expected,"
            % [STEEP_DEG, measured, expected]
            + " off by %.1f%%" % (relative * 100.0),
            relative
        )

    # Half the grip halves the tangent of the limit angle, so a slope the full-grip node
    # holds must be one this node slides down.
    var limit_deg: float = rad_to_deg(atan(STATIC_FRICTION * HALF_GRIP))
    var weak: Dictionary = _slide(SHALLOW_DEG, HALF_GRIP, HOLD_SECONDS)
    if (weak["error"] as String) != "":
        return fail(weak["error"] as String)
    if weak["distance"] as float <= HOLD_TOLERANCE_M:
        return fail(
            "a node with friction %.2f held a %.0f deg slope, past its %.1f deg limit:"
            % [HALF_GRIP, SHALLOW_DEG, limit_deg]
            + " the node's own coefficient is not being read",
            weak["distance"]
        )
    return ok(
        (
            "held %.0f deg within %.4f mm (limit %.1f deg); slid %.0f deg at %.4f m/s2"
            + " against %.4f expected at %.2f m/s slip (%.2f%%); friction %.2f slid %.3f m"
            + " at %.0f deg"
        )
        % [
            SHALLOW_DEG, (shallow["distance"] as float) * 1000.0,
            rad_to_deg(atan(STATIC_FRICTION)), STEEP_DEG, measured, expected,
            steep["slip"], relative * 100.0, HALF_GRIP, weak["distance"], SHALLOW_DEG,
        ],
        relative
    )


## The model's own answer for the acceleration of a mass sliding down `slope_deg` at
## `slip` m/s: gravity along the slope, less the Stribeck friction coefficient at that slip
## speed plus the hydrodynamic term, times gravity into it.
func _expected_acceleration(slope_deg: float, slip: float, friction: float) -> float:
    var angle: float = deg_to_rad(slope_deg)
    var stribeck: float = (
        SLIDING_FRICTION
        + (STATIC_FRICTION - SLIDING_FRICTION)
        * exp(-pow(slip / STRIBECK_VELOCITY, STRIBECK_ALPHA))
    )
    var coefficient: float = stribeck + minf(HYDRODYNAMIC_FRICTION * slip, HYDRODYNAMIC_CAP)
    return GRAVITY * (sin(angle) - coefficient * friction * cos(angle))


## One node on a slope of `slope_deg`, with friction `friction`, for `seconds`.
## Returns {"error", "distance", "acceleration", "slip"}: the distance travelled along the
## slope, and the acceleration and slip speed measured over the final step.
func _slide(slope_deg: float, friction: float, seconds: float) -> Dictionary:
    var solver: RefCounted = ClassDB.instantiate("RorSolver") as RefCounted
    if solver == null:
        return {"error": "RorSolver is not registered: the GDExtension did not load"}
    solver.add_node(Vector3.ZERO, 100.0)
    solver.set_node_friction(0, friction)
    var angle: float = deg_to_rad(slope_deg)
    # Downhill is +X, into the slope is -Y: the incline seen from a frame where the surface
    # is the solver's flat plane.
    solver.set_gravity(Vector3(GRAVITY * sin(angle), -GRAVITY * cos(angle), 0.0))
    solver.set_ground(0.0, true)

    var dt: float = 1.0 / SUBSTEP_HZ
    for _i: int in int(seconds * SUBSTEP_HZ):
        solver.step(dt, 1)
    var final: Vector3 = solver.get_node_position(0)
    if not is_finite(final.length()):
        return {"error": "the node's position went non-finite on a %.0f deg slope" % slope_deg}
    # One more step, measured on its own: the model is a function of the slip speed, so it
    # is compared at a known slip speed rather than averaged over a run during which the
    # speed, and therefore the answer, changed.
    var slip: float = solver.get_node_velocity(0).x
    solver.step(dt, 1)
    return {
        "error": "",
        "distance": absf(final.x),
        "acceleration": (solver.get_node_velocity(0).x - slip) / dt,
        "slip": absf(slip),
    }
