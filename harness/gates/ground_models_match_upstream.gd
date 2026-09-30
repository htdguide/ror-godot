extends GateBase
## The surface friction values are Rigs of Rods', not ours.
##
## `GroundModels` is a copy of upstream's `ground_models.cfg`, and a copy is a thing that
## drifts. This parses the file in the pinned submodule and checks every number against it, so
## the copy is verified rather than trusted — the same reason the parity oracle is extracted
## from source rather than kept.
##
## These numbers are not cosmetic. They decide whether a vehicle slides or rolls: a rollover
## threshold is fixed by the track width and centre of mass, and whether the tyres can deliver
## that much lateral force before letting go is decided entirely here.

const CONFIG: String = "vendor/rigs-of-rods/resources/skeleton/config/ground_models.cfg"
## Names as they appear in the file, mapped to the order of GroundModels.SURFACES values.
const KEYS: Array[String] = [
    "adhesion velocity",
    "static friction coefficient",
    "sliding friction coefficient",
    "hydrodynamic friction",
    "stribeck velocity",
]


static func meta() -> Dictionary:
    return {
        "name": "ground_models_match_upstream",
        "proves": "every surface friction value matches Rigs of Rods' own ground_models.cfg",
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "%d values per surface, exactly equal to the pinned upstream file" % KEYS.size(),
        "why": (
            "these decide whether a vehicle slides or tips, and they are a copy of someone"
            + " else's file. A copy that is trusted rather than checked is how a project ends"
            + " up with numbers nobody chose and nobody can defend."
        ),
        "budget_s": 15.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var path: String = SourceScan.repo_root().path_join(CONFIG)
    if not FileAccess.file_exists(path):
        return ok("skipped: the Rigs of Rods submodule is not checked out", 0)
    var upstream: Dictionary = _parse(path)
    if upstream.is_empty():
        return fail("no surfaces could be read from %s" % CONFIG)

    var checked: int = 0
    for name: String in GroundModels.ORDER:
        if not upstream.has(name):
            return fail("upstream's ground_models.cfg has no surface '%s'" % name)
        var theirs: Dictionary = upstream[name] as Dictionary
        var ours: Array = GroundModels.SURFACES[name] as Array
        for i: int in KEYS.size():
            if not theirs.has(KEYS[i]):
                return fail("upstream's '%s' states no '%s'" % [name, KEYS[i]])
            var expected: float = theirs[KEYS[i]] as float
            if not is_equal_approx(float(ours[i]), expected):
                return fail(
                    "%s '%s' is %.4f here and %.4f upstream"
                    % [name, KEYS[i], float(ours[i]), expected],
                    float(ours[i]) - expected
                )
            checked += 1
    return ok(
        "%d values across %d surfaces match the pinned ground_models.cfg; grip runs from"
        % [checked, GroundModels.ORDER.size()]
        + " %.2f on ice to %.2f on asphalt"
        % [
            float((GroundModels.SURFACES["ice"] as Array)[1]),
            float((GroundModels.SURFACES["asphalt"] as Array)[1]),
        ],
        0
    )


## The INI-ish file upstream uses: [section] headers, `key = value` lines, `;` comments.
func _parse(path: String) -> Dictionary:
    var out: Dictionary = {}
    var section: String = ""
    for raw: String in SourceScan.read_lines(path):
        var line: String = raw.strip_edges()
        if line.is_empty() or line.begins_with(";"):
            continue
        if line.begins_with("[") and line.ends_with("]"):
            section = line.substr(1, line.length() - 2)
            out[section] = {}
            continue
        var equals: int = line.find("=")
        if equals < 0 or section == "":
            continue
        var key: String = line.substr(0, equals).strip_edges()
        var value: String = line.substr(equals + 1).strip_edges()
        if value.is_valid_float():
            (out[section] as Dictionary)[key] = value.to_float()
    return out
