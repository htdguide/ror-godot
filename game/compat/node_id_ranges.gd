class_name NodeIdRanges
extends RefCounted
## Resolves a `forset` node-id range list into node indices.
##
## Lives apart from the truck parser because it is the one piece of that file with a
## subtle rule, its own failure history, and no dependence on parser state beyond the id
## table — which makes it the piece worth being able to read and test on its own.


## "0-91", "0,5,7-9": inclusive ranges over node *ids*, not indices.
##
## The range is walked in id space and each id resolved separately. Resolving only the two
## endpoints and walking the indices between them assumes ids and indices run together,
## which they do not: the hero asset has ids that resolve one index apart from their
## numeric value, so whole parts were bound to the wrong nodes — the door hung open and
## the tailgate went missing.
static func resolve(spec: String, id_to_index: Dictionary) -> PackedInt32Array:
    var out: PackedInt32Array = PackedInt32Array()
    for part: String in spec.replace(" ", ",").split(","):
        var token: String = part.strip_edges()
        if token.is_empty():
            continue
        var dash: int = token.find("-", 1)
        if dash < 0:
            _append_id(out, token, id_to_index)
            continue
        var first_id: String = token.substr(0, dash).strip_edges()
        var last_id: String = token.substr(dash + 1).strip_edges()
        if not first_id.is_valid_int() or not last_id.is_valid_int():
            continue
        for id: int in range(first_id.to_int(), last_id.to_int() + 1):
            _append_id(out, str(id), id_to_index)
    return out


static func _append_id(out: PackedInt32Array, id: String, id_to_index: Dictionary) -> void:
    var resolved: int = int(id_to_index.get(id, -1))
    if resolved >= 0:
        out.append(resolved)
