class_name TruckLinks
extends RefCounted
## What a vehicle file says about linking to other vehicles: its hooks (nodes with option `h`, and
## the `hooks` rows that set them up), its lock groups (`lockgroups`, and `lockgroup_default_nolock`)
## its ties (`ties`), its ropes (`ropes`) and the ropables both take (`ropables`).
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
## Every `ties` row: a rope anchored at one node whose other end is loose until a player ties it to
## a ropable. See `BeamRows.tie`; each also carries the rope's beam defaults at its row (upstream's
## `ProcessTie`: their scaled spring, damping and break figure) and its detacher group.
var ties: Array[Dictionary] = []
## The beam index of each `ropes` row: the beam is built as any other, and is a rope besides.
var ropes: PackedInt32Array = PackedInt32Array()
## Every `triggers` row, upstream's `ParseTriggers`: {a, b, contraction, expansion, short, long,
## options, timer, detacher}; the solver builds the beam and its behaviour (`add_trigger`).
var triggers: Array[Dictionary] = []
## Every `animators` row (`AnimatorRows`), with the beam defaults, detacher group and inertia
## defaults in force at it, as `ProcessAnimator` reads them.
var animators: Array[Dictionary] = []
## {node, group, multilock} per `ropables` row, upstream's `ParseRopables`.
var ropables: Array[Dictionary] = []

## Upstream's lock group no hook may take (`LOCKGROUP_NOLOCK`).
const LOCKGROUP_NOLOCK: int = 9999


func add_hook_node(node: int, defaults: BeamDefaults) -> void:
    hook_nodes.append({
        "node": node, "spring": defaults.spring(), "damp": defaults.damp() * 0.1,
        "strength": defaults.breaking_strength() * 100.0, "deform": defaults.deform(),
    })


## Gives `solver` upstream's hooks, lock groups, ties, ropes and ropables from this file: each `h` node's rope beam, its
## `hooks` row, which nodes a hook may lock to, each tie's rope, each rope and each ropable.
func build(solver: RefCounted, node_count: int) -> void:
    for hook: Dictionary in hook_nodes:
        solver.add_hook(hook["node"], hook["spring"], hook["damp"], hook["strength"], hook["deform"])
    for row: Dictionary in hooks:
        solver.set_hook_options(row["node"], row["lockrange"], row["speed_coef"], row["maxforce"], row["group"],
                row["lockgroup"], row["timer"], row["min_length"], row["selflock"], row["autolock"],
                row["nodisable"], row["norope"])
    if default_nolock:
        for node: int in node_count:
            solver.set_node_lockgroup(node, LOCKGROUP_NOLOCK)
    for node: int in lockgroups:
        solver.set_node_lockgroup(node, lockgroups[node])
    for tie: Dictionary in ties:
        var beam: int = solver.beam_count()
        if solver.add_tie(tie["root"], tie["reach_m"], tie["rate"], tie["min_length"], tie["max_stress"], tie["group"],
                tie["no_self_lock"], tie["spring"], tie["damp"], tie["strength"], tie["deform"]) >= 0 and tie["detacher"] != 0:
            solver.set_beam_detacher_group(beam, tie["detacher"])
    for ropable: Dictionary in ropables:
        solver.add_ropable(ropable["node"], ropable["group"], ropable["multilock"])
    for beam: int in ropes:
        solver.add_rope(beam)
    for row: Dictionary in animators:
        var hydro: int = solver.add_animator(row["a"], row["b"], row["factor"], row["flags"], row["param"],
                row["short_limit"], row["long_limit"], row["spring"], row["damp"], row["strength"], row["detacher"])
        # Upstream gives an animator the inertia defaults in force, when both delays are set.
        var inertia: Dictionary = row["inertia"]
        if hydro >= 0 and float(inertia.get("start_delay", 0.0)) > 0.0 and float(inertia.get("stop_delay", 0.0)) > 0.0:
            solver.set_hydro_inertia(hydro, inertia["start_delay"], inertia["stop_delay"], inertia["start_function"],
                    inertia["stop_function"])
    # In file order, so a blocker's "the next n triggers" are the rows below it, as upstream's are.
    for t: Dictionary in triggers:
        solver.add_trigger(t["a"], t["b"], t["contraction"], t["expansion"], t["short"], t["long"], t["options"],
                t["timer"], t["detacher"])


## One row of `section`; an error, or "".
func read(section: String, line: String, id_to_index: Dictionary, defaults: BeamDefaults, detacher: int,
        inertia: Dictionary = {}) -> String:
    var fields: PackedStringArray = TruckLexer.fields(line)
    match section:
        "ties":
            var row: Dictionary = BeamRows.tie(fields, id_to_index)
            if (row["error"] as String) != "":
                return row["error"] as String
            row.erase("error")
            row.merge({
                "spring": defaults.spring(), "damp": defaults.damp(), "strength": defaults.breaking_strength(),
                "deform": defaults.deform(), "detacher": detacher,
                "no_self_lock": (row["options"] as String).contains("s"),
            })
            ties.append(row)
        "triggers":
            if fields.size() < 6:
                return "row has %d fields, expected at least 6" % fields.size()
            var a: int = int(id_to_index.get(fields[0], -1))
            var b: int = int(id_to_index.get(fields[1], -1))
            if a < 0 or b < 0:
                return "row references an unknown node"
            triggers.append({
                "a": a, "b": b, "contraction": fields[2].to_float(), "expansion": fields[3].to_float(),
                "short": fields[4].to_int(), "long": fields[5].to_int(),
                "options": fields[6] if fields.size() > 6 else "", "timer": fields[7].to_float() if fields.size() > 7 else 0.0,
                "detacher": detacher,
            })
        "animators":
            var row: Dictionary = AnimatorRows.read(line, id_to_index)
            if (row["error"] as String) != "":
                return row["error"] as String
            row.merge({"spring": defaults.spring(), "damp": defaults.damp(), "strength": defaults.breaking_strength(),
                    "detacher": detacher, "inertia": inertia})
            animators.append(row)
        "ropables":
            var node: int = int(id_to_index.get(fields[0], -1)) if not fields.is_empty() else -1
            if node < 0:
                return "row references an unknown node"
            ropables.append({
                "node": node, "group": fields[1].to_int() if fields.size() > 1 else -1,
                "multilock": fields.size() > 2 and fields[2].to_int() == 1,
            })
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
