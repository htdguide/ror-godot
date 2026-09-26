extends GateBase
## Checks the solver against physics, not against itself.
##
## A soft-body solver can be self-consistent and still wrong, and a golden would only
## record whatever it did last time. A mass on a spring has an exact period and an exact
## static deflection; a damped one has an exact decay. Those are the oracle here, and they
## are compared against a solver that deliberately does not use exact arithmetic — see
## ror_approx.h — so each allowance below is derived from that error rather than set flat.
## come from the textbook rather than from this project.

## Deliberately stiff and light, so the period is short enough to measure in a reasonable
## number of substeps and the test exercises the integrator rather than a soft toy.
const MASS_KG: float = 2.0
const SPRING_N_PER_M: float = 800.0
const GRAVITY: float = 9.81
const SUBSTEP_HZ: float = 2000.0
## Upstream runs its physics at 2 kHz, so that is the step this is checked at.
const DT: float = 1.0 / SUBSTEP_HZ
## Symplectic Euler's period is accurate to order dt, so a fraction of a percent is the
## right bound: tight enough to catch a wrong force law, loose enough not to fail on the
## integrator's own known bias.
const PERIOD_TOLERANCE: float = 0.01
const DEFLECTION_TOLERANCE: float = 0.005
## Upstream measures every beam length with the Quake reciprocal square root, whose relative
## error reaches this, and computes each beam's *rest* length exactly at spawn. So a beam sits
## at equilibrium where its approximately-measured length equals its exactly-measured rest
## length, which is displaced from the true equilibrium by up to this fraction of the beam.
##
## That displacement is a length error, not a deflection error, so against a deflection of a
## few millimetres on a beam of a metre it is amplified by their ratio — which is why the
## allowance below is derived from the geometry of each case rather than stated as a percent.
const INV_SQRT_RELATIVE_ERROR: float = 0.00175
## Symplectic Euler on an exact linear spring conserves a nearby quantity and keeps the true
## energy inside a narrow band. Upstream's beam length is not exact — it comes from the Quake
## reciprocal square root — so the force is not exactly linear in extension and the band is
## wider. What still has to hold is that it is a band: measured over 300 s, six hundred
## thousand steps, the worst drift reaches 5.31% in the first five seconds and never exceeds
## it, while the instantaneous figure cycles between 0.07% and 4.96%. Bounded, not growing,
## which is the property that keeps a rig from coming apart on its own.
const ENERGY_DRIFT_TOLERANCE: float = 0.08


static func meta() -> Dictionary:
    return {
        "name": "solver_physics_oracle",
        "proves": "the node/beam solver reproduces spring-mass period, static deflection and energy behaviour",
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "period within %.0f%%, deflection within %.1f%%, undamped energy drift under %.0f%%"
            % [PERIOD_TOLERANCE * 100.0, DEFLECTION_TOLERANCE * 100.0, ENERGY_DRIFT_TOLERANCE * 100.0]
        ),
        "why": (
            "these are closed-form results from mechanics, not values recorded from this"
            + " code. A solver that is merely self-consistent passes a golden and still"
            + " gets the spring law wrong."
        ),
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var period: Dictionary = _check_period()
    if period.has("error"):
        return fail(period["error"] as String, period.get("measured"))
    var deflection: Dictionary = _check_static_deflection()
    if deflection.has("error"):
        return fail(deflection["error"] as String, deflection.get("measured"))
    var energy: Dictionary = _check_energy()
    if energy.has("error"):
        return fail(energy["error"] as String, energy.get("measured"))
    return ok(
        "period %.4f s against %.4f s expected, deflection %.2f mm against %.2f mm, energy drift %.2f%%"
        % [
            float(period["measured"]), float(period["expected"]),
            float(deflection["measured"]) * 1000.0, float(deflection["expected"]) * 1000.0,
            float(energy["measured"]) * 100.0
        ],
        period["measured"]
    )


