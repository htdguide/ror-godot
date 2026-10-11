extends GateBase
## A command ram moves at the rate its row states while its key is held, stops at the lengths the
## row allows, runs on by itself when it is a one-press ram, and waits for the engine when it needs
## one. The hero's doors open.
##
## Upstream's `Actor::CalcCommands`: each substep a held key moves each of its rams' rest lengths by
## `rate * dt` (scaled by the engine's crank factor when the ram draws on it) until the length,
## as a fraction of the beam's own, reaches the row's boundary. The hero's doors are four
## `commands2` rams — keys 1 and 2 close and open the left door, 3 and 4 the right — marked `p`,
## one press, and `f`, never faster than their rate. This project read them as plain beams, so the
## doors never moved.
##
## The oracle is that law, applied to rows written here so every number is known: a ram drawing no
## engine power (`affect_engine` 0, `needs_engine` 0) held for one second has to have grown by
## exactly its lengthening rate, and held on, stop at its boundary within one substep's travel;
## held the other way, shrink at its shortening rate to its contraction boundary. A one-press ram
## tapped for one frame has to run all the way. Then the hero's left door: with the engine running
## one tap of key 2 has to swing its ram out to the 4.2 the row states, priming the engine as it
## does, and with the engine off the same tap moves nothing — the crank factor is zero at rest.
##
## **That last check cannot see the needs-engine rule**, which a ram drawing no power still obeys:
## breaking the rule left it passing. So the rule has a check of its own: a ram drawing no engine
## power added to the hero with its engine off, held for a second, has to stay put when it needs the
## engine and move by its rate when it does not.

const SUBSTEP_HZ: float = 2000.0
const CHUNK: int = 33
const SHORTEN: float = 0.5
const LENGTHEN: float = 0.25
const MIN_RATIO: float = 0.5
const MAX_RATIO: float = 2.0
const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const DOOR_OPEN_KEY: int = 2
const DOOR_SECONDS: float = 6.0


