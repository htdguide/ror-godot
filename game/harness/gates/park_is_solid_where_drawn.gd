extends GateBase
## Every prop the test park draws is solid where it is drawn, and nothing is solid where nothing is
## drawn.
##
## The park's ramps, walls, kerbs, poles, crates and rocks are described once and used twice: the
## renderer draws boxes at those transforms and the solver takes the same transforms as static
## obstacles. The failure that description exists to prevent is the two drifting apart — a ramp
## drawn where the rig cannot climb it, or a wall that stops a truck a metre before it arrives —
## and it is invisible in a picture and invisible in a physics trace. It is only visible by asking
## both.
##
## So for every prop, three points are asked of both: just inside its top face, a little above it,
## and beside it. The solver's answer has to match the drawn geometry's own — not "nothing is
## there", because the park stacks crates and rings the skid pad, and a point above one prop is
## quite properly inside another. Matching the geometry is the claim; matching an assumption about
## what is nearby is how a check like this ends up wrong about a stack.

## How far inside the drawn face the inside point sits, and how far above the outside point does.
## Both bigger than the solver's own tolerance and smaller than anything the park is made of.
const INSIDE_M: float = 0.05
const OUTSIDE_M: float = 0.35
## The park is not a park without these, and the count is what catches a segment that silently
## stopped being built.
const MIN_PROPS: int = 80


static func meta() -> Dictionary:
    return {
        "name": "park_is_solid_where_drawn",
        "proves": "every prop in the test park is a solver obstacle at the transform it is drawn at, and the space above it is clear",
        # a solid box is what obstacles_are_solid proves; this is the park's own use of them.
        "builds_on": ["obstacles_are_solid"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "every prop solid %.0f cm inside its top face and clear %.0f cm above it;"
            % [INSIDE_M * 100.0, OUTSIDE_M * 100.0]
            + " at least %d props" % MIN_PROPS
        ),
        "why": (
            "the props are drawn from one list and collided from another use of the same list,"
            + " and the fault worth catching is those two drifting apart: a ramp drawn where the"
            + " rig cannot climb it, a wall that stops a truck a metre early. Neither shows in a"
            + " picture or in a physics trace, only in asking both about the same point."
        ),
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var solver: RefCounted = ClassDB.instantiate("RorSolver") as RefCounted
    if solver == null:
        return fail("RorSolver is not registered: the GDExtension did not load")
    var props: Array[Dictionary] = ParkProps.boxes()
    if props.size() < MIN_PROPS:
        return fail(
            "the park has %d props, under %d: a segment is not being built"
            % [props.size(), MIN_PROPS],
            props.size()
        )
    var added: int = ParkProps.apply_to_solver(solver)
    if added != props.size():
        return fail(
            "%d props were drawn and %d were handed to the solver" % [props.size(), added],
            added
        )

    var kinds: Dictionary = {}
    for index: int in props.size():
        var prop: Dictionary = props[index]
        var transform: Transform3D = prop["transform"] as Transform3D
        var half: Vector3 = prop["half"] as Vector3
        var kind: String = prop["kind"] as String
        kinds[kind] = int(kinds.get(kind, 0)) + 1
        # The middle of the box's own top face, which is where a wheel would meet it.
        var up: Vector3 = transform.basis.y.normalized()
        var top: Vector3 = transform.origin + up * half.y

        var inside: Dictionary = solver.obstacle_contact(top - up * INSIDE_M)
        if not bool(inside["hit"]):
            return fail(
                "prop %d (%s) is drawn at %v but nothing is solid %.0f cm inside its top face"
                % [index, kind, transform.origin, INSIDE_M * 100.0],
                index
            )
        if int(inside["surface"]) != GroundModels.index_of(prop["surface"] as String):
            return fail(
                "prop %d (%s) is drawn as %s but the solver has it as %s"
                % [index, kind, prop["surface"],
                   GroundModels.name_of(int(inside["surface"]))],
                index
            )
        # Above it and beside it, where the answer is whatever the drawn boxes say it is.
        for probe: Vector3 in [
            top + up * OUTSIDE_M,
            transform.origin + transform.basis.x.normalized() * (half.x + OUTSIDE_M),
        ]:
            var solid: bool = bool((solver.obstacle_contact(probe) as Dictionary)["hit"])
            var drawn: bool = _inside_any(props, probe)
            if solid != drawn:
                return fail(
                    "at %v the solver says %s and the drawn props say %s, near prop %d (%s)"
                    % [probe, "solid" if solid else "clear", "solid" if drawn else "clear",
                       index, kind],
                    index
                )
    var described: PackedStringArray = PackedStringArray()
    var names: Array = kinds.keys()
    names.sort()
    for kind: String in names:
        described.append("%d %s" % [kinds[kind], kind])
    return ok(
        "%d props, the solver and the drawn geometry agreeing at every probe: %s"
        % [props.size(), ", ".join(described)],
        props.size()
    )


## Whether a point is inside any drawn prop, computed here rather than asked of the solver: this is
## the geometry the solver is being compared against, so it has to come from the other side.
func _inside_any(props: Array[Dictionary], point: Vector3) -> bool:
    for prop: Dictionary in props:
        var transform: Transform3D = prop["transform"] as Transform3D
        var half: Vector3 = prop["half"] as Vector3
        var local: Vector3 = transform.basis.transposed() * (point - transform.origin)
        if (absf(local.x) < half.x and absf(local.y) < half.y and absf(local.z) < half.z):
            return true
    return false
