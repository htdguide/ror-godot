extends GateBase
## Every keyword upstream's parser knows is cut from a file the way upstream cuts it: either it opens
## a section, and the rows after it are that section's, or it leaves the open section alone, and is
## not read as one of its rows.
##
## PLAN's section inventory. The brakes of 29 library cars were lost to one keyword, `AntiLockBrakes`,
## that ours did not know and read as a row of `brakes`; this asks the same question of all of them.
## A bare keyword ours does not know is taken for a section header, so `rescuer` or `forwardcommands`
## between two rows of `commands2` would drop the second.
##
## The oracle is upstream's own source: its keyword list (`IDENTIFY_KEYWORD_REGEX_STRING`, in the
## order of the `Keyword` enum, each marked as standing alone or carrying values) and the switch in
## `Parser::ProcessCurrentLine`, where every keyword it names returns without opening a section and
## every other one begins its own, except that `end` and the module lines (`section`, `end_section`,
## whose handler `ProcessChangeModuleLine` begins no block) close the open one. Each keyword is put
## between two `nodes` rows inside a module and the document read. `forset` belongs to the flexbody
## above it.

const REGEXES: String = "vendor/rigs-of-rods/source/main/resources/rig_def_fileformat/RigDef_Regexes.h"
const PARSER: String = "vendor/rigs-of-rods/source/main/resources/rig_def_fileformat/RigDef_Parser.cpp"
const APPLICATION: String = "vendor/rigs-of-rods/source/main/Application.h"
const BELONGS_TO_THE_ROW_ABOVE: PackedStringArray = ["forset"]


static func meta() -> Dictionary:
    return {
        "name": "every_keyword_is_read_where_upstream_reads_it",
        "proves": "every keyword in upstream's parser either opens a section or leaves the open one alone, as upstream's ProcessCurrentLine decides, and none is read as a row",
        "builds_on": [],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "all of upstream's keywords: section openers open a section, the rest keep the open section and are not its rows",
        "why": "a keyword ours did not know was read as data: 29 library cars lost their brakes to one, and several bare ones would drop the rows after them.",
        "budget_s": 10.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var root: String = SourceScan.repo_root()
    if not FileAccess.file_exists(root.path_join(REGEXES)):
        return ok("skipped: vendor/rigs-of-rods is not checked out", 0)
    var keywords: Array[Array] = _keywords(root)
    var enum_names: PackedStringArray = _enum_names(root)
    var cases: Dictionary = _switch_cases(root)
    var stays: PackedStringArray = cases["stays"]
    var closes: PackedStringArray = cases["closes"]
    if keywords.size() < 100 or enum_names.size() < keywords.size() or stays.size() < 30:
        return fail("upstream's lists did not read: %d keywords, %d enum names, %d switch cases" % [keywords.size(), enum_names.size(), stays.size()])
    var wrong: PackedStringArray = PackedStringArray()
    var opened: int = 0
    var kept: int = 0
    var closed: int = 0
    for i: int in keywords.size():
        var word: String = keywords[i][0]
        var standalone: bool = keywords[i][1]
        var opens: bool = not stays.has(enum_names[i + 1])
        var line: String = word if standalone else word + " 1, 2"
        var document: TruckDocument = TruckDocument.new()
        # Inside a module, so `end_section` has one to end: upstream ignores it in the root.
        document.read("t\nsection 1 m\nnodes\n0, 0, 0, 0\n%s\n1, 1, 1, 1\nend" % line)
        var after: String = ""
        var keyword_row_in_nodes: bool = false
        for row: Dictionary in document.rows:
            if row["line"] == "1, 1, 1, 1":
                after = row["section"]
            if row["line"] == line and row["section"] == "nodes" and not bool(row["header"]):
                keyword_row_in_nodes = true
        if closes.has(enum_names[i + 1]):
            closed += 1
            if after == "nodes":
                wrong.append("%s closes the open section upstream; the row after it is still a nodes row" % word)
            continue
        if opens:
            opened += 1
            if after != word.to_lower():
                wrong.append("%s opens a section upstream; the row after it went to '%s'" % [word, after])
        else:
            kept += 1
            if after != "nodes":
                wrong.append("%s leaves the section open upstream; the row after it went to '%s'" % [word, after])
            if keyword_row_in_nodes and not BELONGS_TO_THE_ROW_ABOVE.has(word):
                wrong.append("%s was read as a row of nodes" % word)
    if not wrong.is_empty():
        return fail("%d of %d keywords cut differently from upstream: %s" % [wrong.size(), keywords.size(), "; ".join(wrong)], wrong.size())
    return ok("%d keywords: %d open a section, %d leave it open, %d close it; all as upstream" % [keywords.size(), opened, kept, closed], keywords.size())


## [name, standalone] per keyword, in the order of `Keyword` from 1.
func _keywords(root: String) -> Array[Array]:
    var out: Array[Array] = []
    var pattern: RegEx = RegEx.create_from_string("E_KEYWORD_(BLOCK|INLINE|INLINE_UNSEPARATED)\\(\"([A-Za-z0-9_]+)\"\\)")
    var text: String = FileAccess.get_file_as_string(root.path_join(REGEXES))
    var start: int = text.find("#define IDENTIFY_KEYWORD_REGEX_STRING")
    for m: RegExMatch in pattern.search_all(text.substr(start)):
        out.append([m.get_string(2), m.get_string(1) == "BLOCK"])
    return out


## The `Keyword` enum's members in order, `INVALID` first.
func _enum_names(root: String) -> PackedStringArray:
    var text: String = FileAccess.get_file_as_string(root.path_join(APPLICATION))
    var start: int = text.find("enum class Keyword")
    var body: String = text.substr(start, text.find("};", start) - start)
    var out: PackedStringArray = PackedStringArray()
    for m: RegExMatch in RegEx.create_from_string("\\n\\s*([A-Z][A-Z0-9_]*)\\s*[,=\\n]").search_all(body):
        out.append(m.get_string(1))
    return out


## The keywords `ProcessCurrentLine`'s switch names before its `default:`: {stays, closes}. A case
## group whose handler changes module or begins the empty block closes the open section; every other
## returns leaving it open. `INVALID` is no keyword.
func _switch_cases(root: String) -> Dictionary:
    var text: String = FileAccess.get_file_as_string(root.path_join(PARSER))
    var start: int = text.find("switch (keyword)")
    var body: String = text.substr(start, text.find("default:", start) - start)
    var stays: PackedStringArray = PackedStringArray()
    var closes: PackedStringArray = PackedStringArray()
    var pending: PackedStringArray = PackedStringArray()
    for line: String in body.split("\n"):
        var m: RegExMatch = RegEx.create_from_string("case Keyword::([A-Z0-9_]+):").search(line)
        if m != null:
            if m.get_string(1) != "INVALID":
                pending.append(m.get_string(1))
            continue
        if pending.is_empty():
            continue
        if line.contains("ProcessChangeModuleLine") or line.contains("ParseDirectiveSection()") \
                or line.contains("BeginBlock(Keyword::INVALID)"):
            closes.append_array(pending)
            pending.clear()
        elif line.contains("return;") or line.contains("break;"):
            stays.append_array(pending)
            pending.clear()
    return {"stays": stays, "closes": closes}
