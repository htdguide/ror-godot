extends GateBase
## The beam pass, every beam's force, deformation and breaking, is upstream's `Actor::CalcBeams`:
## compared rig by rig against the function itself compiled from the pinned submodule
## (`tools/build_parity.sh`), with `GetNumActiveConnectedBeams` for its cab rule.
##
## The parts already compared on their own (contact, shocks2/3, differentials) are laws; this is the
## pass that applies them to a structure: the fast inverse square root length, the rate of stretch,
## SHOCK1 bumps (to `sbd_spring` for a `BEAM_HYDRO`, to `DEFAULT_SPRING` otherwise), ropes, support
## beams and their break, plastic deformation both ways and the strength it costs, breaking, and
## the cab rule that refuses to break the last beams of a collision-triangle node. Each rig is run
## several passes without moving, so deformation and softening compound as they do over substeps.
##
## Half the rigs put their beams in detacher groups, positive and negative, so one break takes
## others with it. Not covered, because not modelled here: buoyant hulls sinking when a beam breaks,
## and triggers. Wheel detachers are held by `a_detacher_group_takes_its_wheel_off`.

const ORACLE: String = "build/parity/upstream_oracle"
const TOLERANCE_RELATIVE: float = 1e-6
const RIGS: int = 120
const NODES: int = 6
const BEAMS: int = 10
## Upstream's `SpecialBeam` values against the solver's bound kinds.
const UPSTREAM_BOUND: Array[int] = [0, 1, 5, 6]
const OUR_BOUND: Array[int] = [0, 1, 3, 2]
const DEFAULT_SPRING: float = 9000000.0
const DEFAULT_DAMP: float = 12000.0


