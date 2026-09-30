extends GateBase
## Loads a real Rigs of Rods vehicle and checks the structure that everything downstream
## depends on: nodes resolve, beams and cab triangles reference real nodes, and the rig
## is the size a truck should be.
##
## The vehicle is the DAF semi from Rigs of Rods' own content pack, so the expected
## values come from upstream's published data rather than from anything written here.

const TRUCK_PATH: String = "vendor/rigs-of-rods/content/dafsemi/b6b0UID-semi.truck"
## A tractor unit is metres, not centimetres and not kilometres. This catches unit and
## parsing mistakes that would otherwise show up much later as a truck the size of a city.
const MIN_LENGTH_M: float = 3.0
const MAX_LENGTH_M: float = 25.0
const MIN_NODES: int = 20
const MIN_COVERAGE: float = 0.5


static func meta() -> Dictionary:
    return {
        "name": "truck_parse",
        "proves": "a real upstream vehicle parses into a consistent, correctly scaled node/beam rig",
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "every beam and cab index resolves; %d+ nodes; %.0f-%.0f m long; %.0f%% line coverage"
            % [MIN_NODES, MIN_LENGTH_M, MAX_LENGTH_M, MIN_COVERAGE * 100.0]
        ),
        "why": (
            "the vehicle ships with Rigs of Rods itself, so its contents are upstream's"
            + " data rather than an expectation written here. Index consistency and"
            + " physical scale are what every later stage assumes and nothing else checks."
        ),
        "budget_s": 20.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var path: String = SourceScan.repo_root().path_join(TRUCK_PATH)
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_file(path)
    if error != "":
        return fail(error)
    if truck.errors.size() > 0:
        return fail(
            "%d unresolved references, first: %s" % [truck.errors.size(), truck.errors[0]],
            truck.errors.size()
        )
    if truck.nodes.size() < MIN_NODES:
        return fail("only %d nodes parsed" % truck.nodes.size(), truck.nodes.size())

    var box: AABB = truck.bounds()
    var length: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
    if length < MIN_LENGTH_M or length > MAX_LENGTH_M:
        return fail(
            "rig is %.2f m on its longest axis, outside %.0f-%.0f m"
            % [length, MIN_LENGTH_M, MAX_LENGTH_M],
            length
        )
    var covered: float = truck.coverage()
    if covered < MIN_COVERAGE:
        return fail(
            "parsed only %.0f%% of content lines; unread sections: %s"
            % [covered * 100.0, _unread(truck)],
            covered
        )
    return ok(
        (
            "'%s': %d nodes, %d beams, %d cab triangles, %d submeshes, %.2f x %.2f x %.2f m,"
            + " %.0f%% of lines parsed"
        )
        % [
            truck.name, truck.nodes.size(), truck.beams.size() / 2,
            truck.cab_triangles.size() / 3, truck.submesh_count,
            box.size.x, box.size.y, box.size.z, covered * 100.0
        ],
        truck.nodes.size()
    )


func _unread(truck: TruckParser) -> String:
    var unread: PackedStringArray = PackedStringArray()
    for key: String in truck.sections_seen.keys():
        if int(truck.sections_parsed.get(key, 0)) == 0:
            unread.append("%s(%d)" % [key, int(truck.sections_seen[key])])
    unread.sort()
    return ", ".join(unread)
