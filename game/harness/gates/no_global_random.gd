extends GateBase
## Bans Godot's global random functions.
##
## Determinism is what makes a captured frame comparable between runs. A single global
## randi() anywhere in the project makes a golden image flicker, and the resulting
## failure looks like a rendering regression rather than a seeding mistake. The project
## has exactly one RandomNumberGenerator, owned by the harness and seeded from --seed.

## Lines carrying this marker are exempt: a gate that defines the banned identifiers
## necessarily contains them, and so does any deliberate, reviewed exception.
const ALLOW_MARKER: String = "# random-ok:"
const BANNED: Array[String] = ["randi(", "randf(", "randf_range(", "randi_range(", "randomize("]  # random-ok: the ban list itself


static func meta() -> Dictionary:
    return {
        "name": "no_global_random",
        "proves": "no source file uses Godot's global random functions",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "0 unmarked uses of the global random functions",
        "why": (
            "one unseeded call makes captures non-reproducible, and the failure presents"
            + " as a rendering regression rather than as the seeding bug it is."
        ),
        "budget_s": 10.0,
        "needs_gpu": false,
        "milestone": "M0",
    }


func run(_harness: Node) -> Dictionary:
    var offenders: PackedStringArray = PackedStringArray()
    for path: String in SourceScan.find_files(SourceScan.repo_root(), ["gd"]):
        var lines: PackedStringArray = SourceScan.read_lines(path)
        for i: int in lines.size():
            var line: String = lines[i]
            if SourceScan.is_comment_or_blank(line) or line.contains(ALLOW_MARKER):
                continue
            for banned: String in BANNED:
                # A method call on an explicit RandomNumberGenerator is fine; only the
                # bare global form is banned.
                if line.contains(banned) and not line.contains("rng." + banned):
                    offenders.append(
                        "%s:%d uses %s" % [SourceScan.relative(path), i + 1, banned]
                    )
    if offenders.size() > 0:
        return fail("global random used: " + ", ".join(offenders), offenders.size())
    return ok("no global random calls", 0)
