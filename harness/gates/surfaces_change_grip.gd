extends GateBase
## Each surface grips by its own coefficient, in the place the map says it is.
##
## Every surface in this project used to be upstream's `concrete`, at 1.2 static friction. That
## is asphalt everywhere, including the sand: a vehicle grips right up to the point it rolls
## over rather than sliding first, which is what a human session reported as rolling too
## easily. Surfaces only fix that if the map routes each patch of ground to its own model, and
## if the model's coefficient is what decides.
##
## Both halves are checked with the closed-form result for a mass on a slope: it holds while
## the slope is shallower than the arctangent of the static friction coefficient and slides
## once it is steeper. Each lane is tested two degrees either side of *its own* limit, so the
## test is different for every surface and passing it by accident would require the map, the
## models and the contact law all to be wrong in the same direction.
##
## The ground is a flat synthetic field rather than the valley, so the valley's own slope
## cannot contribute and the only thing under test is the surface.

const FIELD: int = 64
const SPACING: float = 1.0
const GRAVITY: float = 9.81
const SUBSTEP_HZ: float = 2000.0
const SECONDS: float = 1.5
## How far either side of a surface's own limit angle to test.
const MARGIN_DEG: float = 2.0
## A held node may creep by the smoothing in the static branch, but not by this.
const HOLD_TOLERANCE_M: float = 0.002
## And a sliding one has to actually go somewhere.
const MIN_SLIDE_M: float = 0.05


static func meta() -> Dictionary:
    return {
        "name": "surfaces_change_grip",
        "proves": "each ground surface grips by its own friction coefficient, at the place the surface map puts it",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "every surface holds %.0f deg below atan(its own mu) within %.0f mm and slides"
            % [MARGIN_DEG, HOLD_TOLERANCE_M * 1000.0]
            + " at least %.0f mm %.0f deg above it" % [MIN_SLIDE_M * 1000.0, MARGIN_DEG]
        ),
        "why": (
            "one friction value for the whole world means a vehicle either grips everywhere"
            + " or nowhere, and on 1.2 it grips until it tips. Testing each surface at its own"
            + " limit angle, rather than all of them at one angle, is what makes the map and"
            + " the coefficients separable: a wrong map sends a lane to the wrong model and"
            + " the two-degree band catches it."
        ),
        "budget_s": 90.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var report: PackedStringArray = PackedStringArray()
    for index: int in GroundModels.ORDER.size():
        var name: String = GroundModels.ORDER[index]
        var static_friction: float = float((GroundModels.SURFACES[name] as Array)[1])
        var limit_deg: float = rad_to_deg(atan(static_friction))

        var held: Dictionary = _slide(index, limit_deg - MARGIN_DEG)
        if (held["error"] as String) != "":
            return fail(held["error"] as String)
        if held["distance"] as float > HOLD_TOLERANCE_M:
            return fail(
                "on %s at %.1f deg, below its own %.1f deg limit, the node slid %.4f m"
                % [name, limit_deg - MARGIN_DEG, limit_deg, held["distance"]],
                held["distance"]
            )
        var slid: Dictionary = _slide(index, limit_deg + MARGIN_DEG)
        if (slid["error"] as String) != "":
            return fail(slid["error"] as String)
        if slid["distance"] as float < MIN_SLIDE_M:
            return fail(
                "on %s at %.1f deg, above its own %.1f deg limit, the node moved only %.4f m"
                % [name, limit_deg + MARGIN_DEG, limit_deg, slid["distance"]],
                slid["distance"]
            )
        report.append("%s %.1f deg" % [name, limit_deg])
    return ok(
        "%d surfaces, each holding and sliding either side of its own limit: %s"
        % [GroundModels.ORDER.size(), ", ".join(report)],
        0
    )


## One node on a flat field of surface `index`, on a slope of `slope_deg`.
##
## The slope is applied by tilting gravity, so the ground stays flat and its surface map stays
## a simple lookup — the same trick `ground_friction_oracle` uses.
func _slide(index: int, slope_deg: float) -> Dictionary:
    var solver: RefCounted = ClassDB.instantiate("RorSolver") as RefCounted
    if solver == null:
        return {"error": "RorSolver is not registered: the GDExtension did not load"}
    var heights: PackedFloat32Array = PackedFloat32Array()
    heights.resize(FIELD * FIELD)
    heights.fill(0.0)
    var origin: Vector3 = Vector3(-float(FIELD) * SPACING * 0.5, 0.0, -float(FIELD) * SPACING * 0.5)
    if not solver.set_heightfield(heights, FIELD, FIELD, origin, SPACING):
        return {"error": "the solver rejected a %dx%d flat field" % [FIELD, FIELD]}
    var surfaces: PackedByteArray = PackedByteArray()
    surfaces.resize(FIELD * FIELD)
    surfaces.fill(index)
    if not solver.set_surface_map(surfaces, FIELD, FIELD):
        return {"error": "the solver rejected a %dx%d surface map" % [FIELD, FIELD]}
    GroundModels.apply(solver)
    if solver.surface_at(Vector3.ZERO) != index:
        return {
            "error": "the surface map reports %d at the origin, not %d"
            % [solver.surface_at(Vector3.ZERO), index]
        }

    solver.add_node(Vector3.ZERO, 100.0)
    solver.set_node_friction(0, 1.0)
    var angle: float = deg_to_rad(slope_deg)
    solver.set_gravity(Vector3(GRAVITY * sin(angle), -GRAVITY * cos(angle), 0.0))
    solver.set_ground(0.0, true)
    solver.set_air_drag(0.0, false)
    solver.step(1.0 / SUBSTEP_HZ, int(SECONDS * SUBSTEP_HZ))
    var final: Vector3 = solver.get_node_position(0)
    if not is_finite(final.length()):
        return {"error": "the node went non-finite on %s" % GroundModels.name_of(index)}
    return {"error": "", "distance": absf(final.x)}
