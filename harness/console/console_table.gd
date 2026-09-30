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

var _commands: Dictionary = {}
var _harness: Node = null


func _init(harness: Node) -> void:
    _harness = harness
    _register(ConsoleCommand.make(
        "help", "help [command]", "list the commands, or explain one", 0, _cmd_help, _complete_command
    ))
    _register(ConsoleCommand.make(
        "gate list", "gate list [prefix]", "the gates this build has", 0, _cmd_gate_list
    ))
    _register(ConsoleCommand.make(
        "gate run", "gate run <name> [name...]",
        "run gates, each in its own container, in this window", 1, _cmd_gate_run, _complete_gate
    ))
    _register(ConsoleCommand.make(
        "gate meta", "gate meta <name>", "what a gate claims, and how it is bounded", 1,
        _cmd_gate_meta, _complete_gate
    ))
    _register(ConsoleCommand.make(
        "map list", "map list", "the terrains this checkout holds, and what each says of itself",
        0, _cmd_map_list
    ))
    _register(ConsoleCommand.make(
        "cvar list", "cvar list [prefix]", "the tunables, by config and name", 0, _cmd_cvar_list
    ))
    _register(ConsoleCommand.make(
        "cvar get", "cvar get <name>", "one tunable's value", 1, _cmd_cvar_get, _complete_cvar
    ))
    _register(ConsoleCommand.make(
        "echo", "echo <text>", "say something back; proves a front end reaches the table", 1,
        _cmd_echo
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


func _cmd_gate_list(args: PackedStringArray, _harness_node: Node) -> Dictionary:
    var prefix: String = args[0] if args.size() > 0 else ""
    var found: PackedStringArray = _gate_names(prefix)
    return ConsoleResult.ok("%d gates: %s" % [found.size(), " ".join(found)])


## Runs gates here and now, in this window, each in its own container — the same `GateRunner`
## the command line uses, so a gate run from the console is the same run in every respect.
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
    var outcome: Dictionary = await runner.run(harness_node, args)
    var failed: int = int(outcome["failed"])
    var detail: String = "%d gate(s) run, %d failed" % [args.size(), failed]
    if failed == 0:
        return ConsoleResult.ok(detail, {"gates": args.size(), "failed": 0})
    return ConsoleResult.err(detail)


func _cmd_gate_meta(args: PackedStringArray, _harness_node: Node) -> Dictionary:
    var path: String = "res://harness/gates/%s.gd" % args[0]
    if not ResourceLoader.exists(path):
        return ConsoleResult.err("no gate '%s'" % args[0])
    var script: GDScript = load(path) as GDScript
    if script == null or not script.can_instantiate():
        return ConsoleResult.err("gate '%s' does not compile" % args[0])
    var meta: Dictionary = script.call("meta") as Dictionary
    return ConsoleResult.ok(
        "%s [%s, %s, %.0fs] %s" % [
            meta.get("name", args[0]), meta.get("milestone", "?"), meta.get("oracle", "?"),
            float(meta.get("budget_s", 0.0)), meta.get("proves", "")
        ],
        {"threshold": meta.get("threshold", "")}
    )


func _cmd_map_list(_args: PackedStringArray, _harness_node: Node) -> Dictionary:
    var summaries: Array[Dictionary] = RorTerrainLibrary.summaries()
    if summaries.is_empty():
        return ConsoleResult.err(
            "no terrains. The shipped map comes from the vendor submodules:"
            + " git submodule update --init --recursive"
        )
    var lines: PackedStringArray = PackedStringArray()
    for summary: Dictionary in summaries:
        if (summary["error"] as String) != "":
            lines.append("%s (%s)" % [summary["name"], summary["error"]])
            continue
        lines.append("%s '%s' %.0fm" % [
            summary["name"], summary["title"], summary["size_m"] as float
        ])
    return ConsoleResult.ok("%d terrains: %s" % [summaries.size(), "; ".join(lines)])


## --------------------------------------------------------------------------------
## Tunables
##
## Read-only, and that is a scope line rather than an oversight. A tunable is a `const` in
## `game/config/*.gd`, and a GDScript const cannot be written at run time, so making these
## settable means turning the config into a settings object that persists — which is C1's
## settings work and not something to do halfway here. Reading them is useful now: `cvar get`
## answers "what is the renderer actually using" without a source dive.


func _cmd_cvar_list(args: PackedStringArray, _harness_node: Node) -> Dictionary:
    var prefix: String = args[0] if args.size() > 0 else ""
    var found: PackedStringArray = _cvar_names(prefix)
    return ConsoleResult.ok("%d tunables: %s" % [found.size(), " ".join(found)])


func _cmd_cvar_get(args: PackedStringArray, _harness_node: Node) -> Dictionary:
    var wanted: String = args[0]
    var parts: PackedStringArray = wanted.split(".", false)
    if parts.size() != 2:
        return ConsoleResult.err("a tunable is named <config>.<CONST>, as `cvar list` prints it")
    var script: GDScript = _config_script(parts[0])
    if script == null:
        return ConsoleResult.err("no config '%s'" % parts[0])
    var constants: Dictionary = script.get_script_constant_map()
    if not constants.has(parts[1]):
        return ConsoleResult.err("%s has no '%s'" % [parts[0], parts[1]])
    return ConsoleResult.ok(
        "%s = %s (read-only until C1's settings work)" % [wanted, constants[parts[1]]],
        {"value": str(constants[parts[1]])}
    )


## --------------------------------------------------------------------------------
## Completion sources


func _complete_command(prefix: String, _harness_node: Node) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    for name: String in names():
        if name.begins_with(prefix):
            out.append(name)
    return out


func _complete_gate(prefix: String, _harness_node: Node) -> PackedStringArray:
    return _gate_names(prefix)


func _complete_cvar(prefix: String, _harness_node: Node) -> PackedStringArray:
    return _cvar_names(prefix)


func _gate_names(prefix: String) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    var dir: DirAccess = DirAccess.open("res://harness/gates")
    if dir == null:
        return out
    for file: String in dir.get_files():
        if file.get_extension() != "gd":
            continue
        var name: String = file.get_basename()
        if prefix.is_empty() or name.begins_with(prefix):
            out.append(name)
    out.sort()
    return out


func _cvar_names(prefix: String) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    var dir: DirAccess = DirAccess.open("res://game/config")
    if dir == null:
        return out
    for file: String in dir.get_files():
        if file.get_extension() != "gd":
            continue
        var config: String = file.get_basename()
        var script: GDScript = _config_script(config)
        if script == null:
            continue
        for key: String in script.get_script_constant_map().keys():
            var name: String = "%s.%s" % [config, key]
            if prefix.is_empty() or name.begins_with(prefix):
                out.append(name)
    out.sort()
    return out


func _config_script(config: String) -> GDScript:
    var path: String = "res://game/config/%s.gd" % config
    if not ResourceLoader.exists(path):
        return null
    return load(path) as GDScript


func _cmd_echo(args: PackedStringArray, _harness_node: Node) -> Dictionary:
    return ConsoleResult.ok(" ".join(args))
