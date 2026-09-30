class_name ConsoleQueries
extends RefCounted
## The console commands that only read the project: what gates exist, what terrains exist, what
## the tunables are set to.
##
## Split out of `ConsoleTable` when that file went over the source cap, and it is a real seam
## rather than a slice taken to please the counter: none of these touches the table's own state
## — no aliases, no transcript, no command registry — so none of them needed to be there. The
## table keeps dispatch, matching, completion and aliases; this keeps the questions.
##
## **Tunables are read-only, and that is a scope line rather than an oversight.** A tunable is a
## `const` in `game/config/*.gd`, and a GDScript const cannot be written at run time, so making
## these settable means turning the config into a settings object that persists — which is C1's
## settings work and not something to do halfway here. Reading them is useful now: `cvar get`
## answers "what is the renderer actually using" without a source dive.

func _cmd_gate_list(args: PackedStringArray, _harness_node: Node) -> Dictionary:
    var prefix: String = args[0] if args.size() > 0 else ""
    var found: PackedStringArray = _gate_names(prefix)
    return ConsoleResult.ok("%d gates: %s" % [found.size(), " ".join(found)])


## Runs gates here and now, in this window, each in its own container — the same `GateRunner`
## the command line uses, so a gate run from the console is the same run in every respect.
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


## Completion sources, for the table to hand to the commands that take a gate or a tunable.
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


