class_name Scenarios
extends RefCounted
## Deterministic scripted scenarios, shared by every gate.
##
## Fixtures live here and nowhere else. A gate that builds its own ad-hoc scene is how
## a suite starts disagreeing with itself about what the product does, so gates name a
## scenario instead.
##
## A scenario advances by tick index, never by elapsed time. M0 has only `static`,
## because there is no solver to drive yet; the driving scenarios arrive with the
## bridge in M1.

const SCENARIOS: Dictionary = {
    "static": {
        "ticks": 0,
        "describes": "nothing moves; used for image gates that must be bit-stable",
    },
}


static func has(name: String) -> bool:
    return SCENARIOS.has(name)


static func names() -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    for key: String in SCENARIOS.keys():
        out.append(key)
    return out


## Advances a scenario by one tick. M0's only scenario is static, so this is a no-op
## that exists to fix the call site before the solver lands.
static func tick(_name: String, _tick_index: int, _world: Node3D) -> void:
    pass
