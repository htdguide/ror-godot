class_name GateChain
extends RefCounted
## The gate suite as a graph, so that a failure points at where the fault is rather than at
## everything downstream of it.
##
## A gate may declare `builds_on`: the gates whose claims its own claim contains. The edge means
## two things, and both have to be true before it is written:
##
## 1. **Passing implies.** Running this gate exercises everything the named gate exercises, at
##    least as hard, so if this one passes the named one's claim holds. A vehicle photographed
##    from eight sides has rendered a frame; there is no need to also prove that a cube renders.
## 2. **Failing localises.** If this gate fails, the named gates are where to look next, in order,
##    until one of them fails too — and the lowest failing gate is the fault's own level.
##
## The edges are claims about claims and nothing can check them automatically, which is why
## `tools/gate.sh --all --every` exists and is what a release run uses: it ignores the graph and
## runs every gate, which is the only thing that can catch an edge that was never true. An implied
## gate is therefore reported as implied and never as passed.
##
## A gate with no `builds_on` is a leaf, and a gate nothing builds on is a root. Both are normal.

const GATE_DIR: String = "res://harness/gates"
## A gate's tier is the longest chain of edges below it: leaves are 0, and a gate that builds on a
## leaf is 1. Tiers are what the runner walks, highest first.
const LEAF_TIER: int = 0


## Every gate, with what it builds on and what tier that puts it in.
##
## Returns {name: {"builds_on": PackedStringArray, "tier": int}}. Unknown names are kept as
## declared rather than dropped, so that `problems` can report them instead of the graph quietly
## losing an edge.
static func load_graph() -> Dictionary:
    var graph: Dictionary = {}
    var dir: DirAccess = DirAccess.open(GATE_DIR)
    if dir == null:
        return graph
    for file: String in dir.get_files():
        if not file.ends_with(".gd"):
            continue
        var name: String = file.get_basename()
        var script: GDScript = load("%s/%s" % [GATE_DIR, file]) as GDScript
        if script == null or not script.can_instantiate():
            continue
        var meta_dict: Dictionary = script.call("meta") as Dictionary
        var declared: Array = meta_dict.get("builds_on", []) as Array
        var edges: PackedStringArray = PackedStringArray()
        for edge: Variant in declared:
            edges.append(str(edge))
        graph[name] = {"builds_on": edges, "tier": LEAF_TIER}
    _assign_tiers(graph)
    return graph


## What is wrong with the graph, as a list of sentences. Empty when it is sound.
static func problems(graph: Dictionary) -> PackedStringArray:
    var found: PackedStringArray = PackedStringArray()
    for name: String in graph.keys():
        for edge: String in (graph[name] as Dictionary)["builds_on"] as PackedStringArray:
            if edge == name:
                found.append("%s builds on itself" % name)
            elif not graph.has(edge):
                found.append("%s builds on '%s', which is not a gate" % [name, edge])
    for name: String in graph.keys():
        var cycle: PackedStringArray = _cycle_from(graph, name)
        if cycle.size() > 0:
            found.append("a cycle runs through %s" % " -> ".join(cycle))
            break
    return found


## Everything a gate builds on, directly or through another gate.
static func closure(graph: Dictionary, name: String) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    var queue: PackedStringArray = PackedStringArray([name])
    while queue.size() > 0:
        var current: String = queue[0]
        queue.remove_at(0)
        if not graph.has(current):
            continue
        for edge: String in (graph[current] as Dictionary)["builds_on"] as PackedStringArray:
            if out.has(edge) or edge == name:
                continue
            out.append(edge)
            queue.append(edge)
    return out


## The order the runner walks: highest tier first, alphabetical inside a tier so that a run is
## reproducible.
static func order(graph: Dictionary) -> PackedStringArray:
    var names: Array[String] = []
    for name: String in graph.keys():
        names.append(name)
    names.sort_custom(func(a: String, b: String) -> bool:
        var tier_a: int = (graph[a] as Dictionary)["tier"] as int
        var tier_b: int = (graph[b] as Dictionary)["tier"] as int
        if tier_a != tier_b:
            return tier_a > tier_b
        return a < b
    )
    var out: PackedStringArray = PackedStringArray()
    for name: String in names:
        out.append(name)
    return out


## The gates nothing builds on: the tops of the chains.
static func roots(graph: Dictionary) -> PackedStringArray:
    var covered: PackedStringArray = PackedStringArray()
    for name: String in graph.keys():
        for edge: String in (graph[name] as Dictionary)["builds_on"] as PackedStringArray:
            if not covered.has(edge):
                covered.append(edge)
    var out: PackedStringArray = PackedStringArray()
    for name: String in graph.keys():
        if not covered.has(name):
            out.append(name)
    out.sort()
    return out


## --------------------------------------------------------------------------------


## The tier of every gate: one more than the deepest gate it builds on. Computed by walking, not
## by recursion, so that a cycle cannot take the whole harness down with it — a gate caught in one
## keeps the leaf tier and `problems` reports the cycle.
static func _assign_tiers(graph: Dictionary) -> void:
    for _pass: int in graph.size():
        var changed: bool = false
        for name: String in graph.keys():
            var entry: Dictionary = graph[name] as Dictionary
            var tier: int = LEAF_TIER
            for edge: String in entry["builds_on"] as PackedStringArray:
                if not graph.has(edge):
                    continue
                tier = maxi(tier, ((graph[edge] as Dictionary)["tier"] as int) + 1)
            if tier != (entry["tier"] as int):
                entry["tier"] = tier
                changed = true
        if not changed:
            return


## A cycle through `start`, as the path that returns to it, or empty when there is none.
static func _cycle_from(graph: Dictionary, start: String) -> PackedStringArray:
    var path: PackedStringArray = PackedStringArray([start])
    var seen: PackedStringArray = PackedStringArray([start])
    return _walk_for_cycle(graph, start, start, path, seen)


static func _walk_for_cycle(
    graph: Dictionary, start: String, current: String,
    path: PackedStringArray, seen: PackedStringArray
) -> PackedStringArray:
    if not graph.has(current):
        return PackedStringArray()
    for edge: String in (graph[current] as Dictionary)["builds_on"] as PackedStringArray:
        if edge == start:
            var closed: PackedStringArray = path.duplicate()
            closed.append(start)
            return closed
        if seen.has(edge):
            continue
        seen.append(edge)
        var deeper: PackedStringArray = path.duplicate()
        deeper.append(edge)
        var found: PackedStringArray = _walk_for_cycle(graph, start, edge, deeper, seen)
        if found.size() > 0:
            return found
    return PackedStringArray()