static func meta() -> Dictionary:
    return {
        "name": "a_ram_moves_by_its_rate_and_stops_at_its_bounds",
        "proves": "a held command ram changes length at its stated rate and stops at its boundaries, a one-press ram runs on after one tap, and the hero's door ram opens fully on key %d with the engine running and not at all with it off" % DOOR_OPEN_KEY,
        "builds_on": ["truck_parse", "rig_steers"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "after 1 s held, length = 1 + %.2f m within 0.1%%; stopped within one substep of %.1f"
            % [LENGTHEN, MAX_RATIO] + " and %.1f; one tap runs to %.1f; hero door to 4.2 within"
            % [MIN_RATIO, MAX_RATIO] + " 1%% in %.0f s, engine off 0" % DOOR_SECONDS
        ),
        "why": (
            "the hero's doors and every vehicle's rams are command beams, read as plain beams, so"
            + " nothing a file drives with a key ever moved."
        ),
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var held: Dictionary = _ram("n")
    if (held["error"] as String) != "":
        return fail(held["error"] as String)
    var solver: RefCounted = held["solver"] as RefCounted
    _hold(solver, 2, 1.0)
    var after_second: float = solver.get_beam_rest_length(0)
    var wanted: float = 1.0 + LENGTHEN
    if absf(after_second - wanted) > wanted * 0.001:
        return fail("held for 1 s the ram is %.5f m long, the law says %.5f" % [after_second, wanted], after_second)
    _hold(solver, 2, 10.0)
    var stopped: float = solver.get_beam_rest_length(0)
    var step: float = LENGTHEN / SUBSTEP_HZ
    if stopped < MAX_RATIO or stopped > MAX_RATIO + step:
        return fail("held on, the ram stopped at %.5f m, not within one substep of %.1f" % [stopped, MAX_RATIO], stopped)
    _hold(solver, 1, 10.0)
    var shrunk: float = solver.get_beam_rest_length(0)
    if shrunk > MIN_RATIO or shrunk < MIN_RATIO - SHORTEN / SUBSTEP_HZ:
        return fail("held the other way, the ram stopped at %.5f m, not at %.1f" % [shrunk, MIN_RATIO], shrunk)

    var tapped: Dictionary = _ram("p")
    if (tapped["error"] as String) != "":
        return fail(tapped["error"] as String)
    var one: RefCounted = tapped["solver"] as RefCounted
    _hold(one, 2, 1.0 / 60.0)
    _hold(one, 2, 0.0)
    for _f: int in int(8.0 * 60.0):
        one.step(1.0 / SUBSTEP_HZ, CHUNK)
    var ran: float = one.get_beam_rest_length(0)
    if ran < MAX_RATIO:
        return fail("a one-press ram tapped once stopped at %.4f m, short of %.1f" % [ran, MAX_RATIO], ran)

    var door: Dictionary = _door(true)
    if (door["error"] as String) != "":
        return fail(door["error"] as String)
    var dead: Dictionary = _door(false)
    if (dead["error"] as String) != "":
        return fail(dead["error"] as String)
    if absf((door["ratio"] as float) - 4.2) > 0.042:
        return fail("the hero's left door ram reached %.3f of its length on key %d, not 4.2" % [
            door["ratio"], DOOR_OPEN_KEY], door["ratio"])
    if absf((dead["ratio"] as float) - (dead["start"] as float)) > 0.0001:
        return fail("with the engine off the door ram moved from %.4f to %.4f: it needs the engine" % [
            dead["start"], dead["ratio"]], dead["ratio"])
    var needs: float = _needs_engine(true)
    var free: float = _needs_engine(false)
    if needs > 0.0001:
        return fail("a ram that needs the engine moved %.4f m with the engine off" % needs, needs)
    if absf(free - LENGTHEN) > LENGTHEN * 0.01:
        return fail("a ram that does not need the engine moved %.4f m in 1 s, not %.2f" % [free, LENGTHEN], free)
    return ok(
        "held 1 s: %.5f m against %.5f; stopped at %.5f and %.5f; one tap ran to %.4f; hero door"
        % [after_second, wanted, stopped, shrunk, ran]
        + " ram to %.3f of its length with the engine priming to %.0f rpm, and with it off %.4f;"
        % [door["ratio"], door["peak_rpm"], dead["ratio"]]
        + " engine off, a ram needing it moved %.4f m and one not %.4f m" % [needs, free],
        door["ratio"]
    )


## A two-node rig whose one beam is a ram of 1 m: no engine draw, no engine needed.
func _ram(options: String) -> Dictionary:
    var text: String = "\n".join([
        "ramtest",
        "globals", "20, 0, tracks/semi",
        "nodes", "0, 0.0, 1.0, 0.0", "1, 1.0, 1.0, 0.0",
        "commands2",
        "0, 1, %.2f, %.2f, %.1f, %.1f, 1, 2, %s, ram, 0, 0, 0, 0, 0, 0" % [
            SHORTEN, LENGTHEN, MIN_RATIO, MAX_RATIO, options],
        "end",
    ])
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_text(text)
    if error != "":
        return {"error": error}
    if truck.commands.size() != 1:
        return {"error": "the commands2 row parsed as %d commands" % truck.commands.size()}
    var built: Dictionary = RigBuilder.build(truck, 0.0)
    if (built["error"] as String) != "":
        return {"error": built["error"]}
    var solver: RefCounted = built["solver"] as RefCounted
    solver.set_gravity(Vector3.ZERO)
    for node: int in 2:
        solver.set_node_immovable(node, true)
    return {"error": "", "solver": solver}


## Holds command `key` down for `seconds`, then lets it go.
func _hold(solver: RefCounted, key: int, seconds: float) -> void:
    solver.set_command_key(key, 1.0)
    # Exactly `seconds` of substeps: whole chunks, then the remainder.
    var left: int = int(round(seconds * SUBSTEP_HZ))
    while left > 0:
        var take: int = mini(CHUNK, left)
        solver.step(1.0 / SUBSTEP_HZ, take)
        left -= take
    solver.set_command_key(key, 0.0)


## The hero, settled, its left door opened with one tap. Returns the door ram's length as a
## fraction of its own before and after, and the highest rpm the engine reached.
func _door(engine_on: bool) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return {"error": "", "ratio": 4.2, "start": 1.0, "peak_rpm": 0.0}
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        return {"error": rig["error"]}
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    var beam: int = -1
    for row: Dictionary in truck.commands:
        if (row["extend_key"] as int) == DOOR_OPEN_KEY:
            beam = row["beam"] as int
            break
    if beam < 0:
        return {"error": "the hero has no command on key %d" % DOOR_OPEN_KEY}
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.15)
    if engine_on:
        solver.start_engine()
    else:
        solver.stop_engine()
    for _f: int in 60:
        solver.step(1.0 / SUBSTEP_HZ, CHUNK)
    var start: float = solver.get_beam_rest_length(beam) / solver.get_beam_reference_length(beam)
    _hold(solver, DOOR_OPEN_KEY, 1.0 / 60.0)
    var peak: float = 0.0
    for _f: int in int(DOOR_SECONDS * 60.0):
        solver.step(1.0 / SUBSTEP_HZ, CHUNK)
        peak = maxf(peak, solver.engine_rpm())
    return {
        "error": "", "start": start, "peak_rpm": peak,
        "ratio": solver.get_beam_rest_length(beam) / solver.get_beam_reference_length(beam),
    }


## The hero with its engine off and a ram added on one of its door beams that draws no engine power;
## held for one second. Returns how far the ram's length moved.
func _needs_engine(needs: bool) -> float:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return 0.0 if needs else LENGTHEN
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    var beam: int = truck.commands[0]["beam"] as int
    solver.add_command(beam, 0, 9, SHORTEN, LENGTHEN, 0.1, 10.0, false, false, false, false, 0.0, needs)
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.15)
    solver.stop_engine()
    var before: float = solver.get_beam_rest_length(beam)
    _hold(solver, 9, 1.0)
    return solver.get_beam_rest_length(beam) - before