static func meta() -> Dictionary:
    return {
        "name": "the_beam_pass_is_upstreams",
        "proves": "the solver's beam pass gives upstream's CalcBeams forces, rest lengths, stresses, strengths and breaks on the same rigs",
        "builds_on": ["beams_deform_and_break", "bounded_beams_oracle", "a_cab_node_is_held_only_by_plain_beams"],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "%d rigs x %d beams, 1 to 20 passes: every force, length, stress and strength within %s, every break the same" % [RIGS, BEAMS, String.num_scientific(TOLERANCE_RELATIVE)],
        "why": "the beam pass was ported by reading; its pieces matched upstream one at a time but the pass that combines them never had been run against upstream's.",
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var root: String = SourceScan.repo_root()
    if not FileAccess.file_exists(root.path_join(ORACLE)):
        return ok("skipped: the upstream oracle is not built. Run tools/build_parity.sh", 0)
    var rigs: Array[Dictionary] = _rigs()
    var lines: PackedStringArray = PackedStringArray()
    for rig: Dictionary in rigs:
        lines.append("beams %d %d %d" % [rig["passes"], NODES, BEAMS])
        for node: Dictionary in rig["nodes"] as Array:
            var p: Vector3 = node["position"]
            var v: Vector3 = node["velocity"]
            lines.append("node %s %s %s %s %s %s %d" % [_n(p.x), _n(p.y), _n(p.z), _n(v.x), _n(v.y), _n(v.z), 1 if node["cab"] else 0])
        for beam: Dictionary in rig["beams"] as Array:
            lines.append("beam %d %d %s %s %s %d %d %s %s %s %s %s %s %s %d" % [beam["a"], beam["b"], _n(beam["rest"]),
                    _n(beam["k"]), _n(beam["d"]), UPSTREAM_BOUND[beam["kind"]], 1 if beam["hydro"] else 0,
                    _n(beam["short"]), _n(beam["long"]), _n(beam["sbd_k"]), _n(beam["sbd_d"]), _n(beam["deform"]),
                    _n(beam["strength"]), _n(beam["plastic"]), beam["group"]])
    var path: String = root.path_join("build/parity/beam_cases.txt")
    var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    file.store_string("\n".join(lines) + "\n")
    file.close()
    var output: Array = []
    var status: int = OS.execute("/bin/sh", ["-c", "'%s' < '%s'" % [root.path_join(ORACLE), path]], output, true)
    if status != 0:
        return fail("the upstream oracle exited %d: %s" % [status, "\n".join(output)])
    var results: PackedStringArray = ("\n".join(output)).strip_edges().split("\n")
    if results.size() != RIGS * (NODES + BEAMS):
        return fail("the oracle returned %d lines for %d rigs" % [results.size(), RIGS])

    var worst: float = 0.0
    var broken: int = 0
    var deformed: int = 0
    var spent: int = 0
    for r: int in RIGS:
        var rig: Dictionary = rigs[r]
        var ours: Dictionary = _ours(rig)
        var forces: PackedVector3Array = ours["forces"]
        var at: int = r * (NODES + BEAMS)
        for i: int in NODES:
            var theirs: PackedStringArray = results[at + i].split(" ", false)
            for axis: int in 3:
                var difference: float = _difference(theirs[axis].to_float(), forces[i][axis])
                if difference > TOLERANCE_RELATIVE:
                    return fail("rig %d node %d force axis %d: upstream %s, ours %s" % [r, i, axis, theirs[axis], _n(forces[i][axis])], difference)
                worst = maxf(worst, difference)
        for i: int in BEAMS:
            var theirs: PackedStringArray = results[at + NODES + i].split(" ", false)
            var mine: Array = (ours["beams"] as Array)[i]
            if (theirs[3] == "1") != bool(mine[3]):
                return fail("rig %d beam %d (%s): upstream %s it, ours %s" % [r, i, rig["beams"][i],
                        "broke" if theirs[3] == "1" else "kept", "broke" if mine[3] else "kept"])
            for j: int in 3:
                var difference: float = _difference(theirs[j].to_float(), float(mine[j]))
                if difference > TOLERANCE_RELATIVE:
                    return fail("rig %d beam %d (%s), %s: upstream %s, ours %s; upstream %s, ours %s" % [r, i, rig["beams"][i],
                            ["rest length", "stress", "strength"][j], theirs[j], _n(float(mine[j])), results[at + NODES + i], mine], difference)
                worst = maxf(worst, difference)
            broken += 1 if theirs[3] == "1" else 0
            var rest: float = float((rig["beams"] as Array)[i]["rest"])
            deformed += 1 if absf(theirs[0].to_float() - rest) > 1e-5 * rest else 0
            spent += 1 if theirs[2].to_float() <= 0.0 else 0
    if broken == 0 or deformed == 0:
        return fail("no case broke (%d) or deformed (%d) a beam: the comparison tested too little" % [broken, deformed])
    return ok("%d rigs, %d beams (%d deformed, %d broken, %d with no strength left) against upstream's CalcBeams, worst %s" % [
            RIGS, RIGS * BEAMS, deformed, broken, spent, String.num_scientific(worst)], worst)


## The same rig in the solver, run through its beam pass alone.
func _ours(rig: Dictionary) -> Dictionary:
    var solver: RefCounted = ClassDB.instantiate("RorSolver") as RefCounted
    for node: Dictionary in rig["nodes"] as Array:
        var index: int = solver.add_node(node["position"], 1.0)
        solver.set_node_velocity(index, node["velocity"])
        solver.set_node_cab(index, node["cab"])
    for beam: Dictionary in rig["beams"] as Array:
        var b: int = solver.add_beam(beam["a"], beam["b"], beam["rest"], beam["k"], beam["d"])
        solver.set_beam_limits(b, beam["deform"], beam["strength"], beam["plastic"], not beam["hydro"])
        solver.set_beam_detacher_group(b, beam["group"])
        if (beam["kind"] as int) != 0:
            # What a SHOCK1 bumps into: its shock's rates for a `shocks` row (`BEAM_HYDRO`), else
            # upstream's defaults; the builder makes that choice (`a_squashed_tyre_…`).
            var hydro: bool = beam["hydro"]
            solver.set_beam_bounds(b, OUR_BOUND[beam["kind"]], beam["short"], beam["long"],
                    beam["sbd_k"] if hydro else DEFAULT_SPRING, beam["sbd_d"] if hydro else DEFAULT_DAMP, 1.0)
    var forces: PackedVector3Array = solver.beam_pass_probe(rig["passes"])
    var beams: Array = []
    for b: int in BEAMS:
        beams.append([solver.get_beam_rest_length(b), solver.get_beam_stress(b), solver.beam_strength(b), solver.beam_broken(b)])
    return {"forces": forces, "beams": beams}


## Deterministic small rigs: nodes about a metre apart (a few centimetres in one rig in eight) and
## moving, beams between random pairs stretched or squashed up to 40% and of every kind, a third of
## the nodes on a collision triangle.
func _rigs() -> Array[Dictionary]:
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = 20261012
    var rigs: Array[Dictionary] = []
    for r: int in RIGS:
        var nodes: Array[Dictionary] = []
        # One rig in eight is a few centimetres across, so a squashed beam's rest length meets
        # upstream's 10 cm floor (`MIN_BEAM_LENGTH`).
        var size: float = 0.08 if r % 8 == 5 else 1.0
        for i: int in NODES:
            nodes.append({
                "position": Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * size,
                "velocity": Vector3(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0)),
                "cab": rng.randf() < 0.33,
            })
        var beams: Array[Dictionary] = []
        for i: int in BEAMS:
            var a: int = rng.randi_range(0, NODES - 1)
            var b: int = (a + rng.randi_range(1, NODES - 1)) % NODES
            var length: float = (nodes[a]["position"] as Vector3).distance_to(nodes[b]["position"])
            var kind: int = rng.randi_range(0, 3)
            beams.append({
                "a": a, "b": b, "rest": length * rng.randf_range(0.6, 1.4),
                "k": rng.randf_range(1e4, 1e7), "d": rng.randf_range(10.0, 1e4),
                "kind": kind, "hydro": rng.randf() < 0.3,
                "short": rng.randf_range(0.0, 0.4), "long": rng.randf_range(0.0, 0.4),
                "sbd_k": rng.randf_range(1e5, 9e6), "sbd_d": rng.randf_range(100.0, 2e4),
                "deform": rng.randf_range(1e3, 1e6), "strength": rng.randf_range(1e3, 3e6),
                "plastic": rng.randf_range(0.0, 0.5) if rng.randf() < 0.5 else 0.0,
                # Half the rigs group their beams, positive and negative, so a break takes others.
                "group": [0, 1, -1, 2, -2][rng.randi_range(0, 4)] if r % 2 == 1 else 0,
            })
        rigs.append({"nodes": nodes, "beams": beams, "passes": [1, 3, 20][r % 3]})
    return rigs


func _difference(theirs: float, ours: float) -> float:
    return absf(theirs - ours) / maxf(absf(theirs), 1.0)


func _n(value: float) -> String:
    return String.num_scientific(value)
