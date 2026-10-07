extends SceneTree
## Every vehicle in the library, dropped on flat ground and left to settle, measured against the
## shape its own file describes.
##
## **The oracle is the file, so it scales to a library.** A vehicle standing still on level ground
## is not deforming, and every number here is a departure from what the file states rather than a
## figure anybody chose: a wheel's axle should stay level, its tread should keep the radius the row
## states, its beams should neither yield nor break, and the body should not sink through its own
## suspension. Fixing one vehicle at a time is what produces a loader that fits one vehicle.
##
##   godot --path . --headless --script res://harness/dev/settle_report.gd [-- <name substring>]

const SETTLE_SECONDS: float = 2.5
const SUBSTEP_HZ: float = 2000.0
## A rest length that moved by more than this has yielded rather than flexed.
const YIELDED_M: float = 0.002


func _initialize() -> void:
    var filter: String = ""
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    if not argv.is_empty():
        filter = argv[0]
    print("%-28s %5s %6s %6s  %8s %8s  %s" % [
        "vehicle", "broke", "yield", "camber", "tread", "sag", "worst"])
    var bad: int = 0
    var counted: int = 0
    for entry: Dictionary in RorVehicleLibrary.entries():
        var name: String = entry["name"] as String
        if filter != "" and not name.containsn(filter):
            continue
        var line: Dictionary = _settle(entry)
        if (line["error"] as String) != "":
            print("%-28s %s" % [name, line["error"]])
            bad += 1
            continue
        counted += 1
        if bool(line["suspect"]):
            bad += 1
        print("%-28s %5d %6d %5.1f° %7.0f%% %7.3f  %s" % [
            name, int(line["broke"]), int(line["yielded"]), float(line["camber"]),
            float(line["tread"]) * 100.0, float(line["sag"]), line["worst"]])
    print("")
    print("%d actors settled, %d with something wrong" % [counted, bad])
    quit(0)


## One vehicle: built, dropped, settled, and compared with its own file.
func _settle(entry: Dictionary) -> Dictionary:
    var truck: TruckParser = TruckParser.new()
    var failed: String = truck.parse_file(
        (entry["directory"] as String).path_join(entry["file"] as String)
    )
    if failed != "":
        return {"error": failed}
    var rig: Dictionary = RigBuilder.build(truck, 0.15)
    if (rig.get("error", "") as String) != "":
        return {"error": rig["error"] as String}
    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.15)
    var before: PackedFloat32Array = _rest_lengths(solver)
    for _i: int in int(SETTLE_SECONDS * 60.0):
        solver.step(1.0 / SUBSTEP_HZ, int(SUBSTEP_HZ / 60.0))
    var at: PackedVector3Array = solver.get_positions()
    if at.is_empty() or not is_finite(at[0].length()):
        return {"error": "went non-finite while settling"}

    var yielded: int = 0
    var after: PackedFloat32Array = _rest_lengths(solver)
    for i: int in mini(before.size(), after.size()):
        if absf(after[i] - before[i]) > YIELDED_M:
            yielded += 1

    # A wheel's axle should still be level and its tread should still be round.
    var camber: float = 0.0
    var tread: float = 1.0
    for wheel: Dictionary in truck.wheels:
        var axis: Vector3 = at[wheel["node2"] as int] - at[wheel["node1"] as int]
        if axis.length() > 0.0:
            var lean: float = rad_to_deg(asin(clampf(absf(axis.normalized().y), 0.0, 1.0)))
            camber = maxf(camber, lean)
        var mid: Vector3 = (at[wheel["node1"] as int] + at[wheel["node2"] as int]) * 0.5
        var mean: float = 0.0
        for i: int in int(wheel["tread_count"]):
            var node: Vector3 = at[int(wheel["first_tread"]) + i]
            mean += (node - mid).length()
        mean /= maxf(float(int(wheel["tread_count"])), 1.0)
        tread = minf(tread, mean / maxf(wheel["tire_radius"] as float, 0.0001))

    # And the body should not have sunk through its own springs.
    var sag: float = 0.0
    for i: int in truck.generated_from:
        sag = maxf(sag, truck.nodes[i].y - at[i].y)

    var worst: String = ""
    if solver.broken_beam_count() > 0:
        worst = "beams broke"
    elif camber > 5.0:
        worst = "a wheel leans %.1f degrees" % camber
    elif tread < 0.9:
        worst = "a tyre is %.0f%% of its stated radius" % (tread * 100.0)
    elif sag > 0.10:
        worst = "the body sank %.0f mm" % (sag * 1000.0)
    return {
        "error": "",
        "broke": solver.broken_beam_count(),
        "yielded": yielded,
        "camber": camber,
        "tread": tread,
        "sag": sag,
        "worst": worst,
        "suspect": worst != "",
    }


func _rest_lengths(solver: RefCounted) -> PackedFloat32Array:
    var out: PackedFloat32Array = PackedFloat32Array()
    for beam: int in solver.beam_count():
        out.append(solver.get_beam_rest_length(beam))
    return out
