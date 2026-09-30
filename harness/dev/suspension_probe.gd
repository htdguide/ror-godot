extends SceneTree
## Finds what resists a suspension's travel, by moving an axle and seeing which beams object.
##
##   godot --path game --headless --script res://harness/dev/suspension_probe.gd -- <truck>
##
## A Rigs of Rods suspension springs on its shocks and is *located* by ordinary beams, which
## form a linkage that should let the axle rise and fall without any of them changing length.
## When an axle barely moves, something is resisting travel — and rather than reason about the
## geometry, this displaces the axle and asks which beams changed length, which is the same
## question with an answer.
##
## A beam entirely inside the axle, or entirely outside it, cannot resist: only those crossing
## the boundary can. Each is reported with the force its own stiffness would generate for the
## displacement, which is what ranks them.

## The rear axle assembly of the hero truck: every node of it, so that beams within it are
## excluded and only the linkage to the chassis is measured.
const AXLE_FIRST: int = 92
const AXLE_LAST: int = 104
const DROP_M: float = 0.05
const SETTLE_SECONDS: float = 3.0
const SUBSTEP_HZ: float = 2000.0


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    if argv.is_empty():
        printerr("usage: suspension_probe.gd -- <path to .truck>")
        quit(2)
        return
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_file(argv[0])
    if error != "":
        printerr(error)
        quit(1)
        return
    var built: Dictionary = RigBuilder.build(truck, 0.02)
    var solver: RefCounted = built["solver"] as RefCounted
    solver.set_ground(0.0, true)
    for _i: int in int(SETTLE_SECONDS * 60.0):
        solver.step(1.0 / SUBSTEP_HZ, int(SUBSTEP_HZ / 60.0))

    var settled: PackedVector3Array = solver.get_positions()
    print("displacing nodes %d..%d by %.0f mm and measuring what objects"
        % [AXLE_FIRST, AXLE_LAST, DROP_M * 1000.0])

    var rows: Array[Dictionary] = []
    for i: int in range(0, truck.beams.size(), 2):
        var a: int = truck.beams[i]
        var b: int = truck.beams[i + 1]
        var a_in: bool = a >= AXLE_FIRST and a <= AXLE_LAST
        var b_in: bool = b >= AXLE_FIRST and b <= AXLE_LAST
        if a_in == b_in:
            continue  # Wholly inside the axle or wholly outside it: cannot resist travel.
        var beam: int = i / 2
        var before: float = settled[a].distance_to(settled[b])
        var moved_a: Vector3 = settled[a] - (Vector3.DOWN * DROP_M if a_in else Vector3.ZERO)
        var moved_b: Vector3 = settled[b] - (Vector3.DOWN * DROP_M if b_in else Vector3.ZERO)
        var after: float = moved_a.distance_to(moved_b)
        var change: float = after - before
        rows.append({
            "beam": beam,
            "a": a,
            "b": b,
            "change_mm": change * 1000.0,
            "spring": truck.beam_spring[beam],
            "force": absf(change) * truck.beam_spring[beam],
            "bound": _bound_of(truck, beam),
        })
    rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
        return (x["force"] as float) > (y["force"] as float))

    print("  %d beams link the axle to the rest of the rig" % rows.size())
    var total: float = 0.0
    for row: Dictionary in rows:
        total += row["force"] as float
    print("  they resist the displacement with %.0f N in total" % total)
    print("  the ten stiffest:")
    for i: int in mini(10, rows.size()):
        var row: Dictionary = rows[i]
        print("    beam %4d  %3d-%3d  %+7.2f mm  spring %9.0f  %8.0f N  %s" % [
            row["beam"], row["a"], row["b"], row["change_mm"], row["spring"], row["force"],
            row["bound"]])


## What kind of beam this is, as the rig declared it.
func _bound_of(truck: TruckParser, beam: int) -> String:
    for entry: Dictionary in truck.bounded_beams:
        if (entry["beam"] as int) != beam:
            continue
        match entry["bound"] as int:
            BeamRows.BOUND_SHOCK:
                return "shock, travel %.2f/%.2f" % [entry["short_bound"], entry["long_bound"]]
            BeamRows.BOUND_ROPE:
                return "rope"
            BeamRows.BOUND_SUPPORT:
                return "support"
    return "plain beam"
