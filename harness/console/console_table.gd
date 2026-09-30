class_name ConsoleTable
extends RefCounted
## Every command the console can run, and the one place that runs them.
##
## PLAN 0.8: the keyboard, the agent's watched drop box and `tools/gate.sh` all dispatch here, so
## anything the user can type the agent can run and neither has a capability the other lacks.
## `console_fronts_agree` is the gate that holds it.
##
## Commands are grouped by their first word — `gate run`, `map list` — because that is how a
## person remembers them and how completion can be useful without knowing anything about the
## command it is completing.

## Emitted while a long command runs, for a front end that wants to show it happening.
##
## The console prints these as they arrive; the agent's channel ignores them and still gets one
## line per command. Progress a person wants to watch and progress an agent has to pay for are
## different things, and this is the seam between them.
signal progress(text: String, ok: bool)

var _commands: Dictionary = {}
var _harness: Node = null
## `alias -> the line it expands to`. Held here rather than in the console UI, because an alias
## a person defines is a command the agent can run too — one table means one set of commands,
## and an alias only the keyboard knew about would be the first crack in that.
var _aliases: Dictionary = {}
## Every line dispatched, in order, whichever front end sent it. `condump` writes it out, which
## is what a person hands over when reporting what they did.
var _transcript: PackedStringArray = PackedStringArray()
## The commands that only read the project — gates, maps, tunables. Split out when this file
## went over the source cap, and it is a real seam: none of them touches the table's own state,
## so none of them needed to be here.
var _queries: ConsoleQueries = ConsoleQueries.new()


func _init(harness: Node) -> void:
    _harness = harness
    _register(ConsoleCommand.make(
        "help", "help [command]", "list the commands, or explain one", 0, _cmd_help, _complete_command
    ))
    _register(ConsoleCommand.make(
        "gate list", "gate list [prefix]", "the gates this build has", 0, _queries._cmd_gate_list
    ))
    _register(ConsoleCommand.make(
        "gate run", "gate run <name> [name...]",
        "run gates, each in its own container, in this window", 1, _cmd_gate_run, _queries._complete_gate
    ))
    _register(ConsoleCommand.make(
        "gate meta", "gate meta <name>", "what a gate claims, and how it is bounded", 1,
        _queries._cmd_gate_meta, _queries._complete_gate
    ))
    _register(ConsoleCommand.make(
        "map list", "map list", "the terrains this checkout holds, and what each says of itself",
        0, _queries._cmd_map_list
    ))
    _register(ConsoleCommand.make(
        "cvar list", "cvar list [prefix]", "the tunables, by config and name", 0, _queries._cmd_cvar_list
    ))
    _register(ConsoleCommand.make(
        "cvar get", "cvar get <name>", "one tunable's value", 1, _queries._cmd_cvar_get, _queries._complete_cvar
    ))
    _register(ConsoleCommand.make(
        "echo", "echo <text>", "say something back; proves a front end reaches the table", 1,
        _cmd_echo
    ))
    _register(ConsoleCommand.make(
        "alias", "alias [name] [line...]",
        "name a line, or list the names; an alias is a command every front end has", 0,
        _cmd_alias, _complete_alias
    ))
    _register(ConsoleCommand.make(
        "unalias", "unalias <name>", "forget an alias", 1, _cmd_unalias, _complete_alias
    ))
    _register(ConsoleCommand.make(
        "quit", "quit", "close this session", 0, _cmd_quit
    ))
    _register(ConsoleCommand.make(
        "condump", "condump [name]", "write everything dispatched so far to a file", 0,
        _cmd_condump
    ))


func _register(command: ConsoleCommand) -> void:
    _commands[command.name] = command


## Every command name, sorted. The completion source for the first word, and what `help` lists.
func names() -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    for key: String in _commands.keys():
        out.append(key)
    out.sort()
    return out


