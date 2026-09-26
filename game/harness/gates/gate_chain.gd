extends GateBase
## The gate graph is sound: every edge names a real gate, nothing builds on itself, and there are
## no cycles.
##
## The graph is what `tools/gate.sh --all` schedules from. A bad edge there is worse than a bad
## gate, because it does not fail — it silently marks a gate as implied and stops running it. A
## typo in a `builds_on` entry would do exactly that, so it fails here instead.
##
## What this gate cannot check is whether an edge is *true*: "running this exercises that, at
## least as hard" is a claim about two claims, and nothing but a person reading both can settle
## it. `tools/gate.sh --all --every` is the safety net — it ignores the graph and runs every gate
## — and this gate reports how much of the suite the graph is allowed to skip, so the size of that
## exposure is a number rather than a feeling.

## How much of the suite may be implied rather than run. Not a law of nature: a bound that makes
## the suite's exposure visible, and that a run of edges added without thought would cross.
const MAX_IMPLIED_SHARE: float = 0.4


static func meta() -> Dictionary:
    return {
        "name": "gate_chain",
        "proves": "every builds_on edge names a real gate, no gate builds on itself, the graph has no cycles, and the share of the suite the graph can imply stays bounded",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "0 broken edges, 0 cycles, at most %d%% of gates implied"
            % int(MAX_IMPLIED_SHARE * 100.0)
        ),
        "why": (
            "a bad edge does not fail, it skips: a typo in builds_on marks a gate as implied by"
            + " a gate that does not cover it and the suite quietly stops running it. The share"
            + " bound is there because the graph's exposure — how much of the suite is trusted"
            + " rather than run — should be a number somebody can watch grow."
        ),
        "budget_s": 20.0,
        "needs_gpu": false,
        "milestone": "M0",
    }


func run(_harness: Node) -> Dictionary:
    var graph: Dictionary = GateChain.load_graph()
    if graph.is_empty():
        return fail("no gates were found to build a graph from")
    var problems: PackedStringArray = GateChain.problems(graph)
    if problems.size() > 0:
        return fail("the gate graph is broken: " + "; ".join(problems), problems.size())

    var implied: PackedStringArray = PackedStringArray()
    for name: String in graph.keys():
        for edge: String in GateChain.closure(graph, name):
            if not implied.has(edge):
                implied.append(edge)
    var share: float = float(implied.size()) / float(graph.size())
    if share > MAX_IMPLIED_SHARE:
        return fail(
            "%d of %d gates (%.0f%%) can be implied by another gate, over %.0f%%: the suite is"
            % [implied.size(), graph.size(), share * 100.0, MAX_IMPLIED_SHARE * 100.0]
            + " trusting the graph more than it runs itself",
            share
        )

    var roots: PackedStringArray = GateChain.roots(graph)
    var tiers: Dictionary = {}
    for name: String in graph.keys():
        var tier: int = (graph[name] as Dictionary)["tier"] as int
        tiers[tier] = int(tiers.get(tier, 0)) + 1
    var described: PackedStringArray = PackedStringArray()
    var levels: Array = tiers.keys()
    levels.sort()
    for tier: int in levels:
        described.append("tier %d: %d" % [tier, tiers[tier]])
    return ok(
        "%d gates, %d roots, %s; %d gates (%.0f%%) can be implied by a higher one"
        % [graph.size(), roots.size(), ", ".join(described), implied.size(), share * 100.0],
        share
    )
