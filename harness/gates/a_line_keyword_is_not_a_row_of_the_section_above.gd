extends GateBase
## A keyword upstream reads on its own line (`AntiLockBrakes`, `TractionControl`, `CruiseControl`)
## is not a row of whatever section stands above it, and keywords match in any case.
##
## Upstream's parser processes these "immediately, do not change current block". Ours read them as
## data of the open section, and in the library they sit under `brakes`: `AntiLockBrakes 3.5, 15,
## 1500` became a second brakes row, so 29 vehicle files had a brake force of 0 and a parking brake
## of 2.75 (their ABS regulation figure) — no brakes at all.
##
## The oracle is each file's own text: for every library vehicle with a `brakes` section, the
## parsed brake force has to be the first number of the row under that header, and every file
## stating `AntiLockBrakes` or `TractionControl` has to come out with that aid read.

const LIBRARY: String = "assets/mods"
const EXTENSIONS: Array[String] = ["truck", "car", "load", "trailer", "fixed", "boat", "airplane"]


static func meta() -> Dictionary:
    return {
        "name": "a_line_keyword_is_not_a_row_of_the_section_above",
        "proves": "one-line keywords (AntiLockBrakes, TractionControl, CruiseControl) are not read as rows of the section above, and every library brake force is its file's own",
        "builds_on": [],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "every library file: parsed brake force equals its brakes row; every ABS/TC line read",
        "why": "29 library files had no brakes: their AntiLockBrakes line was read as a brakes row.",
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var root: String = SourceScan.repo_root().path_join(LIBRARY)
    if not DirAccess.dir_exists_absolute(root):
        return ok("skipped: no library at %s" % LIBRARY, 0)
    var checked: int = 0
    var aids: int = 0
    for dir: String in DirAccess.get_directories_at(root):
        for file: String in DirAccess.get_files_at(root.path_join(dir)):
            if not EXTENSIONS.has(file.get_extension()):
                continue
            var path: String = root.path_join(dir).path_join(file)
            var text: String = FileAccess.get_file_as_string(path).replace("\r", "")
            var stated: float = _brakes_row(text)
            var truck: TruckParser = TruckParser.new()
            if truck.parse_text(text) != "":
                continue
            if not is_nan(stated):
                checked += 1
                if not is_equal_approx(truck.drivetrain["brake_force"] as float, stated):
                    return fail("%s/%s: brake force parsed as %.1f, its brakes row says %.1f" % [
                        dir, file, truck.drivetrain["brake_force"], stated], truck.drivetrain["brake_force"])
            for pair: Array in [["antilockbrakes", "abs"], ["tractioncontrol", "tc"]]:
                if _states(text, pair[0]):
                    aids += 1
                    if not truck.drivetrain.has(pair[1]):
                        return fail("%s/%s states %s and it was not read" % [dir, file, pair[0]])
    if checked == 0 or aids == 0:
        return fail("nothing to check: %d files with brakes, %d aid lines" % [checked, aids])
    return ok("%d library files: brake force is the file's own; %d ABS/TC lines read" % [checked, aids], checked)


## The first number of the row under the file's `brakes` header, or NAN if it has none.
func _brakes_row(text: String) -> float:
    var lines: PackedStringArray = text.split("\n")
    for i: int in lines.size():
        if lines[i].strip_edges().to_lower() != "brakes":
            continue
        for j: int in range(i + 1, lines.size()):
            var row: String = lines[j].strip_edges()
            if row.is_empty() or row.begins_with(";") or row.begins_with("//"):
                continue
            return row.split(",")[0].strip_edges().to_float()
    return NAN


func _states(text: String, keyword: String) -> bool:
    for line: String in text.split("\n"):
        if line.strip_edges().to_lower().begins_with(keyword):
            return true
    return false
