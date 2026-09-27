extends GateBase
## A rig that declares a fuselage is dragged as a body, not node by node — and it is the
## difference between a truck that does 63 km/h and one that does 300.
##
## Upstream has two aerodynamic models and chooses between them by one thing: whether the rig's
## file has a `fusedrag` section. Without one, every node gets viscous turbulent drag. With one,
## the whole rig gets a single flat-plate force from the fuselage's own width. They are not close
## to each other — the hero truck's fuselage is 0.1 m wide, which is almost no drag at all, while
## three hundred nodes of turbulent drag at road speed is thousands of newtons.
##
## Given the wrong one, the hero truck stopped accelerating at 63 km/h in fourth gear with the
## throttle on the floor, which is what a session reported as "max speed is around 60". So this
## measures the law itself against its closed form, and then measures what it does to a real rig.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const SUBSTEP_HZ: float = 2000.0
## The test rig for the law: two nodes, no beams, moving at a known speed.
const TEST_SPEED_MS: float = 20.0
const TEST_MASS_KG: float = 100.0
const TEST_WIDTH_M: float = 2.0
## Sea-level air density, from upstream's own tropospheric model at zero altitude.
const AIR_DENSITY: float = 101325.0 * 0.0000120896
## How far the measured force may sit from the closed form. Float arithmetic only: both sides are
## the same three multiplications.
const FORCE_TOLERANCE: float = 0.02
## What the hero truck has to reach with its own fuselage, and what it reached without one.
const RUN_SECONDS: float = 30.0
const MIN_TOP_SPEED_KMH: float = 150.0
const WITHOUT_FUSELAGE_KMH: float = 63.0


static func meta() -> Dictionary:
    return {
        "name": "a_rig_is_dragged_the_way_its_file_says",
        "proves": "a rig declaring a fuselage is dragged by upstream's flat-plate law rather than node-by-node turbulent drag, and so reaches the speed its gearing allows",
        # the drag is a force on the nodes, so the force laws have to be right first.
        "builds_on": ["solver_physics_oracle"],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "fuselage drag within %.0f%% of upstream's own closed form, and the hero truck past"
            % (FORCE_TOLERANCE * 100.0)
            + " %.0f km/h at full throttle where the turbulent model held it at %.0f"
            % [MIN_TOP_SPEED_KMH, WITHOUT_FUSELAGE_KMH]
        ),
        "why": (
            "upstream picks its aerodynamic model by whether a file has a fusedrag section, and"
            + " the two models differ by orders of magnitude. Picking the wrong one is invisible"
            + " in every static check and shows up only as a vehicle that will not go faster —"
            + " reported in a session as a top speed of 60."
        ),
        "budget_s": 180.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var law: Dictionary = _law_matches_upstream()
    if (law["error"] as String) != "":
        return fail(law["error"] as String, law["value"] as float)

    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok(
            "fuselage drag within %.4f of upstream's closed form; skipped the drive: the hero"
            % (law["value"] as float) + " asset is not present",
            law["value"]
        )
    var driven: Dictionary = _top_speed(mod_dir)
    if (driven["error"] as String) != "":
        return fail(driven["error"] as String, driven["value"] as float)
    var speed: float = driven["value"] as float
    if speed < MIN_TOP_SPEED_KMH:
        return fail(
            "%.0f s at full throttle reached %.0f km/h in gear %d, under %.0f: the rig is being"
            % [RUN_SECONDS, speed, driven["gear"] as int, MIN_TOP_SPEED_KMH]
            + " held back by drag it does not declare",
            speed
        )
    return ok(
        "fuselage drag %.4f against upstream's closed form; the hero truck reaches %.0f km/h in"
        % [law["value"] as float, speed]
        + " gear %d of %d, where the turbulent model held it at %.0f"
        % [driven["gear"] as int, driven["gears"] as int, WITHOUT_FUSELAGE_KMH],
        speed
    )


## The law itself: a body moving at a known speed is pushed back by the flat-plate force
## upstream's `CalcFuseDrag` computes, and by nothing else.
##
## Upstream's own arithmetic, quoted: the fuselage's back node is its front node, so the airfoil
## term is zero and what is left is
##
##     force = (width^2 / 2) * (density / 2) * speed * velocity
##
## spread over the rig's nodes — which means the total on the body does not depend on how many
## nodes it has, and that is the part that differs from the turbulent model.
func _law_matches_upstream() -> Dictionary:
    var solver: RefCounted = ClassDB.instantiate("RorSolver") as RefCounted
    if solver == null:
        return {"error": "RorSolver is not registered", "value": 0.0}
    solver.set_gravity(Vector3.ZERO)
    solver.set_ground(-1000.0, false)
    for index: int in 4:
        solver.add_node(Vector3(float(index), 0.0, 0.0), TEST_MASS_KG)
        solver.set_node_velocity(index, Vector3(TEST_SPEED_MS, 0.0, 0.0))
    solver.set_air_drag(0.05, false)
    solver.set_fuselage_drag(0, TEST_WIDTH_M, true)
    var dt: float = 1.0 / SUBSTEP_HZ
    # Two substeps, because the integrator runs first in a step and the drag it applies is
    # integrated by the next one. One substep accumulates the force and moves nothing.
    solver.step(dt, 2)
    # What the nodes actually lost is the force, by f = m dv / dt.
    var lost: float = 0.0
    for index: int in 4:
        lost += (TEST_SPEED_MS - solver.get_node_velocity(index).x) * TEST_MASS_KG / dt
    var wanted: float = (
        TEST_WIDTH_M * TEST_WIDTH_M * 0.5 * 0.5 * AIR_DENSITY
        * TEST_SPEED_MS * TEST_SPEED_MS
    )
    var off: float = absf(lost - wanted) / maxf(wanted, 0.0001)
    if off > FORCE_TOLERANCE:
        return {
            "error": (
                "a %.0f m body at %.0f m/s is dragged by %.1f N where upstream's arithmetic"
                % [TEST_WIDTH_M, TEST_SPEED_MS, lost] + " gives %.1f N" % wanted
            ),
            "value": off,
        }
    return {"error": "", "value": off}


## And what it does to the hero truck: full throttle on flat ground, for long enough to run out
## of gears.
func _top_speed(mod_dir: String) -> Dictionary:
    var out: Dictionary = {"error": "", "value": 0.0, "gear": 0, "gears": 0}
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        out["error"] = rig["error"] as String
        return out
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.15)
    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    for _settle: int in 90:
        solver.step(dt, chunk)
    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(1.0)
    var fastest: float = 0.0
    for frame: int in int(RUN_SECONDS * 60.0):
        solver.step(dt, chunk)
        fastest = maxf(fastest, absf(solver.road_speed()) * 3.6)
        if not is_finite(solver.get_node_position(0).length()):
            out["error"] = "the solver went non-finite %.1f s into the run" % (
                float(frame) / 60.0)
            return out
    out["value"] = fastest
    out["gear"] = solver.engine_gear()
    out["gears"] = solver.engine_gear_count()
    return out
