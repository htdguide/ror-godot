extends SceneTree
## What a vehicle's wheels do under its own drive torque, which standing still never asks.
##
## A rig settles on its springs; accelerating loads the axle in a direction the springs do not
## carry, and a wheel whose location is too soft folds under it. Reported from a window as "it
## feels so soft that when I accelerate the wheels just fold" — and `settle_report` reads that
## vehicle as nearly clean, because nothing is wrong with it until it is driven.
##
##   godot --path . --headless --script res://harness/dev/drive_stance.gd [-- <name substring>]

const SUBSTEP_HZ: float = 2000.0
const SETTLE_SECONDS: float = 2.0
const DRIVE_SECONDS: float = 4.0


func _initialize() -> void:
    var filter: String = ""
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    if not argv.is_empty():
        filter = argv[0]
    print("%-28s %8s %8s %8s  %s" % ["vehicle", "rest", "driven", "worst", "verdict"])
    var bad: int = 0
    var counted: int = 0
    for entry: Dictionary in RorVehicleLibrary.entries():
        var name: String = entry["name"] as String
        if filter != "" and not name.containsn(filter):
            continue
        var line: Dictionary = _drive(entry)
        if (line["error"] as String) != "":
            continue
        counted += 1
        var folded: bool = float(line["driven"]) > 15.0
        if folded:
            bad += 1
        print("%-28s %6.1f° %6.1f° %6.1f°  %s" % [
            name, float(line["rest"]), float(line["driven"]), float(line["worst"]),
            "a wheel folds under power" if folded else ""])
    print("")
    print("%d driven, %d fold a wheel under their own torque" % [counted, bad])
    quit(0)


## Settles the rig, then drives it, reporting the worst wheel lean at rest, at the end of the
## run, and at any point during it.
func _drive(entry: Dictionary) -> Dictionary:
    var truck: TruckParser = TruckParser.new()
    if truck.parse_file((entry["directory"] as String).path_join(entry["file"] as String)) != "":
        return {"error": "unreadable"}
    if truck.wheels.is_empty():
        return {"error": "no wheels"}
    var rig: Dictionary = RigBuilder.build(truck, 0.0)
    if (rig.get("error", "") as String) != "":
        return {"error": rig["error"] as String}
    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.0)
    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    for _i: int in int(SETTLE_SECONDS * 60.0):
        solver.step(dt, chunk)
    var rest: float = _lean(solver, truck)
    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(1.0)
    var worst: float = rest
    for _i: int in int(DRIVE_SECONDS * 60.0):
        solver.step(dt, chunk)
        worst = maxf(worst, _lean(solver, truck))
    return {"error": "", "rest": rest, "driven": _lean(solver, truck), "worst": worst}


## The worst lean of any axle from the horizontal, in degrees.
func _lean(solver: RefCounted, truck: TruckParser) -> float:
    var at: PackedVector3Array = solver.get_positions()
    if at.is_empty() or not is_finite(at[0].length()):
        return 0.0
    var worst: float = 0.0
    for wheel: Dictionary in truck.wheels:
        var axis: Vector3 = at[wheel["node2"] as int] - at[wheel["node1"] as int]
        if axis.length() > 0.0:
            worst = maxf(worst, rad_to_deg(asin(clampf(absf(axis.normalized().y), 0.0, 1.0))))
    return worst
