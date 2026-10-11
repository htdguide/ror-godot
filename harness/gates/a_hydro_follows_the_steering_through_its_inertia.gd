extends GateBase
## A steering ram (`hydros`) follows the steering through its own inertia when its row or the
## inertia defaults ask for one, and a respawn puts the controls back at rest the way upstream's
## `SyncReset` does: steering straight, hydro inertia at rest, command keys let go, no differential
## wound up. Command keys keep their inertia across it, as upstream's do.
##
## The oracle is arithmetic on upstream's `slow10` curve, which is 0.1 everywhere: a hydro on it
## moves its output 0.0001 a substep, so after one second (2000 substeps) of a full-lock command
## that the steering itself reaches in half that, the output is exactly 0.2 and a 1 m hydro of
## factor 0.5 stands at 1 - 0.2 x 0.5 = 0.9 m. Without inertia it follows the steering to 0.5 m.
##
## The reset is checked as what it leaves: after a respawn the steering state is 0, the hydro's next
## substep with the steering let go is its full length (a hydro still holding 0.2 would shorten),
## a held command key no longer drives its ram, and the hero's locked rear axle, wound by a turn, is
## at 0.

const SUBSTEP_HZ: float = 2000.0
const CHUNK: int = 33
const FACTOR: float = 0.5
const TOLERANCE: float = 0.001
## Without inertia the hydro follows the steering state, which at full lock steps 0.002 of lock a
## substep about 1 (its ramp of 3 a second plus the centring of 1): one step is this many metres.
const STEERING_STEP_M: float = FACTOR * (3.0 + 1.0) / SUBSTEP_HZ
const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"


static func meta() -> Dictionary:
    return {
        "name": "a_hydro_follows_the_steering_through_its_inertia",
        "proves": "a hydro with inertia lags the steering by upstream's curve, and a respawn resets steering, hydro inertia, command keys and differential wind as upstream's SyncReset does",
        "builds_on": ["rig_steers"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "slow10, 1 s full lock: hydro 0.9 m within %.1f%% (0.5 without, within one steering step); after respawn steering 0, hydro 1 m, held key moves 0, wind 0" % (TOLERANCE * 100.0),
        "why": "every steering ram followed the wheel at once whatever its file asked, and a respawn kept the steering, the keys and the differentials as they were.",
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var lagged: Dictionary = _steer("1, 1, slow10, slow10", "")
    var defaults: Dictionary = _steer("", "set_inertia_defaults 1, 1, slow10, slow10")
    var plain: Dictionary = _steer("", "")
    for case: Array in [["row", lagged, 0.9], ["defaults", defaults, 0.9], ["none", plain, 0.5]]:
        var got: Dictionary = case[1] as Dictionary
        if (got["error"] as String) != "":
            return fail(got["error"] as String)
        var want: float = case[2] as float
        var slack: float = want * TOLERANCE if case[0] != "none" else STEERING_STEP_M
        if absf((got["length"] as float) - want) > slack:
            return fail("%s: after 1 s of full lock the hydro is %.5f m, the curve says %.3f" % [
                case[0], got["length"], want], got["length"])
    if absf(lagged["after_reset"] as float - 1.0) > 1e-5:
        return fail("respawned, the hydro's next substep left it %.6f m, not its full 1 m: its inertia kept the lock" % lagged["after_reset"], lagged["after_reset"])
    if absf(lagged["steer_after_reset"] as float) > 0.0:
        return fail("respawned, the steering state is %.3f, not straight" % lagged["steer_after_reset"])
    if absf(lagged["ram_after_reset"] as float) > 0.0:
        return fail("respawned, a command key held before it moved its ram %.6f m" % lagged["ram_after_reset"])
    var wind: Array = _hero_wind()
    if (wind[0] as float) <= 0.0001 and (wind[0] as float) >= -0.0001:
        return fail("the hero's locked rear axle was not wound by the turn (%.6f m): nothing to reset" % wind[0])
    if absf(wind[1] as float) > 0.0:
        return fail("respawned, the hero's rear axle is still wound %.6f m" % wind[1])
    return ok(
        "1 s full lock: row %.5f m, defaults %.5f m, none %.5f m; respawned: steering 0, hydro %.6f m,"
        % [lagged["length"], defaults["length"], plain["length"], lagged["after_reset"]]
        + " held key moved 0, hero wind %.5f m to 0" % wind[0],
        lagged["length"]
    )


## A two-node rig whose beam is a 1 m hydro of `FACTOR`, plus a ram on key 2; steered full lock for
## a second, then respawned with key 2 held. Returns the hydro's length after the second, and after
## the respawn the hydro's length one substep later, the steering state and how far the ram moved.
func _steer(inertia: String, header: String) -> Dictionary:
    var text: String = "\n".join([
        "hydrotest",
        "globals", "20, 0, tracks/semi",
        "nodes", "0, 0.0, 1.0, 0.0", "1, 1.0, 1.0, 0.0", "2, 0.0, 2.0, 0.0",
        header,
        "hydros",
        "0, 1, %.2f, n%s" % [FACTOR, (", " + inertia) if inertia != "" else ""],
        "commands2",
        "0, 2, 0.25, 0.25, 0.5, 100.0, 1, 2, n, ram, 0, 0, 0, 0, 0, 0",
        "end",
    ])
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_text(text)
    if error != "" or truck.hydros.size() != 1:
        return {"error": "the test rig did not parse: %s (%d hydros)" % [error, truck.hydros.size()]}
    var built: Dictionary = RigBuilder.build(truck, 0.0)
    if (built["error"] as String) != "":
        return {"error": built["error"]}
    var solver: RefCounted = built["solver"] as RefCounted
    solver.set_gravity(Vector3.ZERO)
    for node: int in 3:
        solver.set_node_immovable(node, true)
    var hydro_beam: int = truck.hydros[0]["beam"] as int
    var ram_beam: int = truck.commands[0]["beam"] as int
    solver.set_steer_command(1.0)
    _run(solver, 2000)
    var length: float = solver.get_beam_rest_length(hydro_beam)
    solver.set_command_key(2, 1.0)
    _run(solver, 1)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.15)
    for node: int in 3:
        solver.set_node_immovable(node, true)
    solver.set_steer_command(0.0)
    var ram_before: float = solver.get_beam_rest_length(ram_beam)
    var steer: float = solver.steer_state()
    _run(solver, 1)
    return {
        "error": "", "length": length, "after_reset": solver.get_beam_rest_length(hydro_beam),
        "steer_after_reset": steer, "ram_after_reset": solver.get_beam_rest_length(ram_beam) - ram_before,
    }


## The hero's rear axle wind after two seconds of a locked full-lock turn, and after a respawn.
func _hero_wind() -> Array:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return [1.0, 0.0]
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.02)
    var solver: RefCounted = rig["solver"] as RefCounted
    var truck: TruckParser = rig["truck"] as TruckParser
    solver.set_ground(0.0, true)
    solver.toggle_wheel_differentials()
    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(0.2)
    solver.set_steer_command(DriveCfg.steer_command(1.0))
    _run(solver, 4000)
    var wound: float = solver.wheel_differential_wind(1)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.15)
    return [wound, solver.wheel_differential_wind(1)]


func _run(solver: RefCounted, substeps: int) -> void:
    while substeps > 0:
        var take: int = mini(CHUNK, substeps)
        solver.step(1.0 / SUBSTEP_HZ, take)
        substeps -= take
