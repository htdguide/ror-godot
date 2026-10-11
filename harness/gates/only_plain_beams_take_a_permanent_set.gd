extends GateBase
## Overloaded past its yield, a beam from a `beams` row takes a permanent set whatever its options;
## a shock of any of the three kinds, a `ropes` beam and a command ram do not, because upstream
## types those `BEAM_HYDRO` and its deform branch runs only for `BEAM_NORMAL`.
##
## Upstream's spawner: `ProcessBeam` makes `BEAM_NORMAL` (a rope or support beam by option keeps
## that type), while `ProcessShock`, `ProcessShock2`, `ProcessShock3`, `ProcessRope` and
## `ProcessCommand` make `BEAM_HYDRO`. A `ropes` beam yielded here until 2026-10-12, and so did a
## `shocks3` one, being read as a plain beam.
##
## The oracle is that table on one rig holding a beam of each kind, every node held, each beam pulled
## (or for a support beam and the shocks, pushed) half its length for one substep, never breaking.
## Every kind is then far past upstream's 400 kN yield floor (a shock is past its bump). A beam
## that yields has a new rest length.

const SUBSTEP_HZ: float = 2000.0
const STRAIN: float = 0.5
## Section, row, whether upstream's type lets it yield, and which way to load it (+1 pulls).
const KINDS: Array[Array] = [
    ["beams", "%s, %s", true, 1.0],
    ["beams", "%s, %s, r", true, 1.0],
    ["beams", "%s, %s, s", true, -1.0],
    ["shocks", "%s, %s, 50000, 2000, 0.1, 0.1, 1.0", false, -1.0],
    ["shocks2", "%s, %s, 50000, 2000, 1, 1, 60000, 3000, 1, 1, 0.1, 0.1, 1.0", false, -1.0],
    ["shocks3", "%s, %s, 50000, 2000, 1, 0.1, 1, 60000, 3000, 1, 0.1, 1, 0.1, 0.1, 1.0", false, -1.0],
    ["ropes", "%s, %s", false, 1.0],
    ["commands2", "%s, %s, 0.1, 0.1, 0.5, 2.0, 1, 2, n", false, 1.0],
]


static func meta() -> Dictionary:
    return {
        "name": "only_plain_beams_take_a_permanent_set",
        "proves": "beams rows yield whatever their options, and shocks, shocks2, shocks3, ropes and command rams never do, as upstream's BEAM_NORMAL/BEAM_HYDRO split says",
        "builds_on": ["beams_deform_and_break"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "loaded %.0f%% of length past a 400 kN yield: beams rows change rest length, the five other kinds do not change it at all" % (STRAIN * 100.0),
        "why": "ropes and shocks3 beams took a permanent set under load, which upstream's never do.",
        "budget_s": 10.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var lines: PackedStringArray = PackedStringArray(["yieldtest", "globals", "20, 0, tracks/semi", "nodes"])
    for i: int in KINDS.size():
        lines.append("%d, %.1f, 1.0, 0.0" % [i * 2, float(i) * 3.0])
        lines.append("%d, %.1f, 1.0, 1.0" % [i * 2 + 1, float(i) * 3.0])
    # Spring, damping, deform, break: upstream's floor of 400 kN to yield, and never breaks.
    lines.append("set_beam_defaults 9000000, 12000, 400000, 1000000000")
    for i: int in KINDS.size():
        lines.append(KINDS[i][0] as String)
        lines.append((KINDS[i][1] as String) % [i * 2, i * 2 + 1])
    lines.append("end")
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_text("\n".join(lines))
    if error != "" or truck.beam_table.count() != KINDS.size():
        return fail("the test rig did not parse to %d beams: %s (%d)" % [KINDS.size(), error, truck.beam_table.count()])
    var solver: RefCounted = RigBuilder.build(truck, 0.0)["solver"] as RefCounted
    solver.set_gravity(Vector3.ZERO)
    # The parser spawns sections in upstream's order, not the file's, so each beam is found by its
    # nodes: kind `i` joins nodes 2i and 2i + 1.
    var beam_of: Array[int] = []
    beam_of.resize(KINDS.size())
    for beam: int in KINDS.size():
        beam_of[(solver.get_beam_nodes(beam) as Vector2i).x / 2] = beam
    var before: PackedFloat32Array = PackedFloat32Array()
    for i: int in KINDS.size():
        var rest: float = solver.get_beam_rest_length(beam_of[i])
        before.append(rest)
        solver.set_node_immovable(i * 2, true)
        solver.set_node_immovable(i * 2 + 1, true)
        var anchor: Vector3 = solver.get_node_position(i * 2)
        solver.set_node_position(i * 2 + 1, anchor + Vector3(0.0, 0.0, rest * (1.0 + STRAIN * float(KINDS[i][3]))))
    solver.step(1.0 / SUBSTEP_HZ, 1)
    var report: PackedStringArray = PackedStringArray()
    for i: int in KINDS.size():
        var change: float = solver.get_beam_rest_length(beam_of[i]) - before[i]
        var name: String = ("%s %s" % [KINDS[i][0], (KINDS[i][1] as String).get_slice(", ", 2) if KINDS[i][0] == "beams" else ""]).strip_edges()
        if bool(KINDS[i][2]) and absf(change) < 1e-4:
            return fail("%s did not yield: its rest length moved %.6f m" % [name, change], change)
        if not bool(KINDS[i][2]) and change != 0.0:
            return fail("%s yielded %.6f m: upstream's BEAM_HYDRO never does" % [name, change], change)
        report.append("%s %+.4f m" % [name, change])
    return ok(", ".join(report), 0)
