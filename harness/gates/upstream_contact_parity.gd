extends GateBase
## Our ground contact law against Rigs of Rods' own, case by case.
##
## Every other gate here checks that this project's physics is self-consistent, or that it
## agrees with a textbook. Neither answers the question the project exists to answer: is this
## Rigs of Rods, or is it merely something that behaves plausibly? Upstream is the only oracle
## that settles it, and this is it running.
##
## `tools/build_parity.sh` extracts `primitiveCollision` from the pinned submodule and compiles
## it on its own against a small shim — nine fields of `node_t`, the part of `Ogre::Vector3` it
## uses. Nothing is copied into this repository, so the oracle cannot drift from the upstream
## it claims to be; if the function is renamed or reshaped, extraction fails rather than
## comparing against something stale.
##
## Terrain is not part of the comparison. Both sides are handed a surface normal and a
## penetration depth directly, so the question of which ground each is standing on does not
## arise — which is what makes this checkable at all while the two projects have different
## worlds.

const ORACLE: String = "build/parity/upstream_oracle"
const CASES: int = 500
## Relative, because the forces here span six orders of magnitude: a node barely touching the
## ground carries newtons, and one driven 40 mm into it inside half a millisecond carries half
## a meganewton. An absolute bound is either meaningless at the top of that range or
## unsatisfiable at the bottom.
##
## What is left at this tolerance is float reassociation — the same arithmetic in a different
## order — and nothing else. Running with our own `std::exp` in place of upstream's
## approximation measured 4.4%, so the gap between an algorithmic difference and this bound is
## four orders of magnitude wide.
const TOLERANCE_RELATIVE: float = 0.0001
## Forces below this are compared absolutely instead, so that two near-zero answers do not
## divide into a large ratio.
const MIN_FORCE_N: float = 0.01


static func meta() -> Dictionary:
    return {
        "name": "upstream_contact_parity",
        "proves": "our ground contact law returns what Rigs of Rods' own primitiveCollision returns, across the static, sliding and airborne regimes",
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "%d cases within %.3f%% of upstream's own compiled code" % [CASES, TOLERANCE_RELATIVE * 100.0]
        ),
        "why": (
            "every other gate checks self-consistency or a textbook result, and a solver can"
            + " satisfy both while not being the one this project promises to preserve."
            + " Upstream's own source, compiled and called, is the only thing that settles"
            + " it. The tolerance is not zero because upstream's maths is deliberately"
            + " approximate and ours is exact, which is itself a finding this measures."
        ),
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var root: String = SourceScan.repo_root()
    var binary: String = root.path_join(ORACLE)
    if not FileAccess.file_exists(binary):
        return ok("skipped: the upstream oracle is not built. Run tools/build_parity.sh", 0)
    var solver: RefCounted = ClassDB.instantiate("RorSolver") as RefCounted
    if solver == null:
        return fail("RorSolver is not registered: the GDExtension did not load")

    var cases: Array[Dictionary] = _cases()
    var input: PackedStringArray = PackedStringArray()
    for one: Dictionary in cases:
        input.append(
            "%.9f %.9f %.9f %.9f %.9f %.9f %.9f %.9f %.9f %.9f %.9f %.9f %.9f"
            % [
                one["velocity"].x, one["velocity"].y, one["velocity"].z,
                one["forces"].x, one["forces"].y, one["forces"].z,
                one["mass"], one["friction"],
                one["normal"].x, one["normal"].y, one["normal"].z,
                one["penetration"], one["dt"],
            ]
        )
    var script: String = root.path_join("build/parity/cases.txt")
    var file: FileAccess = FileAccess.open(script, FileAccess.WRITE)
    if file == null:
        return fail("cannot write the case list to %s" % script)
    file.store_string("\n".join(input) + "\n")
    file.close()

    var output: Array = []
    var status: int = OS.execute(
        "/bin/sh", ["-c", "'%s' < '%s'" % [binary, script]], output, true
    )
    if status != 0:
        return fail("the upstream oracle exited %d: %s" % [status, "\n".join(output)])
    var lines: PackedStringArray = ("\n".join(output)).strip_edges().split("\n")
    if lines.size() != cases.size():
        return fail(
            "the oracle returned %d results for %d cases" % [lines.size(), cases.size()]
        )

    var worst: float = 0.0
    var worst_case: Dictionary = {}
    var worst_pair: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
    var compared: int = 0
    var static_cases: int = 0
    for i: int in cases.size():
        var fields: PackedStringArray = lines[i].strip_edges().split(" ", false)
        if fields.size() != 3:
            return fail("the oracle returned '%s' for case %d" % [lines[i], i])
        var theirs: Vector3 = Vector3(
            fields[0].to_float(), fields[1].to_float(), fields[2].to_float()
        )
        var one: Dictionary = cases[i]
        var ours: Vector3 = solver.ground_contact_probe(
            one["velocity"], one["forces"], one["mass"], one["friction"], one["normal"],
            one["penetration"], one["dt"]
        )
        if not is_finite(theirs.length()) or not is_finite(ours.length()):
            return fail("case %d produced a non-finite force" % i)
        if theirs.length() < MIN_FORCE_N and ours.length() < MIN_FORCE_N:
            continue
        compared += 1
        if bool(one["static_regime"]):
            static_cases += 1
        var difference: float = (theirs - ours).length() / maxf(theirs.length(), MIN_FORCE_N)
        if difference > worst:
            worst = difference
            worst_case = one
            worst_pair = [theirs, ours]
    if compared == 0:
        return fail("every case produced no force: the comparison tested nothing")
    if worst > TOLERANCE_RELATIVE:
        return fail(
            "worst case differs by %.4f%%: upstream %v, ours %v, at %.2f m/s slip,"
            % [
                worst * 100.0, worst_pair[0], worst_pair[1],
                (worst_case["velocity"] as Vector3).length(),
            ]
            + " %.4f m penetration, %.1f kg" % [worst_case["penetration"], worst_case["mass"]],
            worst
        )
    return ok(
        "%d cases against upstream's own primitiveCollision, %d of them in static friction:"
        % [compared, static_cases]
        + " worst difference %.5f%%" % (worst * 100.0),
        worst
    )


## Cases spanning the regimes the law switches between: barely touching and deeply
## penetrating, at rest and sliding fast, flat ground and steep, light nodes and heavy.
func _cases() -> Array[Dictionary]:
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = HarnessCfg.SEED
    var out: Array[Dictionary] = []
    for i: int in CASES:
        # Half the cases are deliberately slow, because static friction is a different branch
        # and a random spread would almost never land in it.
        var slow: bool = i % 2 == 0
        var speed: float = rng.randf_range(0.0, 1.5) if slow else rng.randf_range(1.5, 30.0)
        var velocity: Vector3 = Vector3(
            rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 0.2), rng.randf_range(-1.0, 1.0)
        ).normalized() * speed
        var normal: Vector3 = Vector3(
            rng.randf_range(-0.6, 0.6), 1.0, rng.randf_range(-0.6, 0.6)
        ).normalized()
        var mass: float = rng.randf_range(1.5, 20.0)
        out.append({
            "velocity": velocity,
            # A node's accumulated force is dominated by gravity and its beams.
            "forces": Vector3(
                rng.randf_range(-400.0, 400.0),
                rng.randf_range(-1200.0, 200.0),
                rng.randf_range(-400.0, 400.0)
            ),
            "mass": mass,
            "friction": rng.randf_range(0.5, 1.2),
            "normal": normal,
            "penetration": rng.randf_range(0.0, 0.05),
            "dt": 1.0 / 2000.0,
            "static_regime": slow,
        })
    return out
