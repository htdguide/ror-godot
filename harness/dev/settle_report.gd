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
    print("%-28s %5s %6s %6s %6s %6s %6s  %s" % [
        "vehicle", "broke", "yield", "camber", "tread", "sag", "travel", "worst"])
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
        print("%-28s %5d %6d %5.1f° %5.0f%% %6.3f %6.3f  %s" % [
            name, int(line["broke"]), int(line["yielded"]), float(line["camber"]),
            float(line["tread"]) * 100.0, float(line["sag"]), float(line["travel"]),
            line["worst"]])
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
    # **Placed where its file puts it, not dropped onto the ground.** A drop is an impact, and an
    # impact through a stiff damper is a force no spawn ever applies: the Gavril Zeta's third
    # cinecam hangs on 1650 Ns/m mounts, so 0.15 m of fall tears them off and the fault being
    # measured becomes the measurement's own. Upstream spawns an actor resting on the terrain.
    var rig: Dictionary = RigBuilder.build(truck, 0.0)
    if (rig.get("error", "") as String) != "":
        return {"error": rig["error"] as String}
    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.0)
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
        # **The radius about the axle's own axis, not the distance to its midpoint.** A tread node
        # is half the wheel's width to one side, so the straight-line distance to the midpoint is
        # the hypotenuse of the radius and that offset — which read 100% of the stated radius for
        # every vehicle in the library and hid tyres settling at three quarters of theirs.
        var mid: Vector3 = (at[wheel["node1"] as int] + at[wheel["node2"] as int]) * 0.5
        var spin: Vector3 = (at[wheel["node2"] as int] - at[wheel["node1"] as int]).normalized()
        var mean: float = 0.0
        for i: int in int(wheel["tread_count"]):
            var spoke: Vector3 = at[int(wheel["first_tread"]) + i] - mid
            mean += (spoke - spin * spoke.dot(spin)).length()
        mean /= maxf(float(int(wheel["tread_count"])), 1.0)
        tread = minf(tread, mean / maxf(wheel["tire_radius"] as float, 0.0001))

    # And the body should not have sunk through its own springs.
    var sag: float = 0.0
    for i: int in truck.generated_from:
        sag = maxf(sag, truck.nodes[i].y - at[i].y)

    # **How far each axle has moved towards the body it hangs under.** A vehicle resting on level
    # ground sits on its springs, and that is centimetres: an axle that has travelled a quarter of
    # a metre has run out of suspension and the bodywork is sitting on the wheel. Measured against
    # the body's own height rather than the world's, because the whole rig rises onto its tyres as
    # it settles and the file's own ground is not where the ground is.
    var rest_body: float = 0.0
    var now_body: float = 0.0
    for i: int in truck.generated_from:
        rest_body += truck.nodes[i].y
        now_body += at[i].y
    rest_body /= maxf(float(truck.generated_from), 1.0)
    now_body /= maxf(float(truck.generated_from), 1.0)
    var travel: float = 0.0
    for wheel: Dictionary in truck.wheels:
        var a: int = wheel["node1"] as int
        var b: int = wheel["node2"] as int
        var was: float = (truck.nodes[a].y + truck.nodes[b].y) * 0.5 - rest_body
        var now: float = (at[a].y + at[b].y) * 0.5 - now_body
        travel = maxf(travel, absf(now - was))

    var worst: String = ""
    if solver.broken_beam_count() > 0:
        worst = "beams broke"
    elif camber > 5.0:
        worst = "a wheel leans %.1f degrees" % camber
    elif tread < 0.9:
        worst = "a tyre is %.0f%% of its stated radius" % (tread * 100.0)
    elif sag > 0.10:
        worst = "the body sank %.0f mm" % (sag * 1000.0)
    elif travel > 0.12:
        worst = "an axle travelled %.0f mm into the body" % (travel * 1000.0)
    return {
        "error": "",
        "broke": solver.broken_beam_count(),
        "yielded": yielded,
        "camber": camber,
        "tread": tread,
        "sag": sag,
        "travel": travel,
        "worst": worst,
        "suspect": worst != "",
    }


func _rest_lengths(solver: RefCounted) -> PackedFloat32Array:
    var out: PackedFloat32Array = PackedFloat32Array()
    for beam: int in solver.beam_count():
        out.append(solver.get_beam_rest_length(beam))
    return out