## Runs one command line and returns a `ConsoleResult`. Never throws: a bad line is a result
## that says so, because a front end that has to handle two failure shapes will handle one badly.
##
## Awaited, because some commands take frames — `gate run` renders. A handler that returns a
## value rather than a coroutine passes straight through the `await`, so a command does not have
## to be asynchronous to live here.
func dispatch(line: String) -> Dictionary:
    var text: String = line.strip_edges()
    if text.is_empty():
        return ConsoleResult.err("no command")
    if text.begins_with("//") or text.begins_with("#"):
        return ConsoleResult.ok("comment")
    _transcript.append(text)
    text = _expand_alias(text)
    var words: PackedStringArray = _words(text)
    var found: ConsoleCommand = _match(words)
    if found == null:
        return ConsoleResult.err(
            "unknown command '%s'. `help` lists them." % _longest_prefix(words)
        )
    var depth: int = found.name.split(" ").size()
    var args: PackedStringArray = words.slice(depth)
    if args.size() < found.min_args:
        return ConsoleResult.err("usage: %s" % found.usage)
    return await found.run.call(args, _harness) as Dictionary


## Completions for a partly-typed line: the command names that extend it, or the command's own
## argument completions once its name is complete.
func complete(line: String) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    var text: String = line.lstrip(" ")
    var words: PackedStringArray = _words(text)
    var typing_new_word: bool = text.is_empty() or text.ends_with(" ")
    var found: ConsoleCommand = _match(words)
    if found != null and (typing_new_word or words.size() > found.name.split(" ").size()):
        if not found.complete.is_valid():
            return out
        var prefix: String = "" if typing_new_word else words[words.size() - 1]
        return found.complete.call(prefix, _harness) as PackedStringArray
    for name: String in names():
        if name.begins_with(text):
            out.append(name)
    return out


## The longest registered command name the words begin with, or null.
##
## Longest wins, so `gate run` is not shadowed by a `gate` that happens to exist: a two-word
## command and a one-word command sharing a first word is the normal case, not an edge one.
func _match(words: PackedStringArray) -> ConsoleCommand:
    for depth: int in range(mini(words.size(), MAX_NAME_WORDS), 0, -1):
        var candidate: String = " ".join(words.slice(0, depth))
        if _commands.has(candidate):
            return _commands[candidate] as ConsoleCommand
    return null


const MAX_NAME_WORDS: int = 2


func _longest_prefix(words: PackedStringArray) -> String:
    return words[0] if words.size() > 0 else ""


## Splits a line into words, keeping a quoted run together so a path with a space in it is one
## argument.
func _words(line: String) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    var current: String = ""
    var quoted: bool = false
    for i: int in line.length():
        var character: String = line[i]
        if character == "\"":
            quoted = not quoted
            continue
        if character == " " and not quoted:
            if current != "":
                out.append(current)
                current = ""
            continue
        current += character
    if current != "":
        out.append(current)
    return out


## --------------------------------------------------------------------------------
## The commands


func _cmd_help(args: PackedStringArray, _harness_node: Node) -> Dictionary:
    if args.size() > 0:
        var wanted: ConsoleCommand = _match(args)
        if wanted == null:
            return ConsoleResult.err("no command '%s'" % " ".join(args))
        return ConsoleResult.ok("%s — %s" % [wanted.usage, wanted.help])
    var lines: PackedStringArray = PackedStringArray()
    for name: String in names():
        lines.append("%s — %s" % [(_commands[name] as ConsoleCommand).usage,
                                  (_commands[name] as ConsoleCommand).help])
    return ConsoleResult.ok("%d commands: %s" % [lines.size(), "; ".join(lines)])


func _cmd_gate_run(args: PackedStringArray, harness_node: Node) -> Dictionary:
    if harness_node == null:
        return ConsoleResult.err("gate run needs a harness; none is attached to this table")
    var unknown: PackedStringArray = PackedStringArray()
    for name: String in args:
        if not ResourceLoader.exists("res://harness/gates/%s.gd" % name):
            unknown.append(name)
    if unknown.size() > 0:
        return ConsoleResult.err("no such gate: %s" % " ".join(unknown))
    var runner: GateRunner = GateRunner.new()
    runner.gate_finished.connect(_on_gate_finished)
    var outcome: Dictionary = await runner.run(harness_node, args)
    var failed: int = int(outcome["failed"])
    var detail: String = "%d gate(s) run, %d failed" % [args.size(), failed]
    if failed == 0:
        return ConsoleResult.ok(detail, {"gates": args.size(), "failed": 0})
    return ConsoleResult.err(detail)


## --------------------------------------------------------------------------------
## Completion sources


func _complete_command(prefix: String, _harness_node: Node) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    for name: String in names():
        if name.begins_with(prefix):
            out.append(name)
    return out


