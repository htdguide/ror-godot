extends GateBase
## A `transfercase` drives only its first axle in 2WD, both in 4WD through a locked differential
## between them, and its low range multiplies every gear by its reduction, the way upstream's
## `TransferCase` does.
##
## 23 corpus vehicles declare one, and every one of them drove all its `propulsed` wheels with no
## way to leave 4WD or engage a low range.
##
## The hero declares two axles, both split, so the oracle is exact: in 2WD the second axle's
## wheels get no drive torque at all (a split of nothing is nothing), and no differential joins the
## axles, because upstream skips its automatic locked one between the transfer case's two axles. In
## 4WD the transfer case's own locked one appears and the second axle pulls. Leaving 4WD without a
## 2WD low range shifts back to high first, and a range key in 2WD does nothing.
##
## An axle row naming a wheel that is not there keeps its place on wheel 0, as upstream's does
## (`AssignWheelToAxle` warns and leaves its default): the Star Monster's first axle names node 75
## for a wheel on 78, and its transfer case counts on the axle after it being the second.
##
## The low range is checked on the engine: in first gear with the clutch closed the crank turns at
## the wheels' rpm times the gear ratio, so the quotient of the two, Lo against Hi, is the
## reduction, 1.97 here, within the clutch's slip.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
## Upstream's own row shape from the corpus (the VW Thing's): axle 2 always driven, axle 1 in 4WD,
## a 2WD mode, a 2WD low range, two reductions.
const ROW: String = "2, 1, 1, 0, 1.97, 2.46"
const LOW: float = 1.97
const SUBSTEP_HZ: float = 2000.0
const CHUNK: int = 33
const DRIVE_S: float = 3.0
const SLIP: float = 0.02


