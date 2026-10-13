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
## The aero engine rows (`turboprops2`, `pistonprops`, `turbojets`), kept for when they are built;
## a vehicle with any is an airplane, upstream's `ar_driveable`.
var aero_engines: Array[Dictionary] = []
## Every `wings` row (`WingRows`).
var wings: Array[Dictionary] = []
## Every `airbrakes` row, upstream's `ParseAirbrakes`: {nodes (ref, x, y, additional), offset,
## width, length, max_angle, tex (x1, y1, x2, y2)}.
var airbrakes: Array[Dictionary] = []
## The folder the file was read from, where its own airfoils are; "" for text.
var mod_dir: String = ""
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
    # The engines first: the wings' prop wash, worked out as the last wing closes, needs them.
    for row: Dictionary in aero_engines:
        _build_engine(solver, row)
    if not wings.is_empty():
        WingRows.build(solver, wings, mod_dir)
    for row: Dictionary in airbrakes:
        solver.add_airbrake(row["nodes"], row["width"], row["length"], row["max_angle"])
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


## Upstream's `ProcessTurboprop2`, `ProcessPistonprop` and `ProcessTurbojet`: a turboprop's pitch
## is upstream's variable -10, a piston prop's its own.
func _build_engine(solver: RefCounted, row: Dictionary) -> void:
    var f: PackedStringArray = row["fields"]
    match row["section"]:
        "turbojets":
            solver.add_turbojet(row["nodes"], f[3].to_int() != 0, f[4].to_float(), f[5].to_float(), f[7].to_float())
        "turboprops":
            solver.add_turboprop(row["nodes"], f[6].to_float(), WingRows.airfoil_text(f[7], mod_dir), false, -10.0)
        "turboprops2":
            solver.add_turboprop(row["nodes"], f[7].to_float(), WingRows.airfoil_text(f[8], mod_dir), false, -10.0)
        "pistonprops":
            solver.add_turboprop(row["nodes"], f[7].to_float(), WingRows.airfoil_text(f[9], mod_dir), true, f[8].to_float())


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
        "turboprops", "turboprops2", "pistonprops", "turbojets":
            var minimum: int = {"turboprops": 8, "turboprops2": 9, "pistonprops": 10, "turbojets": 9}[section]
            if fields.size() < minimum:
                return "row has %d fields, expected at least %d" % [fields.size(), minimum]
            var nodes: PackedInt32Array = PackedInt32Array()
            for i: int in (3 if section == "turbojets" else 7 if section != "turboprops" else 6):
                # Upstream's `GetArgNullableNode` for a third or fourth blade or a couple node: -1 is
                # no node. Any other negative number is its absolute value, as upstream's sequential
                # importer reads every numbered node reference.
                var nullable: bool = section != "turbojets" and i >= 4
                var id: String = fields[i]
                if nullable and id.to_float() == -1.0:
                    nodes.append(-1)
                    continue
                if id.begins_with("-") and id.substr(1).is_valid_int():
                    id = id.substr(1)
                var node: int = int(id_to_index.get(id, -1))
                if node < 0:
                    return "row references an unknown node"
                nodes.append(node)
            if section == "turboprops":
                nodes.append(-1)
            aero_engines.append({"section": section, "fields": fields, "nodes": nodes})
        "airbrakes":
            # Upstream needs all fourteen, and skips a shorter row.
            if fields.size() < 14:
                return "row has %d fields, expected 14" % fields.size()
            var nodes: PackedInt32Array = PackedInt32Array()
            for i: int in 4:
                nodes.append(int(id_to_index.get(fields[i], -1)))
                if nodes[i] < 0:
                    return "row references an unknown node"
            airbrakes.append({"nodes": nodes, "offset": Vector3(fields[4].to_float(), fields[5].to_float(), fields[6].to_float()),
                    "width": fields[7].to_float(), "length": fields[8].to_float(), "max_angle": fields[9].to_float(),
                    "tex": PackedFloat32Array([fields[10].to_float(), fields[11].to_float(), fields[12].to_float(), fields[13].to_float()])})
        "wings":
            var wing: Dictionary = WingRows.read(fields, id_to_index)
            if (wing["error"] as String) != "":
                return wing["error"] as String
            wings.append(wing)
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
