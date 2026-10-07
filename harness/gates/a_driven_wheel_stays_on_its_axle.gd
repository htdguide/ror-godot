extends GateBase
## A wheel braced to a rigidity node keeps its camber under its own drive torque.
##
## Reported from a window: the Burnside "feels so soft that accelerating folds its wheels". It
## spawned clean, settled clean and read clean on every standing metric, because the fault was
## only there when it was driven: within 0.4 s of first throttle the rear axle leaned 40 degrees,
## and by the end of a 4 s run 80. Taking the tyres' grip away did not change it, so it was never
## the ground. The axle's own nodes are collinear — a hinge — and the beams upstream braces them
## with, one per ray from the row's rigidity node to the tread ring, were never built.
##
## The oracle is geometric: a wheel's axle is a line between its two hub nodes, and driving the
## rig in a straight line on level ground gives that line no reason to turn. What is measured is
## how far it turns from where it settled — not from horizontal, because a monorail's guide wheels
## stand on vertical axles by design and sit at 87 degrees before anything is driven. A change of
## tens of degrees is a wheel folding under the car; a few degrees is suspension and body roll. The
## bound is the one `drive_stance` already called a fold, and it is a long way from both
## populations: a braced wheel that holds moves under 6 degrees across the library, and one that
## folds, over 25.

const SUBSTEP_HZ: float = 2000.0
const SETTLE_SECONDS: float = 2.0
const DRIVE_SECONDS: float = 4.0
const THROTTLE: float = 1.0
## Past this an axle is not leaning, it has folded.
const MAX_LEAN_DEG: float = 15.0


static func meta() -> Dictionary:
    return {
        "name": "a_driven_wheel_stays_on_its_axle",
        "proves": "every driven vehicle whose wheels name a rigidity node keeps each axle within %.0f degrees of where it settled through a full-throttle run on flat ground" % MAX_LEAN_DEG,
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "no axle turns more than %.0f degrees from its settled lean, over %.0f s at full throttle, on any such vehicle in the library" % [MAX_LEAN_DEG, DRIVE_SECONDS],
        "why": (
            "a wheel without its rigidity beams stands, settles and rolls, and folds the first"
            + " time it is driven hard, which no standing metric and no count of nodes can see."
            + " The Burnside Drag's axle leaned 40 degrees within 0.4 s of throttle and 80 by the"
            + " end of the run, with or without grip. 19 of 66 driveable vehicles did the same."
        ),
        "budget_s": 150.0,
        "needs_gpu": false,
        "milestone": "C2",
    }


func run(_harness: Node) -> Dictionary:
    var driven: int = 0
    var worst_overall: float = 0.0
    var report: PackedStringArray = PackedStringArray()
    var folded: PackedStringArray = PackedStringArray()
    for entry: Dictionary in RorVehicleLibrary.entries():
        var truck: TruckParser = TruckParser.new()
        var path: String = (entry["directory"] as String).path_join(entry["file"] as String)
        if truck.parse_file(path) != "":
            continue
        if not _has_braced_driven_wheel(truck):
            continue
        var rig: Dictionary = RigBuilder.build(truck, 0.0)
        if (rig.get("error", "") as String) != "":
            continue
        var solver: RefCounted = rig["solver"] as RefCounted
        if not solver.has_engine():
            continue
        var lean: float = _worst_lean_driven(solver, truck)
        driven += 1
        worst_overall = maxf(worst_overall, lean)
        report.append("%s %.1f" % [entry["name"], lean])
        if lean > MAX_LEAN_DEG:
            folded.append("%s turns an axle %.1f degrees" % [entry["name"], lean])
    if driven == 0:
        return ok("skipped: no vehicle in this checkout drives a wheel braced to a rigidity node", 0)
    if not folded.is_empty():
        return fail(
            "%d of %d braced, driven vehicles fold a wheel under their own torque: %s"
            % [folded.size(), driven, "; ".join(folded)],
            worst_overall
        )
    return ok(
        "%d braced vehicles driven %.0f s at full throttle; worst axle turn %.1f degrees (%s)"
        % [driven, DRIVE_SECONDS, worst_overall, ", ".join(report)],
        worst_overall
    )


static func _has_braced_driven_wheel(truck: TruckParser) -> bool:
    for wheel: Dictionary in truck.wheels:
        if int(wheel.get("rigidity_node", -1)) >= 0 and int(wheel["propulsed"]) != 0:
            return true
    return false


## Settles the rig, drives it, and returns the furthest any wheel's axle turns from its settled
## lean at any point in the run.
static func _worst_lean_driven(solver: RefCounted, truck: TruckParser) -> float:
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.0)
    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    for _i: int in int(SETTLE_SECONDS * 60.0):
        solver.step(dt, chunk)
    var rest: PackedFloat32Array = _leans(solver, truck)
    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(THROTTLE)
    var worst: float = 0.0
    for _i: int in int(DRIVE_SECONDS * 60.0):
        solver.step(dt, chunk)
        var now: PackedFloat32Array = _leans(solver, truck)
        for w: int in now.size():
            worst = maxf(worst, absf(now[w] - rest[w]))
    return worst


## Each wheel's axle lean from horizontal, in degrees; 90 for every wheel once the solver has
## diverged, which is a fold by any measure.
static func _leans(solver: RefCounted, truck: TruckParser) -> PackedFloat32Array:
    var at: PackedVector3Array = solver.get_positions()
    var out: PackedFloat32Array = PackedFloat32Array()
    var diverged: bool = at.is_empty() or not is_finite(at[0].length())
    for wheel: Dictionary in truck.wheels:
        if diverged:
            out.append(90.0)
            continue
        var axis: Vector3 = at[wheel["node2"] as int] - at[wheel["node1"] as int]
        out.append(rad_to_deg(asin(clampf(absf(axis.normalized().y), 0.0, 1.0))) if axis.length() > 0.0 else 0.0)
    return out
