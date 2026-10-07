extends GateBase
## Every generated wheel has the number of nodes and beams upstream says it should.
##
## **The oracle is upstream's own spawn budget**, which it computes before allocating anything —
## `ActorSpawner.cpp`, `CalcMemoryRequirements`:
##
##     wheels / meshwheels / meshwheels2:  num_rays * 2 nodes,  num_rays * 8 beams
##     wheels2:                            num_rays * 4 nodes,  num_rays * 24 beams
##                                         (rim 10, tyre 14 per ray)
##     flexbodywheels:                     num_rays * 4 nodes,  num_rays * 20 beams
##                                         (rim 8, tyre 10, support 2 per ray)
##     and one more beam per ray for any wheel whose row names a rigidity node
##
## Those numbers are not this project's opinion about what a wheel should be. They are the
## allocation upstream makes, in its own source, and a rig that disagrees with them is building a
## different object and calling it a wheel.
##
## **Why counting is worth a gate.** A flexbody wheel was built as a mesh wheel for as long as it
## was parsed at all: half the nodes, two fifths of the beams. Nothing errored. The vehicle had
## four wheels, they were in the right places, they had rims and tyres and textures — and they
## wobbled and would not stay on their suspension, which is a thing only a person driving it can
## see. A count catches it before anybody has to.
##
## It also fixes the shape of the structure rather than its stiffness. What a beam is *worth* is
## a separate question with its own evidence; how many there are is arithmetic, and arithmetic is
## what a gate is good at.

## Upstream's budget, by section. The rigidity beam is the one that is easy to leave out: it is
## virtual, so nothing draws it, and a wheel without it stands and rolls and folds the first time it
## is driven hard. See `WheelBeams.add_rigidity`.
const NODES_PER_RAY: Dictionary = {
    "wheels": 2, "meshwheels": 2, "meshwheels2": 2, "wheels2": 4, "flexbodywheels": 4}
const BEAMS_PER_RAY: Dictionary = {
    "wheels": 8, "meshwheels": 8, "meshwheels2": 8, "wheels2": 24, "flexbodywheels": 20}
const RIGIDITY_BEAMS_PER_RAY: int = 1
## Below this there is nothing to judge: a fresh clone has no downloaded packs.
const MIN_WHEELED_VEHICLES: int = 1


static func meta() -> Dictionary:
    return {
        "name": "a_wheel_rig_matches_upstreams_budget",
        "proves": "every generated wheel has exactly the nodes and beams upstream allocates for its kind",
        "builds_on": ["wheels_carry_the_vehicle"],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "per ray: wheels/meshwheels/meshwheels2 %d nodes and %d beams, wheels2 %d and %d,"
            % [NODES_PER_RAY["wheels"], BEAMS_PER_RAY["wheels"], NODES_PER_RAY["wheels2"],
               BEAMS_PER_RAY["wheels2"]]
            + " flexbodywheels %d and %d, plus %d beam where a rigidity node is named, exactly"
            % [NODES_PER_RAY["flexbodywheels"], BEAMS_PER_RAY["flexbodywheels"],
               RIGIDITY_BEAMS_PER_RAY]
        ),
        "why": (
            "a flexbody wheel built as a mesh wheel has half the nodes and two fifths of the"
            + " beams, and nothing errors: the vehicle has four wheels, in the right places,"
            + " with rims and tyres and textures, and they wobble. That is only visible to"
            + " somebody driving it, and it is arithmetic, which a gate can check first."
        ),
        "budget_s": 120.0,
        "needs_gpu": false,
        "milestone": "C1",
    }


func run(_harness: Node) -> Dictionary:
    var problems: PackedStringArray = PackedStringArray()
    var checked: int = 0
    var kinds: Dictionary = {}
    for entry: Dictionary in RorVehicleLibrary.entries():
        var truck: TruckParser = TruckParser.new()
        var path: String = (entry["directory"] as String).path_join(entry["file"] as String)
        if truck.parse_file(path) != "":
            continue
        if truck.wheels.is_empty():
            continue
        # What upstream would allocate for this vehicle's wheels, from its own figures.
        var wanted_nodes: int = 0
        var wanted_beams: int = 0
        for wheel: Dictionary in truck.wheels:
            var rays: int = wheel["rays"] as int
            var section: String = wheel["section"] as String
            var braced: bool = int(wheel.get("rigidity_node", -1)) >= 0
            kinds[section + (" (braced)" if braced else "")] = true
            wanted_nodes += rays * int(NODES_PER_RAY[section])
            wanted_beams += rays * (
                int(BEAMS_PER_RAY[section]) + (RIGIDITY_BEAMS_PER_RAY if braced else 0)
            )
        var made: Dictionary = WheelRig.generate(truck)
        checked += 1
        if (made["nodes"] as int) != wanted_nodes or (made["beams"] as int) != wanted_beams:
            problems.append(
                "%s: %d nodes and %d beams, upstream allocates %d and %d"
                % [entry["name"], made["nodes"], made["beams"], wanted_nodes, wanted_beams]
            )

    if checked < MIN_WHEELED_VEHICLES:
        return ok("skipped: no wheeled vehicles in this checkout", 0)
    if problems.size() > 0:
        return fail(
            "%d of %d wheeled vehicles build a wheel upstream would not recognise: %s"
            % [problems.size(), checked, "; ".join(problems)],
            problems.size()
        )
    return ok(
        "%d wheeled vehicles across %d wheel kinds (%s) match upstream's allocation exactly"
        % [checked, kinds.size(), ", ".join(PackedStringArray(kinds.keys()))],
        checked
    )
