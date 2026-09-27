extends GateBase
## Every terrain in the library loads, and says what it is.
##
## Terrains arrive here as directories dropped under `assets/terrains/` — downloaded, unzipped,
## never converted — so the library is whatever is on disk, and what is on disk changes without
## any code changing. That makes it exactly the thing that needs a standing check rather than a
## one-off: the next terrain a person adds is the one this project has never read.
##
## The claim is small on purpose. Not that a terrain is good, or drivable, or looks like its
## author's screenshots — only that every directory in the library answers the four questions a
## session has to ask of it before it can open a window: what is it called, how big is it, how
## tall, and where does a vehicle start.

const MIN_SIZE_M: float = 100.0
const MAX_SIZE_M: float = 100000.0


static func meta() -> Dictionary:
    return {
        "name": "terrain_library_loads_what_it_holds",
        "proves": "every terrain directory in the library loads and reports its own name, extent and spawn point",
        "builds_on": ["ror_terrain_matches_its_files"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "every terrain in assets/terrains/ loads, is between %.0f m and %.0f m across, and"
            % [MIN_SIZE_M, MAX_SIZE_M] + " states a spawn inside itself"
        ),
        "why": (
            "the library is the filesystem, so it changes without any code changing, and the"
            + " terrain somebody adds next is the one this project has never read. A session"
            + " should find out that a terrain is unreadable from a gate, not from a window that"
            + " opens onto nothing."
        ),
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var summaries: Array[Dictionary] = RorTerrainLibrary.summaries()
    if summaries.is_empty():
        return ok("skipped: the terrain library is empty", 0)
    var reported: PackedStringArray = PackedStringArray()
    for summary: Dictionary in summaries:
        var where: String = summary["directory"] as String
        if (summary["error"] as String) != "":
            return fail(
                "%s does not load: %s" % [where, summary["error"]], summaries.size()
            )
        var size: float = summary["size_m"] as float
        if size < MIN_SIZE_M or size > MAX_SIZE_M:
            return fail(
                "%s says it is %.0f m across: that is not a terrain's own extent" % [where, size],
                size
            )
        var start: Vector3 = summary["start"] as Vector3
        if start.x < 0.0 or start.z < 0.0 or start.x > size or start.z > size:
            return fail(
                "%s starts a vehicle at %v, outside its own %.0f m map"
                % [where, start, size],
                start.length()
            )
        reported.append("%s (%s, %.0f m)" % [where, summary["name"], size])
    return ok(
        "%d terrains in the library: %s" % [summaries.size(), ", ".join(reported)],
        summaries.size()
    )
