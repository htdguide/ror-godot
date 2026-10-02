class_name WheelRig
extends RefCounted
## Generates the tread nodes and beams a wheel section only implies.
##
## A `meshwheels2` row names two axle nodes and a tyre radius; the nodes the tyre actually
## stands on are generated from that, not written in the file. Without them the lowest
## node of the whole vehicle is an axle, ground contact happens there, and the vehicle is
## drawn sunk into the ground by the tyre radius — measured at 0.34 m on the hero truck.
##
## Follows upstream's `BuildWheelObjectAndNodes` + `BuildWheelBeams`: 2·rays nodes per
## wheel, laid as a zig-zag alternating between the two axle planes, and 8·rays beams.
##
## Generated nodes are appended after the file's own, so every index the file stated —
## beams, flexbody forsets, cameras, cab triangles — keeps its meaning.

## Used only when a wheel row carries no recorded beam defaults, which a hand-built test
## rig may not. A real file always states them: upstream's rim beams for meshwheels2 come
## from the beam defaults rather than the wheel's own spring, which is the tyre's, and
## falling back to the tyre value makes the rim as soft as the sidewall so the wheel folds
## up under load.
const RIM_SPRING_FALLBACK: float = 4000000.0
const RIM_DAMP_FALLBACK: float = 150.0


