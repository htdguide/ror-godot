extends GateBase
## Enforces the one-way dependency rule.
##
## Layers, in order: solver (C++, no Godot symbols) -> bridge -> resources -> physics ->
## terrain -> gfx -> harness. Dependencies point one way only. Rigs of Rods' current renderer
## coupling is exactly what happens without this rule, and it is the reason the renderer could
## not be replaced in place, so it is mechanised here from the first commit.
##
## The layer names are upstream's own directory names, because `game/` mirrors
## `source/main/` — see PLAN 0.7. They were `compat` and `world` until the tree was mirrored;
## that rename changed these names and nothing about what is checked.
##
## A dependency is found by the `res://` path a line names, which means a dependency taken
## through a `class_name` is invisible here. That was true before the mirror as well and is
## deliberately left alone by it: a rename that also changes what is checked is two commits.

const LAYER_ORDER: Array[String] = [
    "solver", "bridge", "resources", "physics", "terrain", "gfx", "harness",
]
## Where each layer's files live, as the `res://` prefix a reference to it would carry.
const LAYER_PATHS: Dictionary = {
    "bridge": "res://bin/",
    "resources": "res://game/resources/",
    "physics": "res://game/physics/",
    "terrain": "res://game/terrain/",
    "gfx": "res://game/gfx/",
    "harness": "res://harness/",
}
## The directory that puts a file in a layer.
const DIR_TO_LAYER: Dictionary = {
    "resources": "resources",
    "physics": "physics",
    "terrain": "terrain",
    "gfx": "gfx",
    "harness": "harness",
}
## Config is data with no logic, so every layer may read it. So are the shaders a layer draws
## with — they sit at `game/shaders/` rather than under `gfx/` for exactly this reason, and
## upstream keeps its own shader and material assets in its content tree rather than in
## `source/main` too. The dev probes are not a layer at all.
const SHARED: Array[String] = ["config", "shaders", "dev", "utils"]
## A prefix no line can contain, for a layer that names no directory of its own. GDScript reads
## a `\u0000` escape in a source string as a real NUL and warns on every load, so this is spelled
## out rather than written as an unreachable escape.
const NO_SUCH_LAYER: String = "res://<no-such-layer>/"


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
                if line.contains(LAYER_PATHS.get(other, NO_SUCH_LAYER) as String):
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