## T = 2*pi*sqrt(m/k) for an undamped mass on a spring.
func _check_period() -> Dictionary:
    var solver: RefCounted = _new_solver()
    solver.set_gravity(Vector3.ZERO)
    var anchor: int = solver.add_node(Vector3.ZERO, MASS_KG)
    solver.set_node_immovable(anchor, true)
    var bob: int = solver.add_node(Vector3(0.0, -1.0, 0.0), MASS_KG)
    solver.add_beam(anchor, bob, 1.0, SPRING_N_PER_M, 0.0)
    # Displace and release.
    solver.set_node_position(bob, Vector3(0.0, -1.05, 0.0))

    var expected: float = TAU * sqrt(MASS_KG / SPRING_N_PER_M)
    # Count zero crossings of the displacement to time whole half-periods.
    var previous: float = solver.get_node_position(bob).y + 1.0
    var crossings: int = 0
    var first_crossing_step: int = -1
    var last_crossing_step: int = -1
    var steps: int = int(expected * SUBSTEP_HZ * 12.0)
    for i: int in steps:
        solver.step(DT, 1)
        var displacement: float = solver.get_node_position(bob).y + 1.0
        if signf(displacement) != signf(previous) and previous != 0.0:
            crossings += 1
            if first_crossing_step < 0:
                first_crossing_step = i
            last_crossing_step = i
        previous = displacement
    if crossings < 4:
        return {"error": "spring did not oscillate: %d zero crossings in %d steps" % [crossings, steps]}

    var half_periods: int = crossings - 1
    var measured: float = float(last_crossing_step - first_crossing_step) * DT * 2.0 / float(half_periods)
    var error: float = absf(measured - expected) / expected
    if error > PERIOD_TOLERANCE:
        return {
            "error": "period is %.5f s, expected %.5f s (%.1f%% off)" % [measured, expected, error * 100.0],
            "measured": measured,
        }
    return {"measured": measured, "expected": expected}


## x = m*g/k at rest, for a mass hanging on a spring.
func _check_static_deflection() -> Dictionary:
    var solver: RefCounted = _new_solver()
    solver.set_gravity(Vector3(0.0, -GRAVITY, 0.0))
    var anchor: int = solver.add_node(Vector3.ZERO, MASS_KG)
    solver.set_node_immovable(anchor, true)
    var bob: int = solver.add_node(Vector3(0.0, -1.0, 0.0), MASS_KG)
    # Damped, so it settles rather than oscillating forever.
    solver.add_beam(anchor, bob, 1.0, SPRING_N_PER_M, 40.0)
    solver.step(DT, int(SUBSTEP_HZ * 6.0))

    var expected: float = MASS_KG * GRAVITY / SPRING_N_PER_M
    var measured: float = absf(solver.get_node_position(bob).y + 1.0)
    var error: float = absf(measured - expected) / expected
    # The rest length is 1 m, so the length-measurement error is that fraction of a metre,
    # against a deflection of about 25 mm.
    var allowance: float = DEFLECTION_TOLERANCE + INV_SQRT_RELATIVE_ERROR * (1.0 + expected) / expected
    if error > allowance:
        return {
            "error": "static deflection is %.4f m, expected %.4f m (%.1f%% off, allowed %.1f%%)"
            % [measured, expected, error * 100.0, allowance * 100.0],
            "measured": measured,
        }
    return {"measured": measured, "expected": expected}


## An undamped spring must not gain energy. Symplectic Euler does not conserve energy
## exactly, but it bounds the error instead of letting it grow, which is the property that
## keeps a rig from exploding.
func _check_energy() -> Dictionary:
    var solver: RefCounted = _new_solver()
    solver.set_gravity(Vector3.ZERO)
    var anchor: int = solver.add_node(Vector3.ZERO, MASS_KG)
    solver.set_node_immovable(anchor, true)
    var bob: int = solver.add_node(Vector3(0.0, -1.0, 0.0), MASS_KG)
    solver.add_beam(anchor, bob, 1.0, SPRING_N_PER_M, 0.0)
    solver.set_node_position(bob, Vector3(0.0, -1.05, 0.0))

    var initial: float = solver.total_energy()
    var worst: float = 0.0
    for i: int in 200:
        solver.step(DT, 100)
        var drift: float = absf(solver.total_energy() - initial) / maxf(absf(initial), 0.0001)
        worst = maxf(worst, drift)
    if worst > ENERGY_DRIFT_TOLERANCE:
        return {
            "error": "energy drifted %.1f%% over 20000 steps, over %.0f%%"
            % [worst * 100.0, ENERGY_DRIFT_TOLERANCE * 100.0],
            "measured": worst,
        }
    return {"measured": worst}


func _new_solver() -> RefCounted:
    return ClassDB.instantiate("RorSolver") as RefCounted
