extends GateBase
## Every node this project generates carries the number the file that generated it uses, and every
## row of every vehicle in the library is read.
##
## **A numeric node reference is an index into the node array, and the array's order is upstream's
## spawn order rather than the file's layout.** Upstream reads a file into a document and then
## builds it keyword by keyword (`ActorSpawnerFlow.cpp`): declared nodes, then `cinecam`, then
## `wheels`, `wheels2`, `meshwheels`, `meshwheels2`, `flexbodywheels`, and only then anything that
## names a node — the source says so over the beams, `(may reference any generated/user-defined
## node)`. `RegisterNode` throws a declared number away and keeps the order of appearance.
##
## **So where a section is written decides nothing and which section it is decides everything.**
## 30 of this library's 69 actors write `props` or `flexbodies` above the wheel section those rows
## name. Read in file order every one of those rows names a node that does not exist yet: the
## Mazda's four hubcaps and four brake discs, and all four tyres of every Gavril.
##
## **The oracle is the file plus upstream's own arithmetic, counted here and not asked for.** The
## layout and the node count of each wheel section are restated below from `RigDef_Parser.cpp` and
## from upstream's spawn budget, so that a loader that changes its mind about either is caught
## rather than agreed with:
##
##     wheels          rays at field 2, 2 nodes per ray     ParseWheel,           budget +rays*2
##     wheels2         rays at field 3, 4 nodes per ray     ParseWheel2,          budget +rays*4
##     meshwheels      rays at field 3, 2 nodes per ray     _ParseBaseMeshWheel,  budget +rays*2
##     meshwheels2     rays at field 3, 2 nodes per ray     _ParseBaseMeshWheel,  budget +rays*2
##     flexbodywheels  rays at field 3, 4 nodes per ray     ParseFlexBodyWheel,   budget +rays*4
##
## And the second half of the claim is that nothing was dropped on the way: a reader that resolves
## a row it cannot place by skipping it passes an arithmetic check on node counts while losing the
## bodywork. Every actor in the library has to parse with no errors at all.

## Below this there is nothing to judge: a fresh clone has few packs.
const MIN_VEHICLES: int = 2
const LISTED: int = 6
## Where each wheel section states its ray count, and how many nodes it appends per ray.
const RAYS_FIELD: Dictionary = {
    "wheels": 2, "wheels2": 3, "meshwheels": 3, "meshwheels2": 3, "flexbodywheels": 3,
}
const NODES_PER_RAY: Dictionary = {
    "wheels": 2, "wheels2": 4, "meshwheels": 2, "meshwheels2": 2, "flexbodywheels": 4,
}
## The order the node-generating sections are built in, which is the order their nodes are
## numbered in. Declared nodes come before all of them and `cinecam` before every wheel.
const GENERATING_ORDER: PackedStringArray = [
    "cinecam", "wheels", "wheels2", "meshwheels", "meshwheels2", "flexbodywheels",
]


## **It builds on nothing.** `builds_on` means "running this exercises that, at least as hard",
## and the graph stops running what a passing gate implies — so an edge that only records which
## gate came first silently retires a gate. This one counts nodes off a file and parses it.


static func meta() -> Dictionary:
    return {
        "name": "a_generated_node_has_the_number_its_file_uses",
        "proves": "every node this project generates has the index upstream's spawn order gives it, and every actor in the library parses with no errors",
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "node count and first generated index equal to the file's own arithmetic for every"
            + " actor, and zero parse errors across the library"
        ),
        "why": (
            "a numeric node reference is an index, and the index depends on the keyword order"
            + " rather than the file's layout. 30 of 69 actors name a wheel node from a row"
            + " written above the wheel section, and all of those rows were dropped: the Mazda's"
            + " hubcaps and brake discs, and every Gavril's four tyres."
        ),
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "C2",
    }


func run(_harness: Node) -> Dictionary:
    var entries: Array[Dictionary] = RorVehicleLibrary.entries()
    if entries.size() < MIN_VEHICLES:
        return ok("skipped: %d vehicles in this checkout" % entries.size(), 0)
    var problems: PackedStringArray = PackedStringArray()
    var checked: int = 0
    var generated: int = 0
    for entry: Dictionary in entries:
        var path: String = (entry["directory"] as String).path_join(entry["file"] as String)
        var truck: TruckParser = TruckParser.new()
        var refused: String = truck.parse_file(path)
        if refused != "":
            problems.append("%s: %s" % [entry["name"], refused])
            continue
        if not truck.errors.is_empty():
            problems.append("%s: %s" % [entry["name"], truck.errors[0]])
            continue
        var counted: Dictionary = _count(path)
        checked += 1
        generated += int(counted["total"]) - int(counted["declared"])
        if truck.nodes.size() != int(counted["total"]):
            problems.append(
                "%s: its file describes %d nodes and the reader built %d"
                % [entry["name"], int(counted["total"]), truck.nodes.size()]
            )
            continue
        if truck.generated_from != int(counted["before_wheels"]):
            problems.append(
                "%s: its first wheel node is number %d and the reader put it at %d"
                % [entry["name"], int(counted["before_wheels"]), truck.generated_from]
            )
    if problems.size() > 0:
        return fail(
            "%d of %d actors do not number their nodes the way their files do: %s"
            % [problems.size(), entries.size(), "; ".join(problems.slice(0, LISTED))],
            problems.size()
        )
    return ok(
        "%d actors, %d generated nodes, every one numbered where its own file puts it"
        % [checked, generated],
        generated
    )


## What a file's own arithmetic says: {"declared", "before_wheels", "total"}.
##
## Counted with its own scan rather than through `TruckParser`, because the reader is what is
## under test. `RorText.fields` and the comment rules are shared with it; the section order, the
## ray field and the node count per ray are restated here from upstream.
func _count(path: String) -> Dictionary:
    var rows: Dictionary = {}
    var section: String = ""
    var declared: int = 0
    var first: bool = true
    for raw_line: String in RorText.read(path).split("\n"):
        var line: String = raw_line.get_slice(";", 0).get_slice("//", 0).strip_edges()
        if line.is_empty():
            continue
        if first:
            first = false
            continue
        if not line.contains(",") and not line.contains(" ") and not line.contains("\t"):
            if not line.is_valid_float():
                section = line.to_lower()
                continue
        if TruckLexer.is_metadata(line) or TruckLexer.directive_of(line) != "":
            continue
        if section == "nodes" or section == "nodes2":
            declared += 1
            continue
        if not RAYS_FIELD.has(section) and section != "cinecam":
            continue
        var fields: PackedStringArray = RorText.fields(line)
        var kept: Array = rows.get(section, []) as Array
        kept.append(fields)
        rows[section] = kept
    var before_wheels: int = declared + (rows.get("cinecam", []) as Array).size()
    var total: int = before_wheels
    for kind: String in GENERATING_ORDER:
        if kind == "cinecam":
            continue
        for fields: PackedStringArray in rows.get(kind, []) as Array:
            var at: int = int(RAYS_FIELD[kind])
            if fields.size() > at:
                total += fields[at].to_int() * int(NODES_PER_RAY[kind])
    return {"declared": declared, "before_wheels": before_wheels, "total": total}
