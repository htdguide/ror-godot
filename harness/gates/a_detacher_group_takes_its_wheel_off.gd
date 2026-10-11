extends GateBase
## A beam of a detacher group breaking takes the rest of its group with it, and the wheels
## `wheeldetachers` names for the group come off: no drive, no brake, no force on the tread. A
## respawn puts them back, as upstream's `SyncReset` does.
##
## Upstream's `CalcBeams` break branch (held to upstream's own code by `the_beam_pass_is_upstreams`)
## and `CalcWheels`, which skips a wheel with `wh_is_detached`. The parser half is upstream's too:
## `detacher_group N` stands over the rows below it until `detacher_group end`. 189 corpus files
## declare detacher groups and 6 detach wheels with them; none of it was read before.
##
## The oracle is the hero with three beams added between two of its frame nodes, in groups 1, -1
## and 0, and `wheeldetachers` taking rear wheel 2 with group 1. The group 1 beam is made to break;
## then the group -1 beam has to be broken too, the group 0 one not, and wheel 2 detached. A detached
## wheel is handed no drive (`CalcDifferentials` skips it), and the hero's rear axle is split, so
## its partner gets half of what the pair would: against an intact truck on the substep after the
## snap, with the same clutch torque in both, wheel 3's torque is half.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const ROWS: String = "\ndetacher_group 1\nbeams\n0, 1\ndetacher_group -1\nbeams\n0, 1\ndetacher_group end\nbeams\n0, 1\nwheeldetachers\n2, 1\n"
const SUBSTEP_HZ: float = 2000.0
const HALF: float = 0.5
const HALF_SLACK: float = 0.001


static func meta() -> Dictionary:
    return {
        "name": "a_detacher_group_takes_its_wheel_off",
        "proves": "detacher_group rows are read, a group's break takes its negative with it and its wheeldetachers wheel off, and a respawn puts them back",
        "builds_on": ["the_beam_pass_is_upstreams", "a_differential_shares_torque_by_its_kind"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "groups read as 1, -1, 0; after the break: beams 1 and -1 broken, 0 whole, wheel 2 detached, its partner's torque %.2f of an intact truck's within %.3f; respawned: whole and attached" % [HALF, HALF_SLACK],
        "why": "detacher groups were not read at all: 189 corpus files group beams so a part comes away together, and 6 lose a wheel that way.",
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var text: String = FileAccess.get_file_as_string(mod_dir.path_join(TRUCK)).replace("\r", "")
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_text(text.replace("\naxles\n", ROWS + "\naxles\n"))
    if error != "":
        return fail("the hero did not parse with the rows added: %s" % error)
    # The three added beams are the last three of the `beams` rows, in file order.
    var added: Array[int] = []
    for beam: int in truck.beam_table.count():
        var nodes: Vector2i = Vector2i(truck.beams[beam * 2], truck.beams[beam * 2 + 1])
        if nodes == Vector2i(truck.node_id_to_index["0"], truck.node_id_to_index["1"]):
            added.append(beam)
    if added.size() < 3:
        return fail("found %d beams between nodes 0 and 1, expected the hero's own and the three added" % added.size())
    added = added.slice(added.size() - 3)
    var groups: Array[int] = []
    for beam: int in added:
        groups.append(truck.beam_table.detacher[beam])
    if groups != [1, -1, 0] or truck.beam_table.wheel_detachers != [{"wheel": 2, "group": 1}]:
        return fail("read groups %s and wheel detachers %s, not [1, -1, 0] and wheel 2 on group 1" % [groups, truck.beam_table.wheel_detachers])
    var intact: float = _partner_torque(truck, added[0], false)

    var solver: RefCounted = _drive(truck, added[0], true)
    var detached: float = absf(solver.get_wheel_torque(3))
    var broken: Array[bool] = [solver.beam_broken(added[0]), solver.beam_broken(added[1]), solver.beam_broken(added[2])]
    if broken != [true, true, false]:
        return fail("after the break, beams in groups 1, -1, 0 are broken %s, not [true, true, false]" % [broken])
    if not solver.wheel_detached(2) or solver.wheel_detached(3):
        return fail("wheel 2 detached %s, wheel 3 %s: group 1 should take wheel 2 only" % [solver.wheel_detached(2), solver.wheel_detached(3)])
    var share: float = detached / maxf(intact, 1e-6)
    if absf(share - HALF) > HALF_SLACK:
        return fail("wheel 3 pulls %.1f N m beside a detached wheel 2 against %.1f on an intact truck: %.3f, not half" % [detached, intact, share], share)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.15)
    if solver.wheel_detached(2) or solver.beam_broken(added[1]):
        return fail("respawned, wheel 2 detached %s and the group -1 beam broken %s" % [solver.wheel_detached(2), solver.beam_broken(added[1])])
    return ok("groups 1, -1, 0 read; the break took 1 and -1, kept 0, took wheel 2; wheel 3 pulls %.3f of an intact truck's; respawned whole" % share, share)


## The hero driven in first for a second, then its group 1 beam made to snap when `snap`, and two
## substeps more. The two runs are the same truck to the bit until the snap.
func _drive(truck: TruckParser, beam: int, snap: bool) -> RefCounted:
    var solver: RefCounted = RigBuilder.build(truck, 0.02)["solver"] as RefCounted
    solver.set_ground(0.0, true)
    # The hero's locked differential between axles would answer a lost wheel with its own torsion;
    # without it the rear axle's split is all that shares the drive.
    solver.clear_axle_differentials()
    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(0.5)
    for chunk: int in 60:
        solver.step(1.0 / SUBSTEP_HZ, 33)
    if snap:
        # A tenth of its length at rest, and next to no strength.
        solver.set_beam_rest_length(beam, solver.get_beam_rest_length(beam) * 0.1)
        solver.set_beam_limits(beam, 1.0, 1.0, 0.0, true)
    # Two substeps: the beam breaks in the first one's beam pass, after the wheels have been driven,
    # and in the second the wheel is off while the clutch's torque still comes from the substep
    # before, the same in both runs. Later the engine answers the lost wheel and the split blurs.
    solver.step(1.0 / SUBSTEP_HZ, 2)
    return solver


func _partner_torque(truck: TruckParser, beam: int, snap: bool) -> float:
    return absf(_drive(truck, beam, snap).get_wheel_torque(3))
