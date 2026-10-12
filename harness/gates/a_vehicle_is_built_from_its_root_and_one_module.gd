extends GateBase
## A file with modules (`section VERSION NAME` ... `end_section`) is built from its root and one
## module, the first by name when nobody chose, the way upstream builds it: `ConfigureSections` adds
## the chosen module to the root, the modules sit in a `std::map` sorted by name, and the game
## preselects "the first available one". Within a section the root's rows come before the module's,
## as the spawner walks its selected modules for each section in turn. A module named after the
## file (`<file>@<module>`, ours, for upstream's selector) is built in place of the first, and a
## name the file does not have is an error listing the ones it does.
##
## Ours read every module at once: the Star Monster declares six model years, each with its own
## wheels, and was built with all 24.
##
## The oracle is a file whose modules are declared out of name order and whose module block comes
## before the root's rows of the same section, and the Star Monster from the corpus, a monster truck
## with four wheels.

const STAR_MONSTER: String = "assets/corpus/1018_star-monster"
const TEXT: String = """modules
globals
1000, 0, tracks/semi
section 1 zz_unused
nodes
20, 9.0, 0.0, 0.0
end_section
section 1 aa_first
nodes
10, 5.0, 0.0, 0.0
end_section
nodes
0, 0.0, 0.0, 0.0
1, 1.0, 0.0, 0.0
end"""


static func meta() -> Dictionary:
    return {
        "name": "a_vehicle_is_built_from_its_root_and_one_module",
        "proves": "a vehicle is built from its root and the first module by name, the root's rows first in each section, as upstream's ConfigureSections and preselection do",
        "builds_on": ["every_keyword_is_read_where_upstream_reads_it"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "modules sorted, aa_first chosen, the root's nodes then its, zz_unused's absent; zz_unused chosen by name; an unknown name refused; Star Monster: 4 wheels, 1990 chosen by name",
        "why": "every module was read at once: the Star Monster was built with all six model years' wheels, 24 of them.",
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_text(TEXT)
    if error != "":
        return fail("the module file did not parse: %s" % error)
    # By position: the root's at x 0 and 1, aa_first's at 5, zz_unused's at 9.
    var order: Array = []
    for node: Vector3 in truck.nodes:
        order.append(node.x)
    if order != [0.0, 1.0, 5.0]:
        return fail("the nodes built sit at x %s, not the root's 0 and 1 then aa_first's 5" % [order])
    var report: String = "modules: nodes at x %s" % [order]
    var chosen: TruckParser = TruckParser.new()
    error = chosen.parse_text(TEXT, "zz_unused")
    order = []
    for node: Vector3 in chosen.nodes:
        order.append(node.x)
    if error != "" or order != [0.0, 1.0, 9.0] or chosen.selected_module != "zz_unused":
        return fail("zz_unused chosen by name built nodes at x %s (%s), not the root's then its 9" % [order, error])
    error = TruckParser.new().parse_text(TEXT, "no_such")
    if not error.contains("aa_first, zz_unused"):
        return fail("an unknown module name was not refused with the file's modules: '%s'" % error)
    report += "; zz_unused by name, an unknown name refused"
    var mod_dir: String = SourceScan.repo_root().path_join(STAR_MONSTER)
    if DirAccess.dir_exists_absolute(mod_dir):
        var monster: TruckParser = TruckParser.new()
        monster.parse_file(mod_dir.path_join("StarMonsterLF4.truck"))
        if monster.wheels.size() != 4:
            return fail("the Star Monster was built with %d wheels, not 4" % monster.wheels.size(), monster.wheels.size())
        var year: TruckParser = TruckParser.new()
        error = year.parse_file(mod_dir.path_join("StarMonsterLF4.truck@1990"))
        # The 1990 truck's front rims are StarRim; the first by name, 1988-Tarp's, IronEagleRim.
        var rim: String = year.wheels[0]["mesh"] if not year.wheels.is_empty() else ""
        if error != "" or year.wheels.size() != 4 or rim != "StarRim.mesh" or monster.wheels[0]["mesh"] != "IronEagleRim.mesh":
            return fail("the Star Monster's 1990 by name: %s, %d wheels, rims %s (the first module's %s)" % [error, year.wheels.size(), rim, monster.wheels[0]["mesh"]])
        report += "; Star Monster 4 wheels, 1990 by name"
    return ok(report, 0)
