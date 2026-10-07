class_name WheelRig
extends RefCounted
## Generates the tread nodes and beams a wheel section only implies.
##
## A `meshwheels2` row names two axle nodes and a tyre radius; the nodes the tyre actually stands
## on are generated from that, not written in the file. Without them the lowest node of the whole
## vehicle is an axle, ground contact happens there, and the vehicle is drawn sunk into the ground
## by the tyre radius — measured at 0.34 m on the hero truck.
##
## Follows upstream's `BuildWheelObjectAndNodes` + `BuildWheelBeams`: 2·rays nodes per wheel, laid
## as a zig-zag alternating between the two axle planes, and 8·rays beams.
##
## Generated nodes are appended after the file's own and after any cinecam node, which is where
## upstream appends them, so a file that names one by number — a hubcap prop, a tyre flexbody —
## reaches the node it meant. See `TruckDocument`.

## Used only when a wheel row carries no recorded beam defaults, which a hand-built test rig may
## not. Upstream's rim beams come from the beam defaults rather than the wheel's own spring, which
## is the tyre's; falling back to the tyre value makes the rim as soft as the sidewall.
## Where a flexbody wheel's tyre mesh sits: half way from the first wheel node towards each of the
## two axle nodes, which is upstream's `Ogre::Vector3(0.5f, 0.5f, 0.f)`. The offsets multiply the
## unnormalised node differences, so this is the wheel's own centre whatever its track.
const TYRE_OFFSET: Vector3 = Vector3(0.5, 0.5, 0.0)
const RIM_SPRING_FALLBACK: float = 4000000.0
const RIM_DAMP_FALLBACK: float = 150.0


## Reads one row of a wheel section into `truck`, with the directives in force where it stands.
##
## **The rates a wheel takes are the ones written above it**, so each row carries its own: the
## tread is generated once every row is read. The hero truck states `set_node_defaults -1, 1.06`
## above its front pair and `-1, 1.12` above its rear, and those are the grip its tyres have.
static func read_row(truck: TruckParser, section: String, line: String) -> String:
    var row: Dictionary = WheelRows.row(section, TruckLexer.fields(line), truck.node_id_to_index)
    if (row["error"] as String) != "":
        return row["error"] as String
    row.erase("error")
    row["friction"] = truck.node_defaults.friction
    # **Unscaled, which is upstream's own asymmetry.** `ProcessMeshWheel2` reads
    # `def.beam_defaults->springiness` and `->damping_constant` directly, not the scaled
    # accessors it uses for ordinary beams, so a rig's `set_beam_defaults_scale` does not reach
    # its wheels. The hero truck scales damping by 0.25: read as scaled, its rims come out at
    # 37.5 Ns/m against the 150 its file states.
    #
    # Only where the section states no rim rates of its own, which `wheels2` and `flexbodywheels`
    # do.
    if not row.has("rim_spring"):
        row["rim_spring"] = truck.beam_defaults.spring_unscaled()
        row["rim_damp"] = truck.beam_defaults.damp_unscaled()
    # The tyre tread's own hoop, which upstream takes from the beam defaults whatever the row
    # states: `float tread_spring = def.beam_defaults->springiness;`. On the Mazda that is
    # 100000 against the 320000 its rim rate states, so the two are not interchangeable.
    row["tread_spring"] = truck.beam_defaults.spring_unscaled()
    row["tread_damp"] = truck.beam_defaults.damp_unscaled()
    # What its beams bend and break at. See `_stress`.
    row["deform"] = truck.beam_defaults.deform()
    row["strength"] = truck.beam_defaults.breaking_strength()
    row["plastic"] = truck.beam_defaults.plastic_coef()
    truck.wheels.append(row)
    return ""


## Adds every wheel's tread to the rig. Returns {"nodes": int, "beams": int}.
static func generate(truck: TruckParser) -> Dictionary:
    var nodes_before: int = truck.nodes.size()
    var beams_before: int = truck.beams.size() / 2
    for wheel: Dictionary in truck.wheels:
        _order_axis(truck, wheel)
        _generate_one(truck, wheel)
    return {
        "nodes": truck.nodes.size() - nodes_before,
        "beams": truck.beams.size() / 2 - beams_before,
    }


