class_name FlareBuilder
extends RefCounted
## Turns a vehicle's parsed `flares` into lamps that exist in the scene.
##
## Each flare becomes a lens — a small emissive quad, which is what is seen when the lamp is
## looked at — and, for the lamps that throw light down the road, a real light. Both ride the
## flare's node triad, so they deform with the panel they are mounted on.
##
## Colour is taken from the type letter rather than from the flare's material. A mod's flare
## material is a sprite with a colour baked into it, and the hero truck reuses one material
## for lamps of three different colours; the letter is the vehicle telling us what the lamp is
## for, which is the thing worth believing.

## Lens colours per upstream flare type. Amber for indicators, red behind, white in front.
const COLOURS: Dictionary = {
    FlareRows.HEADLIGHT: Color(1.0, 0.97, 0.9),
    FlareRows.HIGH_BEAM: Color(1.0, 1.0, 1.0),
    FlareRows.FOG_LIGHT: Color(1.0, 0.9, 0.7),
    FlareRows.TAIL_LIGHT: Color(1.0, 0.1, 0.05),
    FlareRows.BRAKE_LIGHT: Color(1.0, 0.05, 0.02),
    FlareRows.REVERSE_LIGHT: Color(1.0, 1.0, 0.95),
    FlareRows.SIDELIGHT: Color(1.0, 0.65, 0.15),
    FlareRows.BLINKER_LEFT: Color(1.0, 0.55, 0.05),
    FlareRows.BLINKER_RIGHT: Color(1.0, 0.55, 0.05),
}
const DEFAULT_COLOUR: Color = Color(1.0, 0.95, 0.85)
## A flare's stated size is a sprite scale, not metres. The hero truck's headlights state 0.9
## and its tail lights 0.16, and this puts a 0.9 lens at 18 cm across, which is a headlight.
const LENS_METRES_PER_SIZE: float = 0.2
## Emission while the lamp is off: a lens still catches light, and a black disc on the front
## of a truck reads as a hole.
const LENS_EMISSION_OFF: float = 0.15
const LENS_EMISSION_ON: float = 6.0
## A headlight's cone. Wide enough to light the road either side, not so wide it is a bulb.
const SPOT_ANGLE_DEG: float = 38.0
const SPOT_RANGE_M: float = 45.0
const SPOT_ENERGY: float = 6.0


## Builds every lamp under `root`, in the space `render_frame` maps rig coordinates into.
## Returns the lamp holders, one per flare, in file order.
static func build(root: Node3D, truck: TruckParser, render_frame: Transform3D) -> Array[Node3D]:
    var lamps: Array[Node3D] = []
    var to_local: Transform3D = render_frame.affine_inverse()
    for index: int in truck.flares.size():
        var flare: Dictionary = truck.flares[index]
        var holder: Node3D = Node3D.new()
        holder.name = "Flare_%d_%s" % [index, flare["type"]]
        var colour: Color = COLOURS.get(flare["type"] as String, DEFAULT_COLOUR) as Color
        holder.add_child(_lens(flare, colour))
        if FlareRows.projects(flare):
            holder.add_child(_beam(colour))
        holder.transform = to_local * _placement(truck.nodes, flare)
        root.add_child(holder)
        lamps.append(holder)
    return lamps


## Moves every lamp to where its nodes now are.
static func apply_pose(
    lamps: Array[Node3D], truck: TruckParser, nodes: PackedVector3Array, actor: Transform3D
) -> void:
    var to_local: Transform3D = actor.affine_inverse()
    for i: int in mini(lamps.size(), truck.flares.size()):
        lamps[i].transform = to_local * _placement(nodes, truck.flares[i])


## Turns the lamps on or off. The lens stays visible either way; what changes is whether it
## is emitting and whether anything is being lit by it.
static func set_lit(lamps: Array[Node3D], truck: TruckParser, lit: bool) -> void:
    for i: int in mini(lamps.size(), truck.flares.size()):
        for child: Node in lamps[i].get_children():
            var light: Light3D = child as Light3D
            if light != null:
                light.visible = lit
                continue
            var lens: MeshInstance3D = child as MeshInstance3D
            if lens == null:
                continue
            var material: StandardMaterial3D = lens.material_override as StandardMaterial3D
            if material != null:
                material.emission_energy_multiplier = (
                    LENS_EMISSION_ON if lit else LENS_EMISSION_OFF
                )


## The lamp's frame: at its offset from the node triad, facing along the triad's normal.
static func _placement(nodes: PackedVector3Array, flare: Dictionary) -> Transform3D:
    var origin: Vector3 = FlareRows.position(nodes, flare)
    var normal: Vector3 = FlareRows.normal(nodes, flare)
    if normal.length_squared() == 0.0:
        return Transform3D(Basis.IDENTITY, origin)
    # Godot points a light and a quad's face down local -Z, so the lamp looks along its
    # normal when the frame's -Z is the normal.
    #
    # The up vector is chosen so that y is `right x normal` and not `normal x right`. Those
    # differ by a sign, and taking the wrong one gives a basis whose determinant is negative:
    # a mirrored frame, which points -Z along the normal and everything else inside out. It
    # measured as every lamp on the vehicle facing 0.98 of the way into the bodywork.
    var up: Vector3 = Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
    var right: Vector3 = up.cross(normal).normalized()
    return Transform3D(Basis(right, right.cross(normal), -normal), origin)


static func _lens(flare: Dictionary, colour: Color) -> MeshInstance3D:
    var size: float = (flare["size"] as float) * LENS_METRES_PER_SIZE
    var quad: QuadMesh = QuadMesh.new()
    quad.size = Vector2(size, size)
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = colour
    material.emission_enabled = true
    material.emission = colour
    material.emission_energy_multiplier = LENS_EMISSION_OFF
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    # Seen from behind a lamp is not there, rather than being a bright disc inside the wing.
    material.cull_mode = BaseMaterial3D.CULL_BACK
    var lens: MeshInstance3D = MeshInstance3D.new()
    lens.name = "Lens"
    lens.mesh = quad
    lens.material_override = material
    return lens


static func _beam(colour: Color) -> SpotLight3D:
    var light: SpotLight3D = SpotLight3D.new()
    light.name = "Beam"
    light.light_color = colour
    light.light_energy = SPOT_ENERGY
    light.spot_range = SPOT_RANGE_M
    light.spot_angle = SPOT_ANGLE_DEG
    light.shadow_enabled = false
    light.visible = false
    return light
