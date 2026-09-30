class_name AgentChannel
extends Node
## The agent's front end onto the console: a watched directory in, one JSONL line out.
##
## PLAN 0.8. The contract is a file drop rather than a socket because it needs no daemon, works
## whether or not a window is up, survives a restart of either side, and leaves a transcript.
## The socket is the fast path and is not the contract.
##
## ```
## artifacts/console/in/<seq>.cmd     the agent writes; one command per line, many lines allowed
## artifacts/console/out.jsonl        one line per command, appended
## artifacts/console/state.json       what is loaded right now, rewritten after each file
## ```
##
## **Every part of this is shaped by what a line costs the agent to read.** One line per command,
## carrying `seq` so the agent reads only what it asked for; a `detail` that is one sentence; and
## anything large written to a file with the *path* in the line. A script file is one round trip
## for a whole investigation rather than one per step, which is the difference between reading a
## conversation and reading an answer.
##
## It is not a security boundary. Anything that can write into the drop box can run any command
## the console has, which is the same authority a person at the keyboard has — that is the point
## of one command table, and it is why the drop box lives under `artifacts/` in the repository
## and not anywhere a stranger writes.

const IN_DIR: String = "console/in"
const OUT_FILE: String = "console/out.jsonl"
const STATE_FILE: String = "console/state.json"
## How often the drop box is looked at. A command is not latency-critical — the agent has just
## paid a round trip to write the file — and a poll per frame would cost a directory listing per
## frame for the life of a session.
const POLL_SECONDS: float = 0.25

var _table: ConsoleTable = null
var _harness: Node = null
var _seq: int = 0
var _since_poll: float = 0.0
var _busy: bool = false


func setup(harness: Node, table: ConsoleTable) -> void:
    _harness = harness
    _table = table
    DirAccess.make_dir_recursive_absolute(_in_dir())
    DirAccess.make_dir_recursive_absolute(HarnessCapture.resolve_dir("console"))


func _process(delta: float) -> void:
    _since_poll += delta
    if _since_poll < POLL_SECONDS or _busy:
        return
    _since_poll = 0.0
    var pending: PackedStringArray = _pending()
    if pending.is_empty():
        return
    _busy = true
    for file: String in pending:
        await _consume(file)
    _write_state()
    _busy = false


## The command files waiting, oldest first by name. Names are the agent's own sequence, so
## sorting by name is sorting by the order they were meant to run in.
func _pending() -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    var dir: DirAccess = DirAccess.open(_in_dir())
    if dir == null:
        return out
    for file: String in dir.get_files():
        if file.get_extension() == "cmd":
            out.append(file)
    out.sort()
    return out


## Runs one file's commands and appends one line per command. The file is removed first, so a
## command that crashes the engine is not run again on the next launch — a drop box that replays
## its own crash is a drop box nobody can recover.
func _consume(file: String) -> void:
    var path: String = _in_dir().path_join(file)
    var text: String = FileAccess.get_file_as_string(path)
    DirAccess.remove_absolute(path)
    for raw_line: String in text.split("\n"):
        var line: String = raw_line.strip_edges()
        if line.is_empty():
            continue
        _seq += 1
        var started: int = Time.get_ticks_usec()
        var result: Dictionary = await _table.dispatch(line)
        var elapsed_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
        _append(ConsoleResult.to_line(_seq, line, result, elapsed_ms))


func _append(line: String) -> void:
    var path: String = HarnessCapture.resolve_dir("").path_join(OUT_FILE)
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    var handle: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE)
    if handle == null:
        handle = FileAccess.open(path, FileAccess.WRITE)
    if handle == null:
        push_error("the agent channel cannot write %s" % path)
        return
    handle.seek_end()
    handle.store_line(line)
    handle.close()


## What is loaded right now, so the agent can orient without running a command to ask.
##
## Rewritten rather than appended: it is a snapshot and not a log, and a log of snapshots is a
## file the agent has to read to the end of to learn one fact.
func _write_state() -> void:
    var state: Dictionary = {
        "seq": _seq,
        "gate": _harness.container.name if _harness.container != null else "",
        "map": _loaded_map(),
        "weather": _harness.weather_name,
    }
    var path: String = HarnessCapture.resolve_dir("").path_join(STATE_FILE)
    var handle: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    if handle == null:
        return
    handle.store_string(JSON.stringify(state))
    handle.close()


func _loaded_map() -> String:
    if _harness.terrain == null:
        return ""
    var shape: Object = _harness.terrain.shape()
    return (shape.get("name") as String) if shape != null else ""


func _in_dir() -> String:
    return HarnessCapture.resolve_dir(IN_DIR)
