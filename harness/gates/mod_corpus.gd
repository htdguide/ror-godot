extends GateBase
## Two hundred archive mods: each one loads, or says by name what it could not read, and none of
## them hangs or takes the engine down.
##
## M1's acceptance 5, with the deliberately weak claim PLAN R6 asks of it. The legacy shim's risk
## is that fifteen years of malformed mods explode its scope, and the answer is not fidelity across
## the archive — that is C2 — but breadth with honesty: a mod this project cannot read has to fail
## with the name of the section or row it fell on, not silently and not fatally.
##
## The corpus is what `tools/fetch_corpus.sh` unpacked under `assets/corpus/`: the most-downloaded
## resources of the archive's vehicle categories, fetched through the portal Rigs of Rods' own
## client uses, each beside a `CORPUS.json` naming its source and licence. It is not committed
## and not part of the vehicle library, so only this gate pays for it.
##
## What "loads" means here: the file parses to nodes and the rig builds in the solver. What
## "names its feature" means: a refusal carries a message, and every row the parser skipped is
## reported under the section it was in — the report below lists the sections this corpus uses
## that the parser does not read yet, which is the list C2 works from. A hang is an actor over
## `HANG_S`; a crash never reaches the report at all, which is why the harness's own budget stands
## behind this gate.

const CORPUS_DIR: String = "assets/corpus"
const MIN_RESOURCES: int = 200
## Seconds one actor may take to parse and build before it is called a hang.
const HANG_S: float = 10.0
const MOST_LISTED: int = 12


static func meta() -> Dictionary:
    return {
        "name": "mod_corpus",
        "proves": "every actor in a corpus of at least %d archive resources either loads into the solver or refuses with a named reason, every unread section is named, and no actor hangs" % MIN_RESOURCES,
        "builds_on": ["truck_parse"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "at least %d resources; every actor parsed and rig-built or refused with a message;"
            % MIN_RESOURCES + " no actor over %.0f s" % HANG_S
        ),
        "why": (
            "the shim's risk is that the archive's fifteen years of malformed mods explode its"
            + " scope. Breadth is proven by a weak claim held over many mods — loads, or fails"
            + " by name — and the named unread sections are the worklist for format coverage."
        ),
        "budget_s": 600.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var root: String = SourceScan.repo_root().path_join(CORPUS_DIR)
    if not DirAccess.dir_exists_absolute(root):
        return ok("skipped: no corpus at %s; run tools/fetch_corpus.sh" % CORPUS_DIR, 0)
    var resources: int = 0
    var actors: Array[String] = []
    _scan(root, actors)
    for entry: String in DirAccess.get_directories_at(root):
        if FileAccess.file_exists(root.path_join(entry).path_join("CORPUS.json")):
            resources += 1
    if resources < MIN_RESOURCES:
        return ok(
            "skipped: %d resources in the corpus, under the %d the claim is about; run"
            % [resources, MIN_RESOURCES] + " tools/fetch_corpus.sh",
            resources
        )

    var loaded: int = 0
    var refused: Dictionary = {}
    var unread: Dictionary = {}
    var row_faults: Dictionary = {}
    var slowest: float = 0.0
    var slowest_name: String = ""
    for path: String in actors:
        var began: int = Time.get_ticks_usec()
        var truck: TruckParser = TruckParser.new()
        var refusal: String = truck.parse_file(path)
        var reason: String = refusal
        if refusal == "":
            var rig: Dictionary = RigBuilder.build(truck, 0.0)
            reason = rig.get("error", "") as String
        var took: float = float(Time.get_ticks_usec() - began) / 1000000.0
        if took > slowest:
            slowest = took
            slowest_name = path.get_file()
        if took > HANG_S:
            return fail("%s took %.1f s to parse and build: a hang" % [path.get_file(), took], took)
        if reason != "":
            refused[_family(reason)] = int(refused.get(_family(reason), 0)) + 1
            continue
        loaded += 1
        for section: String in truck.sections_seen.keys():
            if int(truck.sections_parsed.get(section, 0)) < int(truck.sections_seen[section]):
                unread[section] = int(unread.get(section, 0)) + 1
        for message: String in truck.errors:
            var family: String = _family(message)
            row_faults[family] = int(row_faults.get(family, 0)) + 1
    var refused_total: int = 0
    for family: String in refused:
        refused_total += int(refused[family])
    return ok(
        (
            "%d resources, %d actors: %d load, %d refuse by name (%s); unread sections across the"
            + " corpus: %s; row faults: %s; slowest %s at %.2f s"
        ) % [
            resources, actors.size(), loaded, refused_total, _listed(refused),
            _listed(unread), _listed(row_faults), slowest_name, slowest
        ],
        actors.size()
    )


## Every actor file under a directory, however deep a pack buried it.
static func _scan(directory: String, out: Array[String]) -> void:
    for file: String in DirAccess.get_files_at(directory):
        if RorVehicleLibrary.ACTOR_EXTENSIONS.has(file.get_extension().to_lower()):
            out.append(directory.path_join(file))
    for sub: String in DirAccess.get_directories_at(directory):
        if sub.begins_with("_") or sub.begins_with("."):
            continue
        _scan(directory.path_join(sub), out)


## A message's family: its words before the colon, numbers taken out, so a thousand rows that
## fell the same way count as one named feature.
static func _family(message: String) -> String:
    var head: String = message.split(":")[0]
    var out: PackedStringArray = PackedStringArray()
    for word: String in head.split(" ", false):
        out.append("<n>" if word.is_valid_int() or word.is_valid_float() else word)
    return " ".join(out).substr(0, 48)


static func _listed(counts: Dictionary) -> String:
    if counts.is_empty():
        return "none"
    var keys: Array = counts.keys()
    keys.sort_custom(func(a: String, b: String) -> bool: return int(counts[a]) > int(counts[b]))
    var parts: PackedStringArray = PackedStringArray()
    for i: int in mini(keys.size(), MOST_LISTED):
        parts.append("%s %d" % [keys[i], int(counts[keys[i]])])
    if keys.size() > MOST_LISTED:
        parts.append("and %d more" % (keys.size() - MOST_LISTED))
    return ", ".join(parts)
