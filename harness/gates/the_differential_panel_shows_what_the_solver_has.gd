extends GateBase
## The differential panel in the solo window says what the solver is doing: one row per axle with
## its kind, the lock between axles on the shaft joining the right two rows, and a switch shows up
## on the panel once it has happened in the solver.
##
## The oracle is the hero's file and upstream's build rules, which `a_differential_shares_torque_
## by_its_kind` already holds the solver to: two axles, `d(sl)`, split until switched, and a locked
## differential between axles 0 and 1. Given the VW Thing's transfer case, the panel's shaft for it
## is the solver's: 2WD high range at spawn, 4WD low range at 1.97 after its two keys. What is checked here is that the panel's model reads that
## and not something of its own; how it looks is the owner's to judge.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"


static func meta() -> Dictionary:
    return {
        "name": "the_differential_panel_shows_what_the_solver_has",
        "proves": "the differential panel's rows are the solver's differentials, kinds and joins, before and after a switch",
        "builds_on": ["a_differential_shares_torque_by_its_kind"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "hero: axles s,s and shaft l joining 0-1; switched, axles l,l; transfer case 1-0 2WD 1 then 4WD 1.97",
        "why": "a panel that reads its own idea of the drivetrain would tell the driver a lock is on when it is not.",
        "budget_s": 20.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        return fail(rig["error"] as String)
    var solver: RefCounted = rig["solver"] as RefCounted
    var before: String = _describe(DiffPanel.model(solver))
    if before != "axles s,s shafts l:0-1":
        return fail("the panel shows %s for the hero, not axles s,s shafts l:0-1" % before)
    solver.toggle_wheel_differentials()
    var after: String = _describe(DiffPanel.model(solver))
    if after != "axles l,l shafts l:0-1":
        return fail("switched, the panel shows %s, not axles l,l shafts l:0-1" % after)
    var text: String = FileAccess.get_file_as_string(mod_dir.path_join(TRUCK)).replace("\r", "")
    var truck: TruckParser = TruckParser.new()
    truck.parse_text(text.replace("\naxles\n", "\ntransfercase\n2, 1, 1, 0, 1.97, 2.46\n\naxles\n"))
    var cased: RefCounted = RigBuilder.build(truck, 0.0)["solver"] as RefCounted
    var spawned: String = _transfer(DiffPanel.model(cased))
    cased.toggle_transfer_case_mode()
    cased.toggle_transfer_case_ratio()
    var shifted: String = _transfer(DiffPanel.model(cased))
    if spawned != "1-0 2WD 1.00" or shifted != "1-0 4WD 1.97":
        return fail("the panel's transfer case is %s at spawn and %s shifted, not 1-0 2WD 1.00 and 1-0 4WD 1.97" % [spawned, shifted])
    return ok("panel: %s, switched %s; transfer case %s, shifted %s" % [before, after, spawned, shifted], 0)


func _transfer(model: Dictionary) -> String:
    var transfer: Dictionary = model["transfer"] as Dictionary
    if transfer.is_empty():
        return "none"
    var axles: Vector2i = transfer["axles"] as Vector2i
    return "%d-%d %s %.2f" % [axles.x, axles.y, "4WD" if transfer["four_wd"] else "2WD", transfer["ratio"]]


func _describe(model: Dictionary) -> String:
    var axles: PackedStringArray = PackedStringArray()
    for axle: Dictionary in model["axles"] as Array:
        axles.append(axle["type"] as String)
    var shafts: PackedStringArray = PackedStringArray()
    for shaft: Dictionary in model["shafts"] as Array:
        var joined: Vector2i = shaft["axles"] as Vector2i
        shafts.append("%s:%d-%d" % [shaft["type"], joined.x, joined.y])
    return "axles %s shafts %s" % [",".join(axles), ",".join(shafts)]
