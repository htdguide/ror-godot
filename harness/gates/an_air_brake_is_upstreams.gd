extends GateBase
## An `airbrakes` row is upstream's air brake: `ParseAirbrakes` reads its fourteen fields, the
## spawner gives it an area of width by length, 3 and 4 step it a fifth less or more (Ctrl+3 and
## Ctrl+4 to none and full), and `Airbrake::applyForce` drags its four nodes by the sine of its
## angle and the air's density at the reference node's height. Drawn as `GfxActor::UpdateAirbrakes`
## places it: turned about its x edge by its step times its maximum angle. Compared step by step
## with `applyForce` compiled from the pinned submodule (`tools/build_parity.sh`).
##
## Ours read the rows as nothing: six corpus airplanes state air brakes, and none slowed or showed.

const ORACLE: String = "build/parity/upstream_oracle"
const CASES: int = 200
const STEPS: int = 20
const PLANE: String = """plane
globals
1000, 0, tracks/semi
nodes
0, 0, 0, 0
1, 1, 0, 0
2, 0, 0, 1
3, 1, 0, 1
beams
0, 1
airbrakes
0, 1, 2, 3, 0.25, 0.5, 0.1, 1.5, 0.75, 60, 0, 0, 1, 1
end"""


static func meta() -> Dictionary:
    return {
        "name": "an_air_brake_is_upstreams",
        "proves": "airbrakes rows are read, stepped by upstream's keys and drag their nodes as upstream's Airbrake::applyForce does, drawn turned as GfxActor::UpdateAirbrakes places them",
        "builds_on": [],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "every force of %d cases x %d steps identical to upstream's; every corpus row builds; steps 0 to 5 by the keys; the drawn edge where upstream's rotation puts it within 1e-5 m" % [CASES, STEPS],
        "why": "six corpus airplanes state air brakes and they did nothing.",
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var truck: TruckParser = TruckParser.new()
    truck.parse_text(PLANE)
    if truck.links.airbrakes.size() != 1 or truck.links.airbrakes[0]["max_angle"] != 60.0 or truck.links.airbrakes[0]["length"] != 0.75:
        return fail("the airbrakes row read as %s" % [truck.links.airbrakes])
    var solver: RorSolver = RigBuilder.build(truck, 0.0)["solver"] as RorSolver
    var keys: AirplaneKeys = AirplaneKeys.new()
    for k: int in 7:
        keys.on_key(KEY_4, solver)
    var full: int = solver.aero_state(-1)["airbrake"]
    keys.on_key(KEY_3, solver)
    var less: int = solver.aero_state(-1)["airbrake"]
    keys.on_key(KEY_3, solver, true)
    var none: int = solver.aero_state(-1)["airbrake"]
    keys.on_key(KEY_4, solver, true)
    if full != 5 or less != 4 or none != 0 or solver.aero_state(-1)["airbrake"] != 5:
        return fail("4 seven times gave %d, 3 then %d, Ctrl+3 %d, Ctrl+4 %d; upstream's are 5, 4, 0, 5" % [full, less, none, solver.aero_state(-1)["airbrake"]])
    # Drawn: the far corner (0, 0, length) of the quad, at full, turned -60 degrees about x.
    var brake: Dictionary = {"nodes": truck.links.airbrakes[0]["nodes"], "offset": truck.links.airbrakes[0]["offset"], "max_angle": 60.0}
    var corner: Vector3 = AirbrakeMesh.frame(brake, truck.nodes, 1.0) * Vector3(0, 0, 0.75)
    var normal: Vector3 = Vector3(0, 0, 1).cross(Vector3(1, 0, 0))
    var origin: Vector3 = Vector3(0.25, 0, 0.5) + normal * 0.1
    var want: Vector3 = origin + Vector3(0, 0, 0.75).rotated(Vector3.RIGHT, deg_to_rad(-60.0)) if normal == Vector3.UP else Vector3.INF
    if corner.distance_to(want) > 1e-5:
        return fail("at full the far corner is drawn at %s, upstream's rotation puts it at %s" % [corner, want])
    var built: int = 0
    var rows: int = 0
    var root: String = SourceScan.repo_root()
    for file: String in ["201_antonov-an-225/adb2UID-an225.airplane", "202_concorde/1af9UID-concorde4350UID.airplane",
            "1071_gavril-mz2-plane/gavrilmz2.airplane", "200_soukhoi-su-37/45e43UID_SU-37.airplane", "96_boeing-767/767shocks.airplane"]:
        var path: String = root.path_join("assets/corpus").path_join(file)
        if not FileAccess.file_exists(path):
            continue
        var plane: TruckParser = TruckParser.new()
        plane.parse_file(path)
        var plane_solver: RorSolver = RigBuilder.build(plane, 0.0)["solver"] as RorSolver
        for row: Dictionary in plane.links.airbrakes:
            rows += 1
            built += 1 if plane_solver.add_airbrake(row["nodes"], row["width"], row["length"], row["max_angle"]) >= 0 else 0
    if built != rows:
        return fail("%d of the corpus's %d air brakes built" % [built, rows])
    var report: String = "row read; keys step 0 to 5; drawn turned as upstream's; %d corpus air brakes build" % rows
    if not FileAccess.file_exists(root.path_join(ORACLE)):
        return ok(report + "; parity skipped: the upstream oracle is not built. Run tools/build_parity.sh", 0)
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = 20261014
    var cases: Array = []
    var lines: PackedStringArray = PackedStringArray()
    for n: int in CASES:
        var params: PackedFloat32Array = PackedFloat32Array([rng.randf_range(0.2, 4.0), rng.randf_range(0.2, 3.0), rng.randf_range(5.0, 90.0)])
        var steps: Array = []
        var parts: PackedStringArray = PackedStringArray(["airbrake", str(STEPS), _n(params[0]), _n(params[1]), _n(params[2])])
        for step: int in STEPS:
            var v: PackedFloat32Array = PackedFloat32Array([float(rng.randi_range(0, 5)), rng.randf_range(-50.0, 9000.0)])
            for k: int in 15:
                v.append(rng.randf_range(-300.0, 300.0) if k < 3 else rng.randf_range(-5000.0, 5000.0))
            steps.append(v)
            parts.append(str(int(v[0])))
            for k: int in range(1, v.size()):
                parts.append(_n(v[k]))
        cases.append([params, steps])
        lines.append(" ".join(parts))
    var path: String = root.path_join("build/parity/airbrake_cases.txt")
    var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    file.store_string("\n".join(lines) + "\n")
    file.close()
    var output: Array = []
    var status: int = OS.execute("/bin/sh", ["-c", "'%s' < '%s'" % [root.path_join(ORACLE), path]], output, true)
    if status != 0:
        return fail("the upstream oracle exited %d: %s" % [status, "\n".join(output)])
    var results: PackedStringArray = ("\n".join(output)).strip_edges().split("\n")
    if results.size() != CASES * STEPS:
        return fail("the oracle printed %d steps, not %d" % [results.size(), CASES * STEPS])
    for i: int in CASES:
        var ours: PackedStringArray = RorSolver.airbrake_probe(cases[i][0], cases[i][1])
        for step: int in STEPS:
            if ours[step].strip_edges() != results[i * STEPS + step].strip_edges():
                return fail("case %d, step %d:\n upstream %s\n ours     %s" % [i, step, results[i * STEPS + step], ours[step]])
    return ok(report + "; %d cases x %d steps identical to upstream's" % [CASES, STEPS], 0)


func _n(value: float) -> String:
    return String.num_scientific(value)