## Upstream orders every wheel's axle nodes so that the first has the smaller z, before
## anything reads them. Files do not: the hero truck states its left wheels outer node
## first and its right wheels outer node first too, which on opposite sides of the vehicle
## are opposite directions in space.
##
## Everything downstream is then handed an axis vector pointing outward on one side of the
## rig and inward on the other. The tread zig-zag winds the opposite way, and — because
## drive torque is applied about that axis — the same engine torque drives the left wheels
## forward and the right wheels backward. Measured on the hero truck: 6 s at full throttle
## moved it 4.70 m, 3.41 m of that sideways, with the left tread at 20.7 m/s and the right
## at 1.4 m/s. The rig was fighting itself.
static func _order_axis(truck: TruckParser, wheel: Dictionary) -> void:
    var node1: int = wheel["node1"] as int
    var node2: int = wheel["node2"] as int
    if truck.nodes[node1].z <= truck.nodes[node2].z:
        return
    wheel["node1"] = node2
    wheel["node2"] = node1


static func _generate_one(truck: TruckParser, wheel: Dictionary) -> void:
    var rays: int = wheel["rays"] as int
    if rays < 3:
        return
    if bool(wheel.get("flexbody", false)):
        _generate_flexbody(truck, wheel)
        return
    # The tread nodes are contiguous and alternate between the two axle planes, which is
    # the layout upstream's wheel force code assumes: even nodes brace to the first axle
    # node, odd ones to the second. Recording where they start is what lets the solver
    # find them without a second copy of the layout rule.
    wheel["first_tread"] = truck.nodes.size()
    wheel["tread_count"] = 2 * rays
    var axis_a: int = wheel["node1"] as int
    var axis_b: int = wheel["node2"] as int
    var origin_a: Vector3 = truck.nodes[axis_a]
    var origin_b: Vector3 = truck.nodes[axis_b]
    var axis: Vector3 = origin_b - origin_a
    if axis.length_squared() == 0.0:
        return
    axis = axis.normalized()

    # Upstream steps the ray by half a ray's angle each time, so the outer and inner
    # treads interleave rather than sitting in pairs. The zig-zag is what gives the
    # sidewall its diagonal bracing.
    var step: float = -TAU / float(2 * rays)
    var ray: Vector3 = _perpendicular(axis) * (wheel["tire_radius"] as float)
    var outer: PackedInt32Array = PackedInt32Array()
    var inner: PackedInt32Array = PackedInt32Array()
    # Upstream spreads the wheel's stated mass evenly over its tread nodes, and exempts them
    # from the rig's own mass distribution and from the minimass floor: a tyre weighs what
    # its row says, not what the structure around it works out to.
    var tread_mass: float = (wheel["mass"] as float) / float(2 * rays)
    var friction: float = wheel.get("friction", 1.0) as float
    for i: int in rays:
        outer.append(_add_node(truck, origin_a + ray, tread_mass, friction))
        ray = ray.rotated(axis, step)
        inner.append(_add_node(truck, origin_b + ray, tread_mass, friction))
        ray = ray.rotated(axis, step)

    var tyre_spring: float = wheel["spring"] as float
    var tyre_damp: float = wheel["damping"] as float
    var rim_spring: float = wheel.get("rim_spring", RIM_SPRING_FALLBACK) as float
    var rim_damp: float = wheel.get("rim_damp", RIM_DAMP_FALLBACK) as float
    var stress: Dictionary = _stress(wheel)
    for i: int in rays:
        var o: int = outer[i]
        var n: int = inner[i]
        var next_o: int = outer[(i + 1) % rays]
        var next_n: int = inner[(i + 1) % rays]
        # Tyre: each tread node braced to both axle nodes, so load crosses the sidewall.
        _add_beam(truck, axis_a, o, tyre_spring, tyre_damp, stress)
        _add_beam(truck, axis_b, n, tyre_spring, tyre_damp, stress)
        _add_beam(truck, axis_b, o, tyre_spring, tyre_damp, stress)
        _add_beam(truck, axis_a, n, tyre_spring, tyre_damp, stress)
        # Rim: the tread ring's own hoop and diagonal stiffness.
        _add_beam(truck, o, n, rim_spring, rim_damp, stress)
        _add_beam(truck, o, next_o, rim_spring, rim_damp, stress)
        _add_beam(truck, n, next_n, rim_spring, rim_damp, stress)
        _add_beam(truck, n, next_o, rim_spring, rim_damp, stress)


