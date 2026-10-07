class_name WheelBeams
extends RefCounted
## Records the beams a generated wheel is made of, the way upstream's `AddWheelBeam` does.
##
## Split from `WheelRig` when that file reached its cap, and it is the half that knows what a wheel
## beam *is* — a spoke is bounded, a support beam carries nothing until the tyre is nearly on the
## rim, a rigidity beam is virtual — while `WheelRig` knows where each one goes.
##
## **A wheel without its rigidity beams folds under its own drive torque.** Every wheel section
## names a rigidity node — `9999` for none — and upstream ties one beam per ray from it to the ring
## node on its side (`BuildWheelBeams`, `ProcessWheel2`, `ProcessFlexBodyWheel`), typed
## `BEAM_VIRTUAL`: force like any other beam, never drawn, no share of the rig's mass. On a rigid
## axle the row names the far hub, so those beams are what hold the wheel's camber: the axle's own
## nodes are collinear and a chain of collinear beams is a hinge. Built without them, the Burnside
## Drag's rear axle leaned 40 degrees within 0.4 s of first throttle and 80 degrees by the end of
## the run, with the tyres' grip taken away entirely — so it was never the ground, it was the hub
## having nothing to hold it square. 19 of 66 driveable vehicles did the same.


## A plain wheel beam at the rates given, yielding and breaking where the row's defaults say.
static func add(
    truck: TruckParser, a: int, b: int, spring: float, damp: float, stress: Dictionary,
    is_virtual: bool = false
) -> void:
    truck.beam_table.record({
        "a": a,
        "b": b,
        "spring": spring,
        "damp": damp,
        "deform": stress["deform"],
        "strength": stress["strength"],
        "plastic_coef": stress["plastic"],
        "bound": BeamRows.BOUND_NORMAL,
        "short_bound": 0.0,
        "long_bound": 0.0,
        "bound_spring": spring,
        "bound_damp": damp,
        "precompression": 1.0,
        "virtual": is_virtual,
    })


## A tyre's own spoke: the axle to one tread node, and upstream bounds it.
##
## `AddWheelBeam(..., 0.66f, max_extension)` makes every one of these a SHOCK1 that may be
## compressed to two thirds of its length and stretched by `max_extension` before handing over to
## the structural rates. The handover is to upstream's own defaults rather than the file's,
## because a wheel beam is not a `shocks` beam: `ActorForcesEuler.cpp` takes the shock's stated
## rates only for `BEAM_HYDRO`, and a wheel's beams are not that.
##
## Left unbounded, a tyre is held on by its stated rate alone and a spinning wheel throws its
## tread off the hub.
static func add_tyre(
    truck: TruckParser, a: int, b: int, spring: float, damp: float, stress: Dictionary,
    reach: float
) -> void:
    truck.bounded_beams.append({
        "beam": truck.beams.size() / 2,
        "bound": BeamRows.BOUND_SHOCK,
        "short_bound": WheelRows.TYRE_MAX_CONTRACTION,
        "long_bound": reach,
        "bound_spring": BeamDefaults.DEFAULT_SPRING,
        "bound_damp": BeamDefaults.DEFAULT_DAMP,
        "precompression": 1.0,
    })
    add(truck, a, b, spring, damp, stress)


## A beam that is a plain spring until it is compressed past `short_bound`, then ramps towards
## the structural rates. Upstream's SHOCK1.
static func add_support(
    truck: TruckParser, a: int, b: int, spring: float, damp: float, short_bound: float,
    stress: Dictionary
) -> void:
    truck.bounded_beams.append({
        "beam": truck.beams.size() / 2,
        "bound": BeamRows.BOUND_SHOCK,
        "short_bound": short_bound,
        "long_bound": 0.0,
        "bound_spring": spring,
        "bound_damp": damp,
        "precompression": 1.0,
    })
    add(truck, a, b, spring, damp, stress)


## The rigidity beams: one per ray, from the node the row names to the ring node on its side.
##
## Upstream picks the side by distance — the ring braced to whichever axle node the rigidity node
## is nearer, `distance_1 < distance_2`, so a tie goes to the second — and the beams are virtual.
## Returns how many were added; none when the row names no node, which is what `9999` means.
static func add_rigidity(
    truck: TruckParser, wheel: Dictionary, ring_a: PackedInt32Array, ring_b: PackedInt32Array,
    spring: float, damp: float, stress: Dictionary
) -> int:
    var rigidity: int = int(wheel.get("rigidity_node", -1))
    if rigidity < 0 or rigidity >= truck.nodes.size():
        return 0
    var at: Vector3 = truck.nodes[rigidity]
    var side_a: bool = (
        at.distance_to(truck.nodes[wheel["node1"] as int])
        < at.distance_to(truck.nodes[wheel["node2"] as int])
    )
    var ring: PackedInt32Array = ring_a if side_a else ring_b
    for node: int in ring:
        add(truck, rigidity, node, spring, damp, stress, true)
    return ring.size()


## What a wheel's generated beams bend and break at: the defaults in force where its row stands,
## which is where upstream's `AddWheelBeam` takes them from.
##
## **Left unset, which was invisible only while the tread was built last**: a beam with no entry
## in the stress tables falls off the end and the solver's default stands in. Built where upstream
## builds it the tread sits *ahead* of the file's beams, and each of those read the entry beside
## it — the hero truck's tyres came out with a 750 N yield and went flat on a 2.4 m/s wall.
static func stress(wheel: Dictionary) -> Dictionary:
    return {
        "deform": wheel.get("deform", BeamDefaults.DEFAULT_DEFORM),
        "strength": wheel.get("strength", BeamDefaults.DEFAULT_BREAK),
        "plastic": wheel.get("plastic", BeamDefaults.DEFAULT_PLASTIC_COEF)}
