class_name TruckLinks
extends RefCounted
## What a vehicle file says about linking to other vehicles: its hooks (nodes with option `h`, and
## the `hooks` rows that set them up), its lock groups (`lockgroups`, and `lockgroup_default_nolock`)
## and its ties (`ties`, kept and not yet acted on).
##
## Upstream's `ParseHook`, `ParseLockgroups` and `ProcessNode`'s hook beam. A hook's beam takes the
## beam defaults in force at its node's row: their spring, a tenth of their damping, a hundred times
## their break figure, and their yield.

## {node, spring, damp, strength, deform} per hook node, in node order.
var hook_nodes: Array[Dictionary] = []
## {node, lockrange, speed_coef, maxforce, group, lockgroup, timer, min_length, selflock, autolock,
## nodisable, norope} per `hooks` row.
var hooks: Array[Dictionary] = []
## Node index -> lock group, from `lockgroups`.
var lockgroups: Dictionary = {}
## `lockgroup_default_nolock`: every node not in a lock group is closed to hooks.
var default_nolock: bool = false
## Every `ties` row: a rope anchored at one node whose other end is loose until a player hooks it
## onto something. See `BeamRows.tie`.
var ties: Array[Dictionary] = []


func add_hook_node(node: int, defaults: BeamDefaults) -> void:
    hook_nodes.append({
        "node": node, "spring": defaults.spring(), "damp": defaults.damp() * 0.1,
        "strength": defaults.breaking_strength() * 100.0, "deform": defaults.deform(),
    })


## One row of `section`; an error, or "".
func read(section: String, line: String, id_to_index: Dictionary) -> String:
    var fields: PackedStringArray = TruckLexer.fields(line)
    match section:
        "ties":
            var row: Dictionary = BeamRows.tie(fields, id_to_index)
            if (row["error"] as String) != "":
                return row["error"] as String
            row.erase("error")
            ties.append(row)
        "lockgroups":
            if fields.size() < 2:
                return "row names no node"
            for i: int in range(1, fields.size()):
                var node: int = int(id_to_index.get(fields[i], -1))
                if node < 0:
                    return "row references an unknown node %s" % fields[i]
                lockgroups[node] = fields[0].to_int()
        "hooks":
            return _hook(fields, id_to_index)
    return ""


## Upstream's `ParseHook`: the node, then options by name, a value after those that take one.
func _hook(fields: PackedStringArray, id_to_index: Dictionary) -> String:
    var node: int = int(id_to_index.get(fields[0], -1)) if not fields.is_empty() else -1
    if node < 0:
        return "row references an unknown node"
    var hook: Dictionary = {
        "node": node, "lockrange": 0.4, "speed_coef": 1.0, "maxforce": 10000000.0, "group": -1,
        "lockgroup": -1, "timer": 5.0, "min_length": 0.0, "selflock": false, "autolock": false,
        "nodisable": false, "norope": false,
    }
    var values: Dictionary = {
        "hookrange": "lockrange", "speedcoef": "speed_coef", "maxforce": "maxforce", "timer": "timer",
        "hookgroup": "group", "hgroup": "group", "lockgroup": "lockgroup", "lgroup": "lockgroup",
        "shortlimit": "min_length", "short_limit": "min_length",
    }
    var flags: Dictionary = {
        "selflock": "selflock", "self-lock": "selflock", "self_lock": "selflock",
        "autolock": "autolock", "auto-lock": "autolock", "auto_lock": "autolock",
        "nodisable": "nodisable", "no-disable": "nodisable", "no_disable": "nodisable",
        "norope": "norope", "no-rope": "norope", "no_rope": "norope",
    }
    var i: int = 1
    while i < fields.size():
        var attr: String = fields[i].strip_edges()
        if values.has(attr) and i < fields.size() - 1:
            i += 1
            var key: String = values[attr]
            hook[key] = fields[i].to_int() if key == "group" or key == "lockgroup" else fields[i].to_float()
        elif flags.has(attr):
            hook[flags[attr]] = true
        i += 1
    hooks.append(hook)
    return ""
