class_name GateSuite
extends RefCounted
## Runs the whole suite in one session, scheduling from the gate graph.
##
## This was bash: `tools/gate.sh` walked the graph, decided what to run, and launched an engine
## per tier because it needed each tier's results before it could decide the next. Five windows
## for a run, and no way to keep one open and work in it.
##
## The scheduling is arithmetic on a graph the engine already holds, so it belongs here, and
## moving it means a suite is one command in a session that stays open. That one process can run
## the whole suite is not an assumption: `--order-check` has been running all of them twice in
## single windows since the containers landed.
##
## **A long-lived session is the development loop, not the release run.** Renderer state warms
## across a process — shader compilation, probe capture timing — and a rendered measurement
## moves in its fourth decimal because of it. For a release, start fresh. `run_release` exists
## to make the difference a thing a caller states rather than a thing they get by accident.

signal gate_finished(row: Dictionary)
signal gate_implied(name: String, implier: String)


## Runs the suite and returns {"ran", "failed", "implied", "results": {name: row}}.
##
## `every` ignores the graph and runs everything, which is what a release run uses: the edges
## are claims about claims and nothing can check them, so a run that trusts them is a run that
## believes a gate it did not perform.
func run(harness: Node, every: bool) -> Dictionary:
    var graph: Dictionary = GateChain.load_graph()
    var problems: PackedStringArray = GateChain.problems(graph)
    if problems.size() > 0:
        return {
            "ran": 0, "failed": 1, "implied": 0, "results": {},
            "error": "the gate graph is broken: %s" % ", ".join(problems),
        }
    var runner: GateRunner = GateRunner.new()
    runner.gate_finished.connect(func(row: Dictionary) -> void: gate_finished.emit(row))

    var implied_by: Dictionary = {}
    var results: Dictionary = {}
    var ran: int = 0
    var failed: int = 0
    var planned: PackedStringArray = GateChain.order(graph)
    # What this run intends to account for, said before it starts.
    #
    # **A suite that stops early used to read as a suite that passed.** The engine was killed
    # part way through a run — the machine was short of memory — and `tools/gate.sh` printed
    # "110 gates run in 1 window; all passed" for a suite of 125, because what it counts is the
    # result lines it was handed and there is no line for a gate that never ran. Fourteen gates
    # were simply absent and the run was green. The plan and the tally below are what let the
    # front end tell a finished run from a truncated one.
    print("HARNESS_SUITE_PLAN " + JSON.stringify({"gates": planned.size()}))
    for name: String in planned:
        if not every and implied_by.has(name):
            gate_implied.emit(name, implied_by[name] as String)
            results[name] = {"gate": name, "implied_by": implied_by[name]}
            continue
        # One gate at a time through the same runner every other caller uses, so a suite run and
        # a `gate run` of the same gate are the same run.
        var outcome: Dictionary = await runner.run(harness, PackedStringArray([name]))
        ran += 1
        var row: Dictionary = runner.last_row
        results[name] = row
        # The suite announces what *it* scheduled, under its own marker. A gate that runs gates
        # emits result lines of its own -- `console_fronts_agree` runs one deliberately named
        # `definitely_not_a_gate` -- and a reader that took every result line would report those
        # as part of the suite. They are not: they belong to the gate that ran them.
        print("HARNESS_SUITE_RESULT " + JSON.stringify(row))
        if (outcome["usage_error"] as bool) or int(outcome["failed"]) > 0:
            failed += 1
            continue
        if every:
            continue
        # A passing gate's claim contains the claims under it, so those are marked off rather
        # than re-proved. An implied gate is reported as implied and never as passed.
        for covered: String in GateChain.closure(graph, name):
            if not implied_by.has(covered):
                implied_by[covered] = name
    print("HARNESS_SUITE_DONE " + JSON.stringify({
        "ran": ran, "implied": implied_by.size(), "planned": planned.size(),
    }))
    return {"ran": ran, "failed": failed, "implied": implied_by.size(), "results": results}
