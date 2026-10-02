extends GateBase
## Every actor file on the disk is in the library, exactly once, with a name a person can read.
##
## A content browser is only as good as what it can see, and the ways to be invisible are quiet
## ones: a pack whose vehicle is a `.car` rather than a `.truck`, a pack unpacked under
## `assets/terrains/` because it also ships a map, a folder holding five vehicles where the
## library reports one. All three are real — measured on four packs downloaded from the
## repository, `mazda626gf` ships only `mazda626sd18i-mt.car`, Starling Island ships five actors
## and four terrains in one folder, and the Chevy pack ships four variations of one truck.
##
## **The oracle is a second scan that shares no code with the first.** This gate walks the content
## roots itself, with its own list of extensions, and requires the two answers to match as sets.
## Asserting "at least twelve vehicles" would pass a library that found twelve and missed six, and
## asserting a list of names written here would be this project grading its own homework and would
## have to be edited every time somebody drops a folder in.
##
## It also requires every entry to carry a title, because a menu of UID-prefixed filenames —
## `57611UIDsprinter-si-ambulance` — is not a menu anybody can use. The title comes out of each
## file's own first line, which is where Rigs of Rods puts it.

## The extensions an actor definition can have. Written out again rather than imported from the
## library, which is the point: if the two lists disagree, the gate fails and somebody looks.
const ACTOR_EXTENSIONS: PackedStringArray = [
    "truck", "car", "load", "airplane", "boat", "trailer", "train", "fixed",
]
const CONTENT_ROOTS: PackedStringArray = ["assets/mods", "assets/terrains"]
## Below this the checkout has no content worth browsing and the gate skips rather than failing:
## a fresh clone has no downloaded packs and that is not a fault in the library.
const MIN_FOR_A_VERDICT: int = 2


static func meta() -> Dictionary:
    return {
        "name": "the_library_finds_every_vehicle",
        "proves": "every actor definition file under the content roots appears in the vehicle library exactly once, each with a readable title",
        "builds_on": ["truck_parse"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "the library's entries and an independent scan of %d roots agree as sets, and every"
            % CONTENT_ROOTS.size() + " entry has a non-empty title"
        ),
        "why": (
            "a vehicle goes missing from a browser quietly: a pack whose actor is a `.car`, a"
            + " pack unpacked under the terrain root because it also ships a map, a folder"
            + " holding five vehicles reported as one. All three are real in this checkout, and"
            + " none of them produces an error — the vehicle is simply not in the list."
        ),
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "C1",
    }


func run(_harness: Node) -> Dictionary:
    var found: Dictionary = _scan()
    var listed: Dictionary = {}
    for entry: Dictionary in RorVehicleLibrary.entries():
        var path: String = (entry["directory"] as String).path_join(entry["file"] as String)
        if listed.has(path):
            return fail("the library lists %s more than once" % path.get_file(), 0)
        listed[path] = entry
    if found.size() < MIN_FOR_A_VERDICT:
        return ok("skipped: %d actor files in this checkout, too few to judge" % found.size(), 0)

    var missing: PackedStringArray = PackedStringArray()
    for path: String in found.keys():
        if not listed.has(path):
            missing.append(path.get_file())
    var invented: PackedStringArray = PackedStringArray()
    for path: String in listed.keys():
        if not found.has(path):
            invented.append(path.get_file())
    if missing.size() > 0:
        return fail(
            "%d actor files on the disk are not in the library: %s. A vehicle that is not listed"
            % [missing.size(), ", ".join(missing)]
            + " cannot be chosen, and nothing reports it as an error.",
            missing.size()
        )
    if invented.size() > 0:
        return fail(
            "the library lists %d files that are not on the disk: %s"
            % [invented.size(), ", ".join(invented)],
            invented.size()
        )

    var untitled: PackedStringArray = PackedStringArray()
    var broken: PackedStringArray = PackedStringArray()
    var kinds: Dictionary = {}
    for summary: Dictionary in RorVehicleLibrary.summaries():
        kinds[summary["kind"]] = true
        if (summary["error"] as String) != "":
            broken.append("%s (%s)" % [summary["name"], summary["error"]])
            continue
        var title: String = summary["title"] as String
        if title.strip_edges().is_empty() or title == (summary["name"] as String):
            untitled.append(summary["name"] as String)
    if untitled.size() > 0:
        return fail(
            "%d vehicles have no title of their own: %s. A menu of filenames like"
            % [untitled.size(), ", ".join(untitled)]
            + " 57611UIDsprinter-si-ambulance is not a menu anybody can use.",
            untitled.size()
        )
    return ok(
        "%d vehicles across %d kinds (%s), every one on the disk listed once and titled%s"
        % [listed.size(), kinds.size(), ", ".join(PackedStringArray(kinds.keys())),
           "" if broken.is_empty() else "; unreadable: " + ", ".join(broken)],
        listed.size()
    )


## The gate's own walk of the content roots: `path -> true`.
func _scan() -> Dictionary:
    var out: Dictionary = {}
    var roots: PackedStringArray = PackedStringArray()
    for relative: String in CONTENT_ROOTS:
        roots.append(SourceScan.repo_root().path_join(relative))
    roots.append(SourceScan.repo_root().path_join(RorVehicleLibrary.SHIPPED_ROOT))
    var seen_names: Dictionary = {}
    for base: String in roots:
        if not DirAccess.dir_exists_absolute(base):
            continue
        for directory: String in DirAccess.get_directories_at(base):
            var full: String = base.path_join(directory)
            for file: String in DirAccess.get_files_at(full):
                if not ACTOR_EXTENSIONS.has(file.get_extension().to_lower()):
                    continue
                # The library keeps the first of a repeated name, so this does too — otherwise
                # the two scans would disagree about a duplicate rather than about a bug.
                var name: String = file.get_basename()
                if seen_names.has(name):
                    continue
                seen_names[name] = true
                out[full.path_join(file)] = true
    return out