func _cmd_echo(args: PackedStringArray, _harness_node: Node) -> Dictionary:
    return ConsoleResult.ok(" ".join(args))


## --------------------------------------------------------------------------------
## Aliases and the transcript


## A line with its first word replaced by the alias it names, once.
##
## Once, not repeatedly: an alias that expands to another alias is a loop waiting to be written,
## and a console that hangs on a typo is worse than one that makes you type the long form.
func _expand_alias(line: String) -> String:
    var words: PackedStringArray = _words(line)
    if words.is_empty() or not _aliases.has(words[0]):
        return line
    var rest: PackedStringArray = words.slice(1)
    var expanded: String = _aliases[words[0]] as String
    return expanded if rest.is_empty() else "%s %s" % [expanded, " ".join(rest)]


func _cmd_alias(args: PackedStringArray, _harness_node: Node) -> Dictionary:
    if args.is_empty():
        if _aliases.is_empty():
            return ConsoleResult.ok("no aliases")
        var listed: PackedStringArray = PackedStringArray()
        for key: String in _aliases.keys():
            listed.append("%s = %s" % [key, _aliases[key]])
        listed.sort()
        return ConsoleResult.ok("%d aliases: %s" % [listed.size(), "; ".join(listed)])
    var name: String = args[0]
    if args.size() == 1:
        if not _aliases.has(name):
            return ConsoleResult.err("no alias '%s'" % name)
        return ConsoleResult.ok("%s = %s" % [name, _aliases[name]])
    if _commands.has(name):
        return ConsoleResult.err(
            "'%s' is a command; an alias that shadowed one would make the same line mean two"
            % name + " things depending on who typed it"
        )
    _aliases[name] = " ".join(args.slice(1))
    return ConsoleResult.ok("%s = %s" % [name, _aliases[name]])


func _cmd_unalias(args: PackedStringArray, _harness_node: Node) -> Dictionary:
    if not _aliases.has(args[0]):
        return ConsoleResult.err("no alias '%s'" % args[0])
    _aliases.erase(args[0])
    return ConsoleResult.ok("forgot %s" % args[0])


func _complete_alias(prefix: String, _harness_node: Node) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    for key: String in _aliases.keys():
        if prefix.is_empty() or key.begins_with(prefix):
            out.append(key)
    out.sort()
    return out


## Writes the transcript to a file and answers with the path, not the contents — which is the
## whole point of it: a session's history is exactly the kind of thing that must not arrive in
## the agent's channel as a hundred lines.
func _cmd_condump(args: PackedStringArray, _harness_node: Node) -> Dictionary:
    var name: String = args[0] if args.size() > 0 else "condump"
    var path: String = HarnessCapture.resolve_dir("console").path_join("%s.txt" % name)
    DirAccess.make_dir_recursive_absolute(path.get_base_dir())
    var handle: FileAccess = FileAccess.open(path, FileAccess.WRITE)
    if handle == null:
        return ConsoleResult.err("cannot write %s" % path)
    for line: String in _transcript:
        handle.store_line(line)
    handle.close()
    return ConsoleResult.ok("%d lines written" % _transcript.size(), null, path)


## Every line dispatched so far, for a front end that wants to show its own history.
func transcript() -> PackedStringArray:
    return _transcript


## Ends the session. The agent's way out of a `--console` run, which otherwise holds the process
## open for as long as it is asked to.
func _cmd_quit(_args: PackedStringArray, harness_node: Node) -> Dictionary:
    if harness_node == null:
        return ConsoleResult.err("no harness to quit")
    harness_node.get_tree().quit(0)
    return ConsoleResult.ok("quitting")


## One line per gate as a suite runs, for whichever front end is watching.
##
## Shaped like the suite table a person already reads on the command line — name, verdict,
## elapsed, detail — so the console and `tools/gate.sh` do not present the same run two ways.
func _on_gate_finished(row: Dictionary) -> void:
    var passed: bool = row.get("pass", false) as bool
    var detail: String = row.get("detail", "") as String
    progress.emit(
        "  %-30s %-5s %6.2fs  %s" % [
            row.get("gate", "?"), "PASS" if passed else "FAIL",
            float(row.get("elapsed_s", 0.0)), detail
        ],
        passed
    )
