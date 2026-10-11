extends GateBase
## A node with upstream's option `c` passes through the ground, takes no part in a spawn's height,
## and is not a node other vehicles' triangles test.
##
## `c` is NO_GROUND_CONTACT (`ActorSpawner::ProcessNode`): `Actor::CalcNodes` skips the terrain and
## the scenery for such a node, the spawn's vertical offset leaves it out, and the contactable rule
## excludes it unless it is a contacter. Upstream gives every cinecam node the same flag whatever
## the file says. Fifteen vehicles in this library mark nodes `c` — the Gavril family twelve each —
## and none of it was read, so those nodes stood on the ground they were meant to pass through.
##
## The test vehicle is written here: a tetrahedron of three nodes at one height and a fourth hanging
## half a metre below them, marked `c`. On flat ground the three stand on the ground and the fourth
## stays under it; it counts as no contactable node. **The control is the same text without the
## `c`**, in the same run: the fourth node now stands on the ground and is contactable. Then a
## shipped Gavril file has to come out of the parser with its twelve, plus its cinecam nodes.

const SUBSTEP_HZ: float = 2000.0
const SETTLE_FRAMES: int = 120
const HANG_M: float = 0.5
## How far under the ground a passing node must be, and how far an ordinary one may sink.
const UNDER_M: float = 0.3
const SINK_M: float = 0.03
const GAVRIL: Dictionary = {"dir": "assets/mods/gavrilmv4", "file": "gavrilmv4.truck"}
const GAVRIL_MARKED: int = 12


static func meta() -> Dictionary:
    return {
        "name": "a_node_marked_c_touches_no_ground",
        "proves": "a node marked c stays %.1f m under flat ground while its rig stands on it and is not contactable, the same rig unmarked stands it on the ground, and a Gavril file parses its %d marked nodes plus its cinecams" % [UNDER_M, GAVRIL_MARKED],
        "builds_on": ["truck_parse", "a_vehicle_collides_with_the_nodes_its_file_names"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "marked node below -%.1f m and others above -%.2f m; unmarked node above -%.2f m;"
            % [UNDER_M, SINK_M, SINK_M] + " contactable 3 then 4; Gavril %d + cinecams"
            % GAVRIL_MARKED
        ),
        "why": (
            "fifteen vehicles here mark nodes as touching no ground and the option was unread, so"
            + " those nodes stood on the ground, held the spawn up and were hit by other vehicles."
        ),
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var marked: Dictionary = _settle(true)
    var plain: Dictionary = _settle(false)
    for case: Dictionary in [marked, plain]:
        if (case["error"] as String) != "":
            return fail(case["error"] as String)
    if (marked["hanging"] as float) > -UNDER_M:
        return fail(
            "the node marked c settled at %.3f m: it is standing on the ground" % marked["hanging"],
            marked["hanging"]
        )
    if (marked["others"] as float) < -SINK_M:
        return fail("the rest of the marked rig sank to %.3f m" % marked["others"], marked["others"])
    if (plain["hanging"] as float) < -SINK_M:
        return fail(
            "unmarked, the low node settled at %.3f m: the control fell through too, so the"
            % plain["hanging"] + " gate cannot tell c from nothing",
            plain["hanging"]
        )
    if (marked["contactable"] as int) != 3 or (plain["contactable"] as int) != 4:
        return fail("contactable nodes: %d marked, %d unmarked; expected 3 and 4" % [
            marked["contactable"], plain["contactable"]])

    var report: String = ""
    var mod_dir: String = SourceScan.repo_root().path_join(GAVRIL["dir"] as String)
    if DirAccess.dir_exists_absolute(mod_dir):
        var truck: TruckParser = TruckParser.new()
        var error: String = truck.parse_file(mod_dir.path_join(GAVRIL["file"] as String))
        if error != "":
            return fail(error)
        var expected: int = GAVRIL_MARKED + truck.cinecams.size()
        if truck.no_ground_contact.size() != expected:
            return fail("%s: %d nodes touch no ground, expected %d marked and %d cinecams" % [
                GAVRIL["file"], truck.no_ground_contact.size(), GAVRIL_MARKED, truck.cinecams.size()])
        report = "; %s: %d marked + %d cinecams" % [
            GAVRIL["file"], GAVRIL_MARKED, truck.cinecams.size()]
    return ok(
        "marked node at %.3f m under a rig standing at %.3f m, unmarked at %.3f m; contactable"
        % [marked["hanging"], marked["others"], plain["hanging"]]
        + " %d then %d%s" % [marked["contactable"], plain["contactable"], report],
        marked["hanging"]
    )


func _settle(marked: bool) -> Dictionary:
    var text: String = "\n".join([
        "tetrahedron",
        "globals",
        "200, 0, tracks/semi",
        "nodes",
        "0, 0.0, 1.0, 0.0",
        "1, 1.0, 1.0, 0.0",
        "2, 0.5, 1.0, 0.9",
        "3, 0.5, %.2f, 0.3%s" % [1.0 - HANG_M, ", c" if marked else ""],
        "beams",
        "0, 1", "1, 2", "2, 0", "0, 3", "1, 3", "2, 3",
        "end",
    ])
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_text(text)
    if error != "":
        return {"error": error}
    var built: Dictionary = RigBuilder.build(truck, 0.0)
    if (built["error"] as String) != "":
        return {"error": built["error"]}
    var solver: RefCounted = built["solver"] as RefCounted
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.01)
    for _f: int in SETTLE_FRAMES:
        solver.step(1.0 / SUBSTEP_HZ, 33)
    var others: float = INF
    for node: int in 3:
        others = minf(others, solver.get_node_position(node).y)
    return {
        "error": "", "hanging": solver.get_node_position(3).y, "others": others,
        "contactable": solver.contactable_count(),
    }
