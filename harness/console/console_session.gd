class_name ConsoleSession
extends RefCounted
## Wires the front ends onto one command table, and decides which of them a run gets.
##
## Small, and its own file because the decision in it is the load-bearing part of PLAN 0.8: one
## table, and every front end reaching it. A run that quietly built a second table, or attached
## a front end that bypassed the first, would satisfy every other check in this project.

## Opens the table, and the front ends this run should have. Returns
## {"table", "channel", "console"}; the last two are null for a run that gets neither.
##
## Not every run gets them. A gate run launched from the command line is over in seconds, and
## polling a drop box during it would let a stray file change what a gate measures — the front
## ends belong to a session that stays open. `--console` asks for them explicitly, and a window
## always has them.
static func open(harness: Node) -> Dictionary:
    var out: Dictionary = {"table": ConsoleTable.new(harness), "channel": null, "console": null}
    var args: HarnessArgs = harness.args
    if not (args.has_flag("play") or args.has_flag("console")):
        return out
    var table: ConsoleTable = out["table"] as ConsoleTable

    var channel: AgentChannel = AgentChannel.new()
    channel.name = "AgentChannel"
    channel.setup(harness, table)
    harness.add_child(channel)
    out["channel"] = channel

    var console: ConsoleUi = ConsoleUi.new()
    console.name = "Console"
    harness.add_child(console)
    console.setup(table)
    out["console"] = console

    print("HARNESS_CONSOLE " + JSON.stringify({
        "in": HarnessCapture.resolve_dir(AgentChannel.IN_DIR),
        "out": HarnessCapture.resolve_dir("").path_join(AgentChannel.OUT_FILE),
        "commands": table.names().size(),
    }))
    return out
