extends GateBase
## `--add` puts an undriven vehicle behind the driven one, in the same world: stood 8 m behind along
## the driven vehicle's own length, stepped by one `RorWorld` with it, and moved by nothing the
## driver's keys do. It is what a trailer or a load needs before a hook or a tie can take it.
##
## The oracle is the driven vehicle's own frame for where the other belongs, and the throttle for
## which of the two is driven: held for a second and a half, the driven truck moves and the added
## one stays where it was put.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const SPEC: String = "assets/mods/ChevyS1023:S10offroad.truck"
const PRESET: String = "hero_3q"
const HELD_FRAMES: int = 90
const SETTLE_FRAMES: int = 90
const PLACED_WITHIN_M: float = 0.5
const MIN_DRIVEN_M: float = 1.0
const MAX_DRIFT_M: float = 0.2


static func meta() -> Dictionary:
    return {
        "name": "an_added_vehicle_stands_behind_and_shares_the_world",
        "proves": "an --add vehicle stands 8 m behind the driven one along its own axis, is stepped by the same world, and does not answer the driver's keys",
        "builds_on": ["two_drivers_drive_their_own_vehicles"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "placed within %.1f m of 8 m behind; one world of 2; throttle held %d frames: driven over %.1f m, added under %.1f m" % [PLACED_WITHIN_M, HELD_FRAMES, MIN_DRIVEN_M, MAX_DRIFT_M],
        "why": "the play window could hold no vehicle but the driven one, so a trailer had nothing to be hitched to.",
        "budget_s": 90.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)
    var built: Dictionary = VehicleBuilder.build(mod_dir, "S10offroad.truck")
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    harness.world.add_child(built["root"] as Node3D)
    var driver: PlayDrive = PlayDrive.new()
    driver.synchronous = true
    var set_up: String = driver.setup(built)
    if set_up != "":
        return fail(set_up)
    var fleet: PlayFleet = PlayFleet.new()
    harness.add_child(fleet)
    var error: String = fleet.setup(harness.world, driver, SPEC)
    if error != "":
        return fail(error)
    if fleet.extras.size() != 1:
        return fail("--add built %d vehicles, not 1" % fleet.extras.size())
    var extra: PlayDrive = fleet.extras[0]
    var back: Vector3 = Vector3(driver.frame.basis.z.x, 0.0, driver.frame.basis.z.z).normalized()
    var want: Vector3 = driver.spawn + back * PlayFleet.BEHIND_M
    if Vector2(extra.spawn.x, extra.spawn.z).distance_to(Vector2(want.x, want.z)) > PLACED_WITHIN_M:
        return fail("the added vehicle stands at %s, not 8 m behind at %s" % [extra.spawn, want])
    if not extra.world_stepped or not driver.world_stepped:
        return fail("the two are not stepped by the world")

    # Both are put down from a little height, the driver with its engine started in drive as the
    # play window does on a respawn; they settle before anything is measured.
    driver.respawn()
    fleet.place()
    for frame: int in SETTLE_FRAMES:
        _frame(driver, fleet)
    var start: Array[Vector3] = [_where(driver), _where(extra)]
    var throttle: Key = (driver.keys["throttle"] as Array)[0] as Key
    var event: InputEventKey = InputEventKey.new()
    event.keycode = throttle
    event.physical_keycode = throttle
    event.pressed = true
    Input.parse_input_event(event)
    Input.flush_buffered_events()
    for frame: int in HELD_FRAMES:
        _frame(driver, fleet)
    event.pressed = false
    Input.parse_input_event(event)
    Input.flush_buffered_events()
    var driven: float = _where(driver).distance_to(start[0])
    var added: float = _where(extra).distance_to(start[1])
    if driven < MIN_DRIVEN_M:
        return fail("with the throttle held the driven truck moved %.2f m: the world did not step it" % driven, driven)
    if added > MAX_DRIFT_M:
        return fail("the added vehicle moved %.2f m while only the driver's throttle was held" % added, added)
    return ok("added 8 m behind; driven %.2f m, added %.3f m in %d frames" % [driven, added, HELD_FRAMES], driven)


## One frame as the play window runs it: the driver's controls, the extras', the world's step.
func _frame(driver: PlayDrive, fleet: PlayFleet) -> void:
    driver.begin(1.0 / 60.0)
    fleet.begin(1.0 / 60.0)
    driver.finish()
    fleet.finish()


func _where(drive: PlayDrive) -> Vector3:
    var positions: PackedVector3Array = drive.solver.get_positions()
    var sum: Vector3 = Vector3.ZERO
    for p: Vector3 in positions:
        sum += p
    return sum / float(positions.size())
