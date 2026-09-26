#!/usr/bin/env python3
"""Schedules the gate suite from the gate graph.

The graph itself comes from the engine (`--chain`), because the edges are declared in the
gates and nothing outside Godot can read them. This only does the arithmetic on it, so that
the runner does not have to: bash on macOS is 3.2 and has no associative arrays.

Subcommands, all taking the chain JSON on a `--chain` file:

    order                  every gate, highest tier first: the order a run walks
    closure GATE           everything GATE builds on, directly or through another gate
    implied GATE           the same list, for marking off when GATE passes
    localize --results F   for each failed gate, the lowest failing gate under it
"""

import argparse
import json
import sys


def load(path):
    with open(path) as handle:
        text = handle.read()
    marker = "HARNESS_CHAIN "
    if marker in text:
        text = text[text.index(marker) + len(marker):]
    return json.loads(text)


def tier_of(chain, gate):
    return chain["gates"].get(gate, {}).get("tier", 0)


def closure(chain, gate):
    """Everything `gate` builds on, transitively, highest tier first."""
    gates = chain["gates"]
    out = []
    queue = list(gates.get(gate, {}).get("builds_on", []))
    while queue:
        current = queue.pop(0)
        if current == gate or current in out or current not in gates:
            continue
        out.append(current)
        queue.extend(gates[current].get("builds_on", []))
    return sorted(out, key=lambda name: (-tier_of(chain, name), name))


def read_results(path):
    """The run so far, as [(gate, verdict)] in the order it happened."""
    rows = []
    with open(path) as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2 and parts[0]:
                rows.append((parts[0], parts[1]))
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["order", "closure", "implied", "localize"])
    parser.add_argument("gate", nargs="?", default="")
    parser.add_argument("--chain", required=True)
    parser.add_argument("--results", default="")
    options = parser.parse_args()
    chain = load(options.chain)

    if options.command == "order":
        for gate in chain.get("order", sorted(chain["gates"])):
            print(gate)
        return 0

    if options.command in ("closure", "implied"):
        if not options.gate:
            print("gate_plan.py: %s needs a gate name" % options.command, file=sys.stderr)
            return 2
        for gate in closure(chain, options.gate):
            print(gate)
        return 0

    # localize: for every failure, the lowest gate under it that also failed. That gate is the
    # level the fault is at — everything above it failed because of it, and everything below it
    # passed, so the fault is in what it alone exercises.
    if not options.results:
        print("gate_plan.py: localize needs --results", file=sys.stderr)
        return 2
    results = dict(read_results(options.results))
    failed = [gate for gate, verdict in results.items() if verdict == "FAIL"]
    if not failed:
        return 0
    reported = set()
    for gate in sorted(failed, key=lambda name: (-tier_of(chain, name), name)):
        under = [name for name in closure(chain, gate) if results.get(name) == "FAIL"]
        if not under:
            if gate not in reported:
                print("%s\t%s\t%s" % (gate, gate, "no lower gate failed"))
                reported.add(gate)
            continue
        lowest = min(under, key=lambda name: (tier_of(chain, name), name))
        below = closure(chain, lowest)
        if not below:
            note = "it builds on nothing: the lowest level there is"
        elif all(results.get(name) == "PASS" for name in below):
            note = "everything it builds on passed"
        else:
            note = "not everything under it was run"
        print("%s\t%s\t%s" % (gate, lowest, note))
        reported.add(gate)
        reported.add(lowest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
