extends GateBase
## Every front end of the console reaches the same command table, and gets the same answer.
##
## Three of them: the table called directly, the agent's watched drop box, and the keyboard's
## drop-down console. The third is driven through its own submit path — the one a keystroke
## reaches — rather than by calling the table it sits on, for the same reason as the second: the
## part that can drift is the part in between.
##
## PLAN 0.8 says the keyboard, the agent's watched drop box and `tools/gate.sh` all dispatch into
## one command table, so that anything the user can type the agent can run and neither has a
## capability the other lacks. That is a claim about wiring, and wiring claims rot silently: a
## second front end grows a convenience its own way, and six months later the agent cannot
## reproduce what the user is seeing because it is running different code.
##
## So this drives the same commands through both front ends and compares. The agent's front end
## is exercised as the agent actually uses it — a file written into the drop box, a line read back
## out of the JSONL — rather than by calling the dispatcher it happens to sit on, because the
## thing that can drift is the part in between.
##
## It also holds the token-efficiency contract, which is not a nicety: **one command must cost
## the agent one line**. A front end that answers a question with a frame, a log or a stack is a
## front end the agent cannot afford to use, and that is a property worth a number rather than an
## intention.

## Commands run through both front ends. Chosen to cover a result, an error, and a result
## carrying structured data, since those are the three shapes a line can take.
const COMMANDS: Array[String] = [
    "echo hello",
    "gate list console",
    "map list",
    "cvar get render_cfg.EXPOSURE",
    "gate meta smoke",
    "nonsense command",
]
## The drop box writes and the channel polls, so a reply is not instant. Generous: what is being
## checked is that it arrives and matches, not how fast.
const REPLY_TIMEOUT_S: float = 10.0
## What one command may cost the agent to read back. A JSONL line carrying a one-sentence detail
## and a small result sits far under this; a line carrying a log or a frame cannot.
const MAX_LINE_BYTES: int = 2048
## How many front ends must reach the table: called directly, the agent's drop box, the console.
const FRONT_ENDS: int = 3


static func meta() -> Dictionary:
    return {
        "name": "console_fronts_agree",
        "proves": "the keyboard's console, the agent's channel and a direct call all dispatch into one command table and return the same result, and one command costs the agent one line",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "%d commands, identical ok and detail through both front ends, each reply one JSONL"
            % COMMANDS.size() + " line of at most %d bytes" % MAX_LINE_BYTES
        ),
        "why": (
            "one command table is what stops the agent and the user having different"
            + " capabilities, and it is a wiring claim, which rots without being noticed: a"
            + " second front end grows a convenience its own way and the agent can no longer"
            + " reproduce what the user sees. The line budget is the other half — a front end"
            + " that answers with a log is one the agent cannot afford to use."
        ),
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "D0",
    }


func run(harness: Node) -> Dictionary:
    var table: ConsoleTable = ConsoleTable.new(harness)

    # Front end one: straight into the table, which is what the keyboard does.
    var typed: Array[Dictionary] = []
    for command: String in COMMANDS:
        typed.append(await table.dispatch(command))

    # Front end two: the drop box, exercised the way the agent uses it.
    var channel: AgentChannel = AgentChannel.new()
    channel.setup(harness, table)
    harness.add_child(channel)
    var out_path: String = HarnessCapture.resolve_dir("").path_join(AgentChannel.OUT_FILE)
    var before: int = _line_count(out_path)
    var dropped: String = HarnessCapture.resolve_dir(AgentChannel.IN_DIR).path_join("0001.cmd")
    var handle: FileAccess = FileAccess.open(dropped, FileAccess.WRITE)
    if handle == null:
        channel.queue_free()
        return fail("the agent's drop box could not be written at %s" % dropped)
    handle.store_string("\n".join(COMMANDS))
    handle.close()

    # Plain frames, not `advance_frames`: this gate builds no world, and the harness's frame
    # pump samples metrics that only exist once one has been set up. The channel polls on
    # `_process`, so frames are all it needs.
    var waited: float = 0.0
    while _line_count(out_path) < before + COMMANDS.size() and waited < REPLY_TIMEOUT_S:
        await harness.get_tree().process_frame
        waited += 1.0 / 60.0
    channel.queue_free()

    var lines: PackedStringArray = _lines(out_path).slice(before)
    if lines.size() != COMMANDS.size():
        return fail(
            "the drop box answered %d of %d commands in %.1f s: the agent's front end is not"
            % [lines.size(), COMMANDS.size(), waited] + " reaching the table",
            lines.size()
        )

    # Front end three: the keyboard's console, through the submit path a keystroke reaches.
    var ui: ConsoleUi = ConsoleUi.new()
    harness.add_child(ui)
    ui.setup(table)
    for command: String in COMMANDS:
        await ui.submit(command)
    var typed_lines: PackedStringArray = table.transcript()
    ui.queue_free()
    # The console dispatched into the same table, so the table's own transcript has to show each
    # command three times: once per front end. A console that had grown its own dispatcher would
    # leave a third of them missing.
    for command: String in COMMANDS:
        var seen: int = 0
        for line: String in typed_lines:
            if line == command:
                seen += 1
        if seen != FRONT_ENDS:
            return fail(
                "'%s' reached the table %d times for %d front ends: one of them is not"
                % [command, seen, FRONT_ENDS] + " dispatching into it",
                seen
            )

    var widest: int = 0
    for index: int in COMMANDS.size():
        var line: String = lines[index]
        widest = maxi(widest, line.to_utf8_buffer().size())
        var parsed: Variant = JSON.parse_string(line)
        if parsed == null or not (parsed is Dictionary):
            return fail("the channel wrote a line that is not JSON: %s" % line.substr(0, 120))
        var row: Dictionary = parsed as Dictionary
        var expected: Dictionary = typed[index]
        if (row.get("cmd", "") as String) != COMMANDS[index]:
            return fail(
                "line %d answers '%s' where the command was '%s': the channel is not replying in"
                % [index + 1, row.get("cmd", ""), COMMANDS[index]] + " order"
            )
        if bool(row.get("ok", false)) != bool(expected.get("ok", false)):
            return fail(
                "'%s' is %s typed and %s through the channel: the two front ends are not running"
                % [COMMANDS[index], expected.get("ok"), row.get("ok")] + " the same command"
            )
        if (row.get("detail", "") as String) != (expected.get("detail", "") as String):
            return fail(
                "'%s' answers differently through the two front ends: typed '%s', channel '%s'"
                % [COMMANDS[index], expected.get("detail", ""), row.get("detail", "")]
            )
    if widest > MAX_LINE_BYTES:
        return fail(
            "the widest reply is %d bytes, over %d: a command has to cost the agent one line"
            % [widest, MAX_LINE_BYTES],
            widest
        )
    return ok(
        "%d commands identical through %d front ends; widest reply %d bytes of %d"
        % [COMMANDS.size(), FRONT_ENDS, widest, MAX_LINE_BYTES],
        widest
    )


func _lines(path: String) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    if not FileAccess.file_exists(path):
        return out
    for line: String in FileAccess.get_file_as_string(path).split("\n"):
        if not line.strip_edges().is_empty():
            out.append(line)
    return out


func _line_count(path: String) -> int:
    return _lines(path).size()
