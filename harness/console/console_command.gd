class_name ConsoleCommand
extends RefCounted
## One command the console can run.
##
## A command is data: a name, what it takes, what it does, and where its completions come from.
## Nothing here knows whether it was typed by a person, read out of the agent's drop box, or
## passed in by `tools/gate.sh`, which is the point — PLAN 0.8 requires one command table so that
## neither the user nor the agent has a capability the other lacks. A command that only one front
## end can reach is the thing this design exists to make impossible.

## `run.call(args: PackedStringArray, harness: Node) -> Dictionary`, returning the result shape
## `ConsoleResult` describes.
var run: Callable = Callable()
## `complete.call(prefix: String, harness: Node) -> PackedStringArray`, for the argument after the
## command name. Empty when a command's arguments cannot be enumerated.
var complete: Callable = Callable()
var name: String = ""
var usage: String = ""
var help: String = ""
var min_args: int = 0


static func make(
    command_name: String, command_usage: String, command_help: String, min_arg_count: int,
    handler: Callable, completer: Callable = Callable()
) -> ConsoleCommand:
    var out: ConsoleCommand = ConsoleCommand.new()
    out.name = command_name
    out.usage = command_usage
    out.help = command_help
    out.min_args = min_arg_count
    out.run = handler
    out.complete = completer
    return out
