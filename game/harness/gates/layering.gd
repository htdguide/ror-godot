extends GateBase
## Enforces the one-way dependency rule.
##
## Layers, in order: solver (C++, no Godot symbols) -> bridge -> world/compat ->
## harness. Dependencies point one way only. Rigs of Rods' current renderer coupling is
## exactly what happens without this rule, and it is the reason the renderer could not
## be replaced in place, so it is mechanised here from the first commit.

const LAYER_ORDER: Array[String] = ["solver", "bridge", "compat", "world", "harness"]
const DIR_TO_LAYER: Dictionary = {
    "compat": "compat",
    "world": "world",
    "harness": "harness",
    "bridge": "bridge",
}
## Config is data with no logic, so every layer may read it.
const SHARED: Array[String] = ["config", "shaders", "post", "tools"]


static func meta() -> Dictionary:
    return {
        "name": "layering",
        "proves": "no source file imports or references a layer above its own",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "0 upward references",
        "why": (
            "Rigs of Rods' solver reaches into its renderer today, which is why the"
            + " renderer cannot be swapped. One-way dependencies are the property that"
            + " makes this rewrite possible, so it is checked rather than intended."
        ),
        "budget_s": 25.0,
        "needs_gpu": false,
        "milestone": "M0",
    }


func run(_harness: Node) -> Dictionary:
    var offenders: PackedStringArray = PackedStringArray()
    var checked: int = 0
    for path: String in SourceScan.find_files(SourceScan.repo_root(), ["gd"]):
        var layer: String = _layer_of(path)
        if layer == "":
            continue
        var rank: int = LAYER_ORDER.find(layer)
        var lines: PackedStringArray = SourceScan.read_lines(path)
        for i: int in lines.size():
            var line: String = lines[i]
            if SourceScan.is_comment_or_blank(line):
                continue
            checked += 1
            for other: String in LAYER_ORDER:
                if LAYER_ORDER.find(other) <= rank:
                    continue
                if line.contains("res://%s/" % other):
                    offenders.append(
                        "%s:%d %s references %s" % [SourceScan.relative(path), i + 1, layer, other]
                    )
    if offenders.size() > 0:
        return fail("upward references: " + ", ".join(offenders), offenders.size())
    return ok("%d lines checked across %d layers" % [checked, LAYER_ORDER.size()], 0)


func _layer_of(path: String) -> String:
    for dir_name: String in DIR_TO_LAYER.keys():
        if path.contains("/%s/" % dir_name):
            return DIR_TO_LAYER[dir_name] as String
    return ""
