extends GateBase
## A .tscn carries structure only: nodes, names, and references to scripts and
## resources. Every tunable lives in res://config or a .gdshader.
##
## Development here is CLI-only, so a value buried in a scene file is a value nobody
## reviews and nobody can diff meaningfully. This gate is what makes "scenes are thin
## and generated" a property of the repository rather than a habit.

const ALLOWED_PROPERTIES: Array[String] = ["script"]


static func meta() -> Dictionary:
    return {
        "name": "scene_purity",
        "proves": "no .tscn contains a tunable property assignment",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "only %s may be assigned in a .tscn" % str(ALLOWED_PROPERTIES),
        "why": (
            "a CLI-only workflow cannot review a value that lives in a scene file."
            + " Keeping scenes structural is what makes every visual change a text diff."
        ),
        "budget_s": 25.0,
        "needs_gpu": false,
        "milestone": "M0",
    }


func run(_harness: Node) -> Dictionary:
    var offenders: PackedStringArray = PackedStringArray()
    var scenes: PackedStringArray = SourceScan.find_files(SourceScan.repo_root(), ["tscn"])
    for path: String in scenes:
        var lines: PackedStringArray = SourceScan.read_lines(path)
        var in_node: bool = false
        for i: int in lines.size():
            var line: String = lines[i].strip_edges()
            if line.begins_with("["):
                in_node = line.begins_with("[node")
                continue
            if not in_node or line.is_empty() or line.begins_with(";"):
                continue
            var eq: int = line.find("=")
            if eq < 0:
                continue
            var property_name: String = line.substr(0, eq).strip_edges()
            if not ALLOWED_PROPERTIES.has(property_name):
                offenders.append(
                    "%s:%d assigns '%s'" % [SourceScan.relative(path), i + 1, property_name]
                )
    if offenders.size() > 0:
        return fail("scene carries tunables: " + ", ".join(offenders), offenders.size())
    return ok("%d scene files are structural only" % scenes.size(), 0)