static func meta() -> Dictionary:
    return {
        "name": "a_transfer_case_drives_its_second_axle_in_4wd",
        "proves": "a transfer case drives one axle in 2WD and both through a locked differential in 4WD, and its low range multiplies the gearing by its reduction, as upstream's does",
        "builds_on": ["a_differential_shares_torque_by_its_kind"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "2WD: second axle torque exactly 0, no differential between the axles; 4WD: second axle pulling, transfer case wound and unwound by a respawn; Lo/Hi crank-to-wheel quotient %.2f within %.0f%%" % [LOW, SLIP * 100.0],
        "why": "23 corpus vehicles declare a transfer case and drove every wheel all the time, with no 2WD and no low range.",
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var parsed: TruckParser = TruckParser.new()
    if parsed.parse_text("t\nnodes\n0, 0, 0, 0\ntransfercase\n%s\nend" % ROW) != "" or parsed.transfer_cases.size() != 1:
        return fail("the transfercase row did not parse")
    var row: Dictionary = parsed.transfer_cases[0]
    if [row["a1"], row["a2"], row["has_2wd"], row["has_2wd_lo"]] != [1, 0, true, false] \
            or row["ratios"] != PackedFloat32Array([1.0, 1.97, 2.46]):
        return fail("the row read as %s, not upstream's axles 1 and 0, 2WD, no 2WD Lo, ratios 1, 1.97, 2.46" % row)

    var astray: Dictionary = _hero(mod_dir, ROW, "w1(115 113)", "w1(115 0)")
    if (astray["error"] as String) != "":
        return fail("an axle with a wheel it cannot find: %s" % astray["error"])
    var astray_wheels: Vector2i = (astray["solver"] as RefCounted).wheel_differential_wheels(0)
    if astray_wheels.x != 0:
        return fail("the axle naming a missing wheel is on wheels %s, not on wheel 0" % astray_wheels)

    var rig: Dictionary = _hero(mod_dir, ROW)
    if (rig["error"] as String) != "":
        return fail(rig["error"] as String)
    var solver: RefCounted = rig["solver"] as RefCounted
    var second: Vector2i = solver.wheel_differential_wheels(0)
    if solver.driven_wheel_count() != 2 or solver.transfer_case_four_wd():
        return fail("spawned with %d driven wheels, 4WD %s: not 2WD on one axle" % [
            solver.driven_wheel_count(), solver.transfer_case_four_wd()])
    if solver.axle_differential_count() != 0:
        return fail("2WD has %d differentials between the axles: the automatic locked one was not skipped" % solver.axle_differential_count())
    solver.toggle_transfer_case_ratio()
    if solver.transfer_case_ratio() != 1.0:
        return fail("the range key shifted to %.2f in 2WD without a 2WD low range" % solver.transfer_case_ratio())
    if solver.add_interaxle(0, 1, "l") != -1:
        return fail("an interaxle between the transfer case's two axles was accepted")

    var two_wd: Dictionary = _drive(solver, second, false)
    if (two_wd["second"] as float) != 0.0 or (two_wd["first"] as float) <= 0.0:
        return fail("2WD: first axle %.3f N m, second %.6f: the second axle was driven" % [two_wd["first"], two_wd["second"]])

    rig = _hero(mod_dir, ROW)
    solver = rig["solver"] as RefCounted
    solver.toggle_transfer_case_mode()
    if solver.driven_wheel_count() != 4 or not solver.transfer_case_four_wd():
        return fail("after the mode key %d wheels are driven: not 4WD" % solver.driven_wheel_count())
    var hi: Dictionary = _drive(solver, second, true)
    if absf(hi["second"] as float) <= 1.0:
        return fail("4WD: the second axle got %.4f N m: not pulling" % hi["second"])
    # Only a locked differential winds; upstream's `SyncReset` unwinds it while in 4WD.
    var wind: float = solver.transfer_case_wind()
    if absf(wind) < 1e-6:
        return fail("4WD: the transfer case's differential did not wind (%.8f m): it is not locked" % wind)
    RigBuilder.place(solver, rig["truck"] as TruckParser, Vector3.ZERO, 0.0, 0.15)
    if solver.transfer_case_wind() != 0.0:
        return fail("respawned in 4WD, the transfer case is still wound %.6f m" % solver.transfer_case_wind())

    rig = _hero(mod_dir, ROW)
    solver = rig["solver"] as RefCounted
    solver.toggle_transfer_case_mode()
    solver.toggle_transfer_case_ratio()
    var name: String = AxleRows.transfer_case_name(solver)
    if name != "Transfercase switched to: 4WD Lo (1.97:1)":
        return fail("the console says \"%s\"" % name)
    var lo: Dictionary = _drive(solver, second, true)
    var quotient: float = (lo["crank_per_wheel"] as float) / (hi["crank_per_wheel"] as float)
    if absf(quotient - LOW) > LOW * SLIP:
        return fail("crank per wheel turn %.3f in Lo against %.3f in Hi: %.3f, not %.2f" % [
            lo["crank_per_wheel"], hi["crank_per_wheel"], quotient, LOW], quotient)
    solver.toggle_transfer_case_mode()
    if solver.transfer_case_ratio() != 1.0 or solver.driven_wheel_count() != 2:
        return fail("back to 2WD the range is %.2f with %d wheels driven: no shift back to Hi" % [
            solver.transfer_case_ratio(), solver.driven_wheel_count()])
    return ok(
        "2WD: axles %.1f / 0 N m, none between; 4WD Hi: %.1f / %.1f, wound %.6f m; Lo/Hi crank per wheel %.3f / %.3f = %.3f"
        % [two_wd["first"], hi["first"], hi["second"], wind, lo["crank_per_wheel"], hi["crank_per_wheel"], quotient],
        quotient
    )


## The hero with `row` as its transfer case, on flat ground, `edit` replaced by `with` in its file.
func _hero(mod_dir: String, transfer_row: String, edit: String = "", with: String = "") -> Dictionary:
    var text: String = FileAccess.get_file_as_string(mod_dir.path_join(TRUCK)).replace("\r", "")
    if edit != "":
        text = text.replace(edit, with)
    text = text.replace("\naxles\n", "\ntransfercase\n%s\n\naxles\n" % transfer_row)
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_text(text)
    if error != "":
        return {"error": "the hero did not parse with a transfer case: %s" % error}
    var built: Dictionary = RigBuilder.build(truck, 0.02)
    if (built["error"] as String) != "":
        return {"error": built["error"]}
    built["truck"] = truck
    var solver: RefCounted = built["solver"] as RefCounted
    if not solver.has_transfer_case():
        return {"error": "the hero's transfer case was refused"}
    solver.set_ground(0.0, true)
    return built


## Drives in first for `DRIVE_S` and returns the summed wheel torque of the first (always driven)
## and the second axle over the last second, and the crank's rpm per metre a second of tread.
func _drive(solver: RefCounted, second: Vector2i, four_wd: bool) -> Dictionary:
    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(0.5)
    var first: Vector2i = solver.wheel_differential_wheels(1)
    var torque: Vector2 = Vector2.ZERO
    var substeps: int = int(DRIVE_S * SUBSTEP_HZ)
    var done: int = 0
    while done < substeps:
        solver.step(1.0 / SUBSTEP_HZ, CHUNK)
        done += CHUNK
        if done > substeps - int(SUBSTEP_HZ):
            torque.x += absf(solver.get_wheel_torque(first.x)) + absf(solver.get_wheel_torque(first.y))
            torque.y += absf(solver.get_wheel_torque(second.x)) + absf(solver.get_wheel_torque(second.y))
    # Tread speed stands in for the wheels' rpm: the radius is the same in both ranges and cancels.
    var tread: float = 0.0
    for wheel: int in [first.x, first.y] + ([second.x, second.y] if four_wd else []):
        tread += absf(solver.get_wheel_speed(wheel))
    tread /= 4.0 if four_wd else 2.0
    return {"first": torque.x, "second": torque.y, "crank_per_wheel": solver.engine_rpm() / maxf(tread, 1e-3)}
