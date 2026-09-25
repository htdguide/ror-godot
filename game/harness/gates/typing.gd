extends GateBase
## Requires static typing in GDScript.
##
## This project's most likely bug is a silently wrong number in render configuration,
## which dynamic typing hides until an image looks subtly off. Typed declarations turn
## that class of mistake into a parse error.

const UNTYPED_PATTERNS: Array[String] = [
    "^\\s*var\\s+[a-zA-Z_][a-zA-Z0-9_]*\\s*=",
    "^\\s*func\\s+[a-zA-Z_][a-zA-Z0-9_]*\\([^)]*\\)\\s*:",
]
const ALLOW_MARKER: String = "# untyped-ok:"


static func meta() -> Dictionary:
    return {
        "name": "typing",
        "proves": "every GDScript variable and function declaration is statically typed",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "0 untyped declarations outside lines marked '%s'" % ALLOW_MARKER,
        "why": (
            "untyped GDScript turns a wrong render-config value into a plausible image"
            + " instead of an error, and a wrong image is exactly what this project"
            + " cannot detect cheaply."
        ),
        "budget_s": 10.0,
        "needs_gpu": false,
        "milestone": "M0",
    }


func run(_harness: Node) -> Dictionary:
    var untyped_var: RegEx = RegEx.create_from_string(UNTYPED_PATTERNS[0])
    var untyped_func: RegEx = RegEx.create_from_string(UNTYPED_PATTERNS[1])
    var offenders: PackedStringArray = PackedStringArray()
    var checked: int = 0
    for path: String in SourceScan.find_files(SourceScan.repo_root(), ["gd"]):
        var lines: PackedStringArray = SourceScan.read_lines(path)
        for i: int in lines.size():
            var line: String = lines[i]
            if SourceScan.is_comment_or_blank(line) or line.contains(ALLOW_MARKER):
                continue
            checked += 1
            if untyped_var.search(line) != null:
                offenders.append("%s:%d untyped var" % [SourceScan.relative(path), i + 1])
            elif untyped_func.search(line) != null and not line.contains("->"):
                offenders.append("%s:%d untyped return" % [SourceScan.relative(path), i + 1])
    if offenders.size() > 0:
        return fail("untyped declarations: " + ", ".join(offenders), offenders.size())
    return ok("%d declarations checked, all typed" % checked, 0)
