class_name ConsoleRuns
extends RefCounted
## The console commands that run things: one gate, the whole suite, a file of commands.
##
## The counterpart to `ConsoleQueries`, which answers questions. Split out of `ConsoleTable`
## when that went over the source cap, and the seam is the same one: the table owns dispatch,
## matching, completion and aliases, and these own the work.
##
## They need the table back, unlike the queries: `exec` dispatches lines through it, and both
## gate commands report progress on it so a person watching a suite sees it happen.

var _table: ConsoleTable = null


func setup(table: ConsoleTable) -> void:
    _table = table


func _cmd_gate_run(args: PackedStringArray, harness_node: Node) -> Dictionary:
    if harness_node == null:
        return ConsoleResult.err("gate run needs a harness; none is attached to this table")
    # Names are not pre-validated here. `GateRunner` reports a missing gate as that gate's own
    # result line, which is what a caller parsing the run needs: a batch that answered "no such
    # gate" for the whole list would leave every other gate in it unaccounted for.
    var runner: GateRunner = GateRunner.new()
    runner.gate_finished.connect(_on_gate_finished)
    var outcome: Dictionary = await runner.run(harness_node, args)
    # A gate that does not exist, or does not compile, stops the run and is not a failed gate --
    # so it arrives as `usage_error` with a `failed` count of zero. Reading only `failed` reports
    # a typo'd gate name as a clean run, which is the worst possible answer to give CI.
    if outcome["usage_error"] as bool:
        return ConsoleResult.err(
            "the run stopped: a named gate does not exist or does not compile (see above)"
        )
    var failed: int = int(outcome["failed"])
    var detail: String = "%d gate(s) run, %d failed" % [args.size(), failed]
    if failed == 0:
        return ConsoleResult.ok(detail, {"gates": args.size(), "failed": 0})
    return ConsoleResult.err(detail)


## --------------------------------------------------------------------------------
## Completion sources

## Runs the whole suite in this session: one window, however many gates.
##
## The scheduling used to live in `tools/gate.sh`, which launched an engine per tier because it
## needed each tier's results before deciding the next. That is arithmetic on a graph the engine
## already holds, so it is `GateSuite` now and a suite is one command in a window that stays
## open.
func _cmd_gate_all(args: PackedStringArray, harness_node: Node) -> Dictionary:
    if harness_node == null:
        return ConsoleResult.err("gate all needs a harness")
    var every: bool = args.size() > 0 and args[0] == "every"
    var suite: GateSuite = GateSuite.new()
    suite.gate_implied.connect(func(name: String, implier: String) -> void:
        # On stdout as well as to the console, because a shell reading the run needs to tell an
        # implied gate from one nobody scheduled.
        print("HARNESS_GATE_IMPLIED " + JSON.stringify({"gate": name, "by": implier}))
        _table.progress.emit(
            "  %-30s %-5s %6s  implied by %s, which passed" % [name, "IMPL", "-", implier],
            true
        )
    )
    var outcome: Dictionary = await suite.run(harness_node, every)
    if (outcome.get("error", "") as String) != "":
        return ConsoleResult.err(outcome["error"] as String)
    var ran: int = int(outcome["ran"])
    var failed: int = int(outcome["failed"])
    var implied: int = int(outcome["implied"])
    var detail: String = "%d gates run, %d implied, %d failed" % [ran, implied, failed]
    if failed > 0:
        return ConsoleResult.err(detail)
    return ConsoleResult.ok(detail, {"ran": ran, "implied": implied, "failed": 0})


## Runs a file of commands, one per line. One round trip for a whole investigation, which is
## what the agent's channel is shaped around and what the order check uses to put two suite runs
## in one session.
func _cmd_exec(args: PackedStringArray, _harness_node: Node) -> Dictionary:
    var path: String = args[0]
    if not FileAccess.file_exists(path):
        return ConsoleResult.err("no file at %s" % path)
    var lines: PackedStringArray = FileAccess.get_file_as_string(path).split("\n")
    var ran: int = 0
    var failed: int = 0
    for raw: String in lines:
        var line: String = raw.strip_edges()
        if line.is_empty() or line.begins_with("#"):
            continue
        ran += 1
        var result: Dictionary = await _table.dispatch(line)
        _table.progress.emit(
            "  %s %s" % ["ok " if result.get("ok", false) else "ERR", line], result.get("ok", false)
        )
        if not (result.get("ok", false) as bool):
            failed += 1
    var detail: String = "%d commands, %d failed" % [ran, failed]
    return ConsoleResult.ok(detail) if failed == 0 else ConsoleResult.err(detail)


## One line per gate as a suite runs, for whichever front end is watching.
##
## Shaped like the suite table a person already reads on the command line — name, verdict,
## elapsed, detail — so the console and `tools/gate.sh` do not present the same run two ways.
func _on_gate_finished(row: Dictionary) -> void:
    var passed: bool = row.get("pass", false) as bool
    var detail: String = row.get("detail", "") as String
    _table.progress.emit(
        "  %-30s %-5s %6.2fs  %s" % [
            row.get("gate", "?"), "PASS" if passed else "FAIL",
            float(row.get("elapsed_s", 0.0)), detail
        ],
        passed
    )