## A flexbody wheel: a rim ring and a tyre ring, with the tyre sprung against the rim.
##
## **This is a different rig, not a mesh wheel with different numbers.** Upstream gives it
## `rays * 4` nodes and `rays * 20` beams — eight rim, ten tyre, two support per ray — against a
## mesh wheel's `rays * 2` and `rays * 8` (`ActorSpawner.cpp`, the spawn budget, and
## `ProcessFlexBodyWheel`). Built as a mesh wheel it has half the nodes and two fifths of the
## beams, and what that looks like from the driver's seat is a wheel that wobbles and will not
## stay on its suspension, which is how it was reported.
##
## The tyre ring is what touches the ground, so it is the ring the solver is told about: the rim
## ring carries the wheel's stiffness and the tyre ring carries the contact.
static func _generate_flexbody(truck: TruckParser, wheel: Dictionary) -> void:
    var rays: int = wheel["rays"] as int
    var axis_a: int = wheel["node1"] as int
    var axis_b: int = wheel["node2"] as int
    var origin_a: Vector3 = truck.nodes[axis_a]
    var origin_b: Vector3 = truck.nodes[axis_b]
    var axis: Vector3 = origin_b - origin_a
    if axis.length_squared() == 0.0:
        return
    axis = axis.normalized()

    var rim_radius: float = wheel["rim_radius"] as float
    var tyre_radius: float = wheel["tire_radius"] as float
    var step: float = -TAU / float(2 * rays)
    # Upstream spreads the stated mass over four rings rather than two.
    var node_mass: float = (wheel["mass"] as float) / float(4 * rays)
    var friction: float = wheel.get("friction", 1.0) as float

    var rim_outer: PackedInt32Array = PackedInt32Array()
    var rim_inner: PackedInt32Array = PackedInt32Array()
    var ray: Vector3 = _perpendicular(axis) * rim_radius
    for i: int in rays:
        rim_outer.append(_add_node(truck, origin_a + ray, node_mass, friction))
        ray = ray.rotated(axis, step)
        rim_inner.append(_add_node(truck, origin_b + ray, node_mass, friction))
        ray = ray.rotated(axis, step)

    # The tyre ring starts half a ray round from the rim ring: upstream turns its ray vector once
    # before the loop, which is what interleaves the two rings instead of stacking them.
    var tyre_outer: PackedInt32Array = PackedInt32Array()
    var tyre_inner: PackedInt32Array = PackedInt32Array()
    ray = (_perpendicular(axis) * tyre_radius).rotated(axis, step)
    # The tyre ring is the one that meets the ground, so it is the one the solver drives and
    # brakes through.
    wheel["first_tread"] = truck.nodes.size()
    wheel["tread_count"] = 2 * rays
    for i: int in rays:
        tyre_outer.append(_add_node(truck, origin_a + ray, node_mass, friction))
        ray = ray.rotated(axis, step)
        tyre_inner.append(_add_node(truck, origin_b + ray, node_mass, friction))
        ray = ray.rotated(axis, step)

    _tyre_flexbody(truck, wheel, rim_outer[0])

    var rim_spring: float = wheel["rim_spring"] as float
    var rim_damp: float = wheel["rim_damp"] as float
    # Upstream halves the tyre rate on every rim-to-tyre beam: each tyre node is held by two of
    # them, so the pair together carry what the row states.
    var tyre_spring: float = (wheel["spring"] as float) * 0.5
    var tyre_damp: float = wheel["damping"] as float
    var tread_spring: float = wheel.get("tread_spring", RIM_SPRING_FALLBACK) as float
    var tread_damp: float = wheel.get("tread_damp", RIM_DAMP_FALLBACK) as float
    var stress: Dictionary = _stress(wheel)
    # Where the support beams start to resist, so the tread cannot collapse onto the rim.
    var support_short_bound: float = 1.0 - (rim_radius / maxf(tyre_radius, 0.0001)) * 0.95

    for i: int in rays:
        var next: int = (i + 1) % rays
        var prev: int = (i + rays - 1) % rays
        # Rim: both axle nodes to both rim nodes, then the rim ring's own hoop and diagonals.
        _add_beam(truck, axis_a, rim_outer[i], rim_spring, rim_damp, stress)
        _add_beam(truck, axis_b, rim_inner[i], rim_spring, rim_damp, stress)
        _add_beam(truck, axis_b, rim_outer[i], rim_spring, rim_damp, stress)
        _add_beam(truck, axis_a, rim_inner[i], rim_spring, rim_damp, stress)
        _add_beam(truck, rim_outer[i], rim_inner[i], rim_spring, rim_damp, stress)
        _add_beam(truck, rim_outer[i], rim_outer[next], rim_spring, rim_damp, stress)
        _add_beam(truck, rim_inner[i], rim_inner[next], rim_spring, rim_damp, stress)
        _add_beam(truck, rim_inner[i], rim_outer[next], rim_spring, rim_damp, stress)
        # Tyre: each rim node to three tyre nodes, reaching back a ray, which is the sidewall.
        _add_beam(truck, rim_outer[i], tyre_outer[i], tyre_spring, tyre_damp, stress)
        _add_beam(truck, rim_outer[i], tyre_inner[prev], tyre_spring, tyre_damp, stress)
        _add_beam(truck, rim_outer[i], tyre_outer[prev], tyre_spring, tyre_damp, stress)
        _add_beam(truck, rim_inner[i], tyre_outer[i], tyre_spring, tyre_damp, stress)
        _add_beam(truck, rim_inner[i], tyre_inner[i], tyre_spring, tyre_damp, stress)
        _add_beam(truck, rim_inner[i], tyre_inner[prev], tyre_spring, tyre_damp, stress)
        # Tread: the tyre ring's own stiffness, at the rig's structural rates rather than the
        # tyre's, because it is the carcass rather than the sidewall.
        _add_beam(truck, tyre_outer[i], tyre_inner[i], tread_spring, tread_damp, stress)
        _add_beam(truck, tyre_outer[i], tyre_outer[next], tread_spring, tread_damp, stress)
        _add_beam(truck, tyre_inner[i], tyre_inner[next], tread_spring, tread_damp, stress)
        _add_beam(truck, tyre_inner[i], tyre_outer[next], tread_spring, tread_damp, stress)
        # Support: axle to tread, carrying nothing until the tyre is squashed nearly to the rim.
        _add_support_beam(
            truck, axis_a, tyre_outer[i], tyre_spring, tyre_damp, support_short_bound, stress
        )
        _add_support_beam(
            truck, axis_b, tyre_inner[i], tyre_spring, tyre_damp, support_short_bound, stress
        )


