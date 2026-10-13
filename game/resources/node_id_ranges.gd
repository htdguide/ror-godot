class_name NodeIdRanges
extends RefCounted
## Resolves a `forset` node-id range list into node indices.
##
## Lives apart from the truck parser because it is the one piece of that file with a
## subtle rule, its own failure history, and no dependence on parser state beyond the id
## table — which makes it the piece worth being able to read and test on its own.


## "0-91", "0,5,7-9", "0 - 36": inclusive ranges over node *ids*, not indices, read as upstream's
## `ProcessForsetLine` reads them: leading spaces, colons and commas skipped; each comma-separated
## item a number or two around a dash, each read as `strtoul` reads it (spaces before it skipped,
## digits up to anything else, none at all being 0). So "0 - 36" is the range 0 to 36, "1 2" is 1,
## and garbage or a trailing comma adds node 0, quirks upstream keeps for old files.
##
## The range is walked in id space and each id resolved separately. Resolving only the two
## endpoints and walking the indices between them assumes ids and indices run together,
## which they do not: the hero asset has ids that resolve one index apart from their
## numeric value, so whole parts were bound to the wrong nodes — the door hung open and
## the tailgate went missing.
static func resolve(spec: String, id_to_index: Dictionary) -> PackedInt32Array:
    var out: PackedInt32Array = PackedInt32Array()
    var at: int = 0
    while at < spec.length() and spec[at] in [" ", ":", ","]:
        at += 1
    var items: PackedStringArray = spec.substr(at).split(",")
    for item: String in items:
        var dash: int = item.find("-")
        var first: int = _strtoul(item if dash < 0 else item.substr(0, dash))
        var last: int = first if dash < 0 else _strtoul(item.substr(dash + 1))
        for id: int in range(first, last + 1):
            _append_id(out, str(id), id_to_index)
    return out


## C's `strtoul` in base 10 as upstream calls it: blanks skipped, then the digits there are.
static func _strtoul(text: String) -> int:
    var at: int = 0
    while at < text.length() and text[at] in [" ", "\t"]:
        at += 1
    var value: int = 0
    while at < text.length() and text[at] >= "0" and text[at] <= "9":
        value = value * 10 + text.unicode_at(at) - 48
        at += 1
    return value


static func _append_id(out: PackedInt32Array, id: String, id_to_index: Dictionary) -> void:
    var resolved: int = int(id_to_index.get(id, -1))
    if resolved >= 0:
        out.append(resolved)
