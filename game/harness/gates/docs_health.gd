extends GateBase
## Keeps the documentation tree readable and honest: every document under its size cap,
## every internal link resolving, every document naming its audience.
##
## One oversized document is how documentation becomes unreviewable, and a broken link
## is how it becomes untrusted. Both are cheap to check and expensive to notice late.

const DOC_MAX_LINES: int = 400
const EXEMPT: Array[String] = ["docs/PLAN.md"]
const AUDIENCE_SCAN_LINES: int = 6


static func meta() -> Dictionary:
    return {
        "name": "docs_health",
        "proves": "documents stay under the size cap, name their audience, and link only to files that exist",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "%d lines per document; 0 broken relative links" % DOC_MAX_LINES,
        "why": (
            "the size cap is the same single-responsibility proxy the code uses, and a"
            + " broken link is the cheapest possible signal that a document has drifted"
            + " away from the tree it describes."
        ),
        "budget_s": 10.0,
        "needs_gpu": false,
        "milestone": "M0",
    }


func run(_harness: Node) -> Dictionary:
    var root: String = SourceScan.repo_root()
    var link_pattern: RegEx = RegEx.create_from_string("\\]\\(([^)#:]+)\\)")
    var offenders: PackedStringArray = PackedStringArray()
    var docs: PackedStringArray = SourceScan.find_files(root, ["md"])
    for path: String in docs:
        var rel: String = SourceScan.relative(path)
        var lines: PackedStringArray = SourceScan.read_lines(path)
        if lines.size() > DOC_MAX_LINES and not EXEMPT.has(rel):
            offenders.append("%s: %d lines > %d" % [rel, lines.size(), DOC_MAX_LINES])
        if rel.begins_with("docs/") and not EXEMPT.has(rel) and not _names_audience(lines):
            offenders.append("%s: first lines do not name an audience" % rel)
        for i: int in lines.size():
            for found: RegExMatch in link_pattern.search_all(lines[i]):
                var target: String = found.get_string(1).strip_edges()
                if target.begins_with("http"):
                    continue
                var resolved: String = path.get_base_dir().path_join(target).simplify_path()
                if not FileAccess.file_exists(resolved) and not DirAccess.dir_exists_absolute(resolved):
                    offenders.append("%s:%d broken link '%s'" % [rel, i + 1, target])
    if offenders.size() > 0:
        return fail("documentation problems: " + ", ".join(offenders), offenders.size())
    return ok("%d documents healthy" % docs.size(), docs.size())


func _names_audience(lines: PackedStringArray) -> bool:
    for i: int in mini(AUDIENCE_SCAN_LINES, lines.size()):
        if lines[i].to_lower().contains("audience:"):
            return true
    return false