## The tyre of a flexbody wheel is a flexbody, and that is upstream's own answer rather than an
## analogy. `CreateFlexBodyWheelVisuals` draws the rim mesh and then blanks the generated tyre band
## outright — `"tracks/trans", // Use a builtin transparent material ... to effectively disable it`
## — before handing the tyre mesh to the flexbody factory, bound to all four rings of the wheel's
## own nodes at an offset of (0.5, 0.5, 0) from the first of them towards the two axle nodes.
##
## **Drawn as a rigid mesh on the rim instead, it is in the wrong place twice over.** A flexbody
## mesh is authored in the rig's own coordinates, so parenting it to the wheel adds the wheel's
## offset a second time, and nothing then deforms it with the tyre. Reported from a window as the
## tyres being "completely off": a black lump sitting outboard of its own rim.
static func _tyre_flexbody(truck: TruckParser, wheel: Dictionary, base: int) -> void:
    var mesh: String = wheel.get("tyre_mesh", "") as String
    if mesh == "":
        return
    var bound: PackedInt32Array = PackedInt32Array()
    for i: int in 4 * (wheel["rays"] as int):
        bound.append(base + i)
    truck.flexbodies.append({
        "ref": base,
        "nx": wheel["node1"] as int,
        "ny": wheel["node2"] as int,
        "offset": TYRE_OFFSET,
        "rot_deg": Vector3.ZERO,
        "mesh": mesh,
        "forset": bound,
    })


## A beam that is a plain spring until it is compressed past `short_bound`, then ramps towards
## the structural rates. Upstream's SHOCK1.
static func _add_support_beam(
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
    _add_beam(truck, a, b, spring, damp, stress)


static func _add_node(
    truck: TruckParser, position: Vector3, mass: float, friction: float
) -> int:
    var index: int = truck.nodes.size()
    # Registered at its index, because that is how a file reaches it: a generated node is
    # referenced by number like any declared one, and real content does — the Mazda's hubcaps
    # and brake discs each name the first rim node of their own wheel.
    truck.register_generated("@wheel%d" % index)
    truck.nodes.append(position)
    truck.node_mass.append(mass)
    truck.node_friction.append(friction)
    return index


static func _add_beam(
    truck: TruckParser, a: int, b: int, spring: float, damp: float, stress: Dictionary
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
    })


## What a wheel's generated beams bend and break at: the defaults in force where its row stands,
## which is where upstream's `AddWheelBeam` takes them from.
##
## **Left unset, which was invisible only while the tread was built last**: a beam with no entry
## in the stress tables falls off the end and the solver's default stands in. Built where upstream
## builds it the tread sits *ahead* of the file's beams, and each of those read the entry beside
## it — the hero truck's tyres came out with a 750 N yield and went flat on a 2.4 m/s wall.
static func _stress(wheel: Dictionary) -> Dictionary:
    return {
        "deform": wheel.get("deform", BeamDefaults.DEFAULT_DEFORM),
        "strength": wheel.get("strength", BeamDefaults.DEFAULT_BREAK),
        "plastic": wheel.get("plastic", BeamDefaults.DEFAULT_PLASTIC_COEF)}


## Any unit vector at right angles to `axis`. Which one does not matter: it only sets
## where ray zero lands on a circle that is about to be walked all the way round.
static func _perpendicular(axis: Vector3) -> Vector3:
    var seed: Vector3 = Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
    return axis.cross(seed).normalized()
