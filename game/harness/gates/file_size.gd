extends GateBase
## Enforces the file-size caps. The cap is a proxy for single responsibility: a file
## that outgrows it is doing more than one job, and the fix is extraction.

const GD_MAX_LINES: int = 400
const SHADER_MAX_LINES: int = 300
const CPP_MAX_LINES: int = 600


static func meta() -> Dictionary:
    return {
        "name": "file_size",
        "proves": "no source file exceeds its size cap",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "%d lines for .gd, %d for .gdshader, %d for C++"
            % [GD_MAX_LINES, SHADER_MAX_LINES, CPP_MAX_LINES]
        ),
        "why": (
            "the caps are a measurable proxy for single responsibility. They are set"
            + " where a file stops fitting in one reading, and the only allowed fix is"
            + " extraction, never reformatting to dodge the counter."
        ),
        "budget_s": 10.0,
        "needs_gpu": false,
        "milestone": "M0",
    }


func run(_harness: Node) -> Dictionary:
    var root: String = SourceScan.repo_root()
    var limits: Dictionary = {
        "gd": GD_MAX_LINES,
        "gdshader": SHADER_MAX_LINES,
        "gdshaderinc": SHADER_MAX_LINES,
        "cpp": CPP_MAX_LINES,
        "h": CPP_MAX_LINES,
    }
    var offenders: PackedStringArray = PackedStringArray()
    var worst: int = 0
    for path: String in SourceScan.find_files(root, ["gd", "gdshader", "gdshaderinc", "cpp", "h"]):
        var count: int = SourceScan.read_lines(path).size()
        var cap: int = limits[path.get_extension()] as int
        worst = maxi(worst, count)
        if count > cap:
            offenders.append("%s: %d lines > %d" % [SourceScan.relative(path), count, cap])
    if offenders.size() > 0:
        return fail("over cap: " + ", ".join(offenders), offenders.size())
    return ok("all source files within cap; largest is %d lines" % worst, worst)
