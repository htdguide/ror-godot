class_name HarnessReport
extends RefCounted
## What the harness prints about itself: the gate graph, and what this build contains.
##
## Split out of `Harness` when that file went over the source cap. It is a real seam rather than a
## place to put spare lines: neither of these touches the harness's own state, both are pure
## reporting, and both are read by tools outside the engine — `tools/gate_plan.py` parses the
## chain and the runner schedules from it.


## The gate graph, for the runner to schedule from: which gates build on which, and what tier
## that puts each one in. Printed rather than computed in the runner because the edges are
## declared in the gates themselves and nothing outside the engine can read them.
static func print_chain() -> void:
    var graph: Dictionary = GateChain.load_graph()
    print("HARNESS_CHAIN " + JSON.stringify({
        "gates": graph,
        "order": GateChain.order(graph),
        "roots": GateChain.roots(graph),
        "problems": GateChain.problems(graph),
    }))


static func print_inventory(gate_dir: String) -> void:
    var gates: PackedStringArray = PackedStringArray()
    var dir: DirAccess = DirAccess.open(gate_dir)
    if dir != null:
        for file: String in dir.get_files():
            if file.ends_with(".gd"):
                gates.append(file.get_basename())
    print("HARNESS_INVENTORY " + JSON.stringify({
        "gates": gates,
        "presets": CameraCfg.names(),
        "scenarios": Scenarios.names(),
    }))
