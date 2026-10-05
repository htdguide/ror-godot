extends GateBase
## No source file holds mutable state in a `static var`.
##
## A `static var` is process-global. With one gate per process that is invisible; D0 runs the
## whole suite in one process, one gate at a time in its own container, and process-global state
## is exactly what a container cannot contain. The failure it produces is the worst kind: a gate
## that passes alone and fails as the fortieth of a run, or the reverse, with a number that looks
## plausible either way.
##
## Two of these were live when this gate was written and neither had ever failed a run:
##
## - `TerrainWorld` was a class of static functions over a static shape and surface map, so the
##   terrain built last was a property of the process. A caller that asked for `lattice()`
##   without having populated in its own run was served the previous run's map.
## - `BlockoutWorld._clouds` was a build option assigned in `build()` and read in `_build_sky()`,
##   so the sky a world got depended on what the last world built had asked for. Every lighting
##   gate in this project is graded against a stated sky.
##
## Both are fixed by construction rather than by care: one is an instance the harness owns, the
## other is a parameter.
##
## **The allowlist is names, not patterns.** An exemption is a human deciding that one specific
## variable is a memo rather than state, for a reason written down beside it. A rule that waves
## through anything shaped like a cache would have waved through both of the bugs above.

## `file basename -> variable name` a human has exempted, with the reason in the source.
const ALLOWED: Dictionary = {
    "flare_sprite.gd": "_glow_sprite",
}


static func meta() -> Dictionary:
    return {
        "name": "static_state",
        "proves": "no source file holds mutable state in a static var, so a gate cannot be affected by one that ran before it",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "0 static vars outside the named allowlist",
        "why": (
            "D0 runs the whole suite in one process. A static var is process-global, so it is"
            + " state a gate container cannot contain, and the bug it causes is order-dependent"
            + " — a gate that passes alone and fails in a suite, with a plausible number either"
            + " way. Two were live when this was written and neither had ever failed a run."
        ),
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "D0",
    }


func run(_harness: Node) -> Dictionary:
    var offenders: PackedStringArray = PackedStringArray()
    var exempted: PackedStringArray = PackedStringArray()
    var checked: int = 0
    for path: String in SourceScan.find_files(SourceScan.repo_root(), ["gd"]):
        var file: String = path.get_file()
        var lines: PackedStringArray = SourceScan.read_lines(path)
        for i: int in lines.size():
            var line: String = lines[i]
            if SourceScan.is_comment_or_blank(line):
                continue
            checked += 1
            var name: String = _static_var_name(line)
            if name == "":
                continue
            if (ALLOWED.get(file, "") as String) == name:
                exempted.append("%s:%s" % [file, name])
                continue
            offenders.append("%s:%d static var %s" % [SourceScan.relative(path), i + 1, name])
    if offenders.size() > 0:
        return fail(
            "process-global state: " + ", ".join(offenders)
            + ". Make it an instance a container owns, or a parameter; an exemption goes in"
            + " ALLOWED with its reason in the source.",
            offenders.size()
        )
    return ok(
        "%d lines checked, no process-global state; %d exempted by name (%s)"
        % [checked, exempted.size(), ", ".join(exempted)],
        0
    )


## The name a `static var` declaration introduces, or "" when the line declares none.
##
## Matched on the declaration rather than on the words appearing anywhere, so a line that
## mentions `static var` in a string or in code that builds one is not a false positive.
func _static_var_name(line: String) -> String:
    var stripped: String = line.strip_edges()
    if not stripped.begins_with("static var "):
        return ""
    var rest: String = stripped.trim_prefix("static var ").strip_edges()
    var name: String = rest.split(":", true, 1)[0]
    name = name.split("=", true, 1)[0]
    return name.strip_edges()