## Parses a `meshwheels2` row: "tire_radius, rim_radius, width, rays, node1, node2, snode,
## braked, propulsed, arm, mass, spring, damping, side, meshname, material". Lives here
## rather than in the parser because the tread generated below is the only thing that
## reads most of these fields.
##
## `braked`, `propulsed` and `arm` are what make a wheel a driven wheel rather than a
## castor. The hero truck states `4, 1, 8` on its front pair and `1, 1, 15` on its rear:
## four-wheel drive, brakes all round, and a reference arm node per wheel for the reaction
## torque to push against. Dropped, every wheel rolls freely and no amount of engine makes
## the rig move.
## **A `flexbodywheels` row parses here, but its rig is not built here yet, and the difference is
## structural.** Upstream gives a flexbody wheel `num_rays * 4` nodes and `num_rays * 20` beams —
## eight rim beams, ten tyre beams and two support beams per ray — against a mesh wheel's
## `num_rays * 2` nodes and `num_rays * 8` beams (`ActorSpawner.cpp`, the spawn budget). It is a
## two-ring structure: a rim ring and a tyre ring, with the tyre sprung against the rim, which is
## why the row carries two spring and damping pairs instead of one.
##
## Built as a mesh wheel it gets half the nodes and two fifths of the beams, and what that looks
## like from the driver's seat is a wheel that wobbles and does not sit on its suspension —
## reported from the window exactly that way. Parsing the row correctly is what lets such a
## vehicle have wheels at all; giving it the right rig is a port of
## `BuildWheelObjectAndNodes` and its flexbody variant, and it has not been done.
##
## **`flexbodywheels` is not the same row, and reading it as one is a quiet disaster.** The two
## agree for the first eleven fields and then diverge: a mesh wheel carries
## `spring, damping, side, mesh, material` where a flexbody wheel carries
## `tyre spring, tyre damp, rim spring, rim damp, side, rim mesh, tyre mesh`
## (`RigDef_Parser.cpp`, `_ParseBaseMeshWheel` against `ParseFlexBodyWheel`).
##
## Read with the wrong layout, the Mazda 626 took its side from a rim stiffness of 320000, its rim
## mesh from a damping figure of 40, and its material from the letter `l`. What that looks like on
## screen is white tyres with no rims and a car sitting on its bump stops, which is exactly how it
## was reported — three symptoms, one misread row.
static func parse_row(
    fields: PackedStringArray, id_to_index: Dictionary, flexbody: bool = false
) -> Dictionary:
    var needed: int = 16 if not flexbody else 16
    if fields.size() < needed:
        return {"error": "row has %d fields, expected at least %d" % [fields.size(), needed]}
    var node1: int = int(id_to_index.get(fields[4], -1))
    var node2: int = int(id_to_index.get(fields[5], -1))
    if node1 < 0 or node2 < 0:
        return {"error": "row references an unknown node"}
    # A flexbody wheel states the tyre and the rim separately; the rim is the stiffer pair and is
    # what the mesh wheel's single pair corresponds to.
    var spring: float = fields[11].to_float()
    var damping: float = fields[12].to_float()
    var side: String = fields[13].to_lower()
    var mesh_name: String = fields[14]
    var material_name: String = fields[15]
    var tyre_mesh: String = ""
    if flexbody:
        side = fields[15].to_lower()
        mesh_name = fields[16] if fields.size() > 16 else ""
        # Field 17 is the **tyre mesh**, not a material: a flexbody wheel draws its tyre as
        # geometry where a mesh wheel sweeps one and paints it. Passing it on as a material name
        # is what left the Mazda with white tyres after its rims came back.
        tyre_mesh = fields[17] if fields.size() > 17 else ""
        material_name = ""
    return {
        "error": "",
        "tire_radius": fields[0].to_float(),
        "rim_radius": fields[1].to_float(),
        "width": fields[2].to_float(),
        "rays": fields[3].to_int(),
        "node1": node1,
        "node2": node2,
        "braked": fields[7].to_int(),
        "propulsed": fields[8].to_int(),
        # A wheel with no resolvable arm node falls back to its own axle, which upstream
        # also does: the reaction then has no lever and is skipped rather than misapplied.
        "arm_node": int(id_to_index.get(fields[9], -1)),
        "mass": fields[10].to_float(),
        "spring": spring,
        "damping": damping,
        "side": side,
        "mesh": mesh_name,
        "material": material_name,
        "tyre_mesh": tyre_mesh,
        # Filled in by `generate` once the tread exists.
        "first_tread": -1,
        "tread_count": 0,
    }


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
    for i: int in rays:
        var o: int = outer[i]
        var n: int = inner[i]
        var next_o: int = outer[(i + 1) % rays]
        var next_n: int = inner[(i + 1) % rays]
        # Tyre: each tread node braced to both axle nodes, so load crosses the sidewall.
        _add_beam(truck, axis_a, o, tyre_spring, tyre_damp)
        _add_beam(truck, axis_b, n, tyre_spring, tyre_damp)
        _add_beam(truck, axis_b, o, tyre_spring, tyre_damp)
        _add_beam(truck, axis_a, n, tyre_spring, tyre_damp)
        # Rim: the tread ring's own hoop and diagonal stiffness.
        _add_beam(truck, o, n, rim_spring, rim_damp)
        _add_beam(truck, o, next_o, rim_spring, rim_damp)
        _add_beam(truck, n, next_n, rim_spring, rim_damp)
        _add_beam(truck, n, next_o, rim_spring, rim_damp)


static func _add_node(
    truck: TruckParser, position: Vector3, mass: float, friction: float
) -> int:
    var index: int = truck.nodes.size()
    truck.nodes.append(position)
    # Generated nodes carry an id no file can state, so a later reference to a numeric id
    # can never resolve to one of these by accident.
    truck.node_ids.append("@wheel%d" % index)
    truck.node_mass.append(mass)
    truck.node_friction.append(friction)
    return index


static func _add_beam(
    truck: TruckParser, a: int, b: int, spring: float, damp: float
) -> void:
    truck.beams.append(a)
    truck.beams.append(b)
    truck.beam_spring.append(spring)
    truck.beam_damp.append(damp)


## Any unit vector at right angles to `axis`. Which one does not matter: it only sets
## where ray zero lands on a circle that is about to be walked all the way round.
static func _perpendicular(axis: Vector3) -> Vector3:
    var seed: Vector3 = Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
    return axis.cross(seed).normalized()
