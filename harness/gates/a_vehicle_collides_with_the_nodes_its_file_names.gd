extends GateBase
## The nodes of a vehicle that can hit another vehicle are the ones upstream's rule picks from the
## vehicle's own file.
##
## `RorWorld` tests each actor's collision triangles against the other actor's contactable nodes,
## and which nodes those are is upstream's `UpdateCollcabContacterNodes`: every node a `contacters`
## row names, every node of a collision triangle (`cab` options c, p, u, D, F, S), every rim node of
## a `flexbodywheels` row, and every node at all of a vehicle with no collision triangles. Before
## this the `contacters` section was not read and rims were not marked, so a hero contacter that is
## on no triangle — 7 of its 79 — passed into the other truck, and so did a Mazda's rims.
##
## The oracle is the rule applied to the parsed file here, independently of the solver's own
## bookkeeping, on two vehicles that exercise different halves of it: the hero (contacters, no
## rims) and the Mazda 626 (flexbody wheels). **The control is in the same run**: each vehicle built
## again with its contacters and rims dropped, which has to lose exactly the nodes only they named.

const VEHICLES: Array[Dictionary] = [
    {"dir": "assets/mods/ChevyS1023", "file": "S10offroad.truck"},
    {"dir": "assets/mods/mazda626gf", "file": "mazda626sd18i-mt.car"},
]


static func meta() -> Dictionary:
    return {
        "name": "a_vehicle_collides_with_the_nodes_its_file_names",
        "proves": "the solver's contactable nodes are exactly upstream's rule applied to the file — contacters, collision-triangle nodes and flexbody rims — on a vehicle with contacters and one with flexbody wheels, and dropping the contacters and rims loses exactly the nodes only they named",
        "builds_on": ["two_vehicles_collide", "truck_parse"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "contactable count equal to the rule's count from the parsed file, with and without contacters and rims",
        "why": (
            "a node the file names as a contacter, or a flexbody wheel's rim, has to hit another"
            + " vehicle; the section was unread and the rims unmarked, so both passed through."
        ),
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var reports: PackedStringArray = PackedStringArray()
    for entry: Dictionary in VEHICLES:
        var mod_dir: String = SourceScan.repo_root().path_join(entry["dir"] as String)
        if not DirAccess.dir_exists_absolute(mod_dir):
            continue
        var file: String = entry["file"] as String
        var full: Dictionary = _count(mod_dir, file, true)
        var bare: Dictionary = _count(mod_dir, file, false)
        for case: Dictionary in [full, bare]:
            if (case["error"] as String) != "":
                return fail("%s: %s" % [file, case["error"]])
            if (case["solver"] as int) != (case["rule"] as int):
                return fail(
                    "%s %s: the solver counts %d contactable nodes, the rule %d"
                    % [file, case["label"], case["solver"], case["rule"]],
                    case["solver"]
                )
        if (full["named"] as int) > 0 and (full["solver"] as int) == (bare["solver"] as int):
            return fail("%s names %d contacters and rims and dropping them changed nothing" % [
                file, full["named"]])
        reports.append("%s %d contactable (%d contacters, %d rim nodes; %d without them)" % [
            file, full["solver"], full["contacters"], full["rims"], bare["solver"]])
    if reports.is_empty():
        return ok("skipped: none of the gate's vehicles are in this checkout", 0)
    return ok("; ".join(reports), reports.size())


## Builds the vehicle, with or without its contacters and rims, and counts its contactable nodes
## two ways: the solver's, and upstream's rule over the parsed file.
func _count(mod_dir: String, file: String, with_roles: bool) -> Dictionary:
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_file(mod_dir.path_join(file))
    if error != "":
        return {"error": error}
    # Rims are generated with the wheels while the file is parsed, so both lists are complete here.
    var contacters: int = truck.contacters.size()
    var rims: int = truck.rim_nodes.size()
    if not with_roles:
        truck.contacters = PackedInt32Array()
        truck.rim_nodes = PackedInt32Array()
    var built: Dictionary = RigBuilder.build(truck, 0.0)
    if (built["error"] as String) != "":
        return {"error": built["error"]}
    var solver: RefCounted = built["solver"] as RefCounted
    var picked: Dictionary = {}
    var triangles: PackedInt32Array = truck.submeshes.cab_triangles
    var options: PackedStringArray = truck.submeshes.cab_options
    var has_triangles: bool = false
    for index: int in options.size():
        for letter: String in RigBuilder.COLLISION_CAB_OPTIONS:
            if options[index].contains(letter):
                has_triangles = true
                for corner: int in 3:
                    picked[triangles[index * 3 + corner]] = true
                break
    if with_roles:
        for node: int in truck.contacters:
            picked[node] = true
        for node: int in truck.rim_nodes:
            picked[node] = true
    var rule: int = picked.size() if has_triangles else solver.node_count()
    return {
        "error": "", "label": "with its contacters and rims" if with_roles else "without them",
        "solver": solver.contactable_count(), "rule": rule, "contacters": contacters,
        "rims": rims, "named": contacters + rims,
    }
