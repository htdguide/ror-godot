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
## and its tail lights 0.16, and this puts a 0.9 lens at 25 cm across, which is a headlight.
const LENS_METRES_PER_SIZE: float = 0.28
## How far the lens stands off the panel it is mounted on.
##
## A flare's own position is on the bodywork, and the mod draws its own lamp geometry there: a
## lens at exactly that point is inside the mod's dark plastic, which is what a session saw as
## lamps that light the road without lighting up themselves. Upstream draws its flares as sprites
## in front of the panel for the same reason.
const LENS_STANDOFF_M: float = 0.04
## How bright the glow is with the lamp off and on. Off is zero: an additive sprite that adds
## nothing is not there, which is what a lamp that is off looks like.
const LENS_EMISSION_OFF: float = 0.0
const LENS_EMISSION_ON: float = 2.4
## The glow sprite: how big across it is drawn compared with the lamp itself, how much of it is
## the bright core, and how strong the halo around that is.
const GLOW_SIZE_SCALE: float = 1.7
const GLOW_TEXTURE_PX: int = 64
const GLOW_CORE: float = 0.45
const GLOW_HALO: float = 0.55
## A headlight's cone. Wide enough to light the road either side, not so wide it is a bulb, and
## far enough to be a headlight: at 45 m and six units it lit a patch of ground in front of the
## bumper, which in daylight is indistinguishable from being off.
const SPOT_ANGLE_DEG: float = 32.0
const SPOT_RANGE_M: float = 110.0
const SPOT_ENERGY: float = 14.0
## How the cone falls off across its width and along its length. Both are how a headlight is
## told apart from a torch: bright in the middle, dim at the edge, and reaching.
const SPOT_ANGLE_ATTENUATION: float = 0.8
const SPOT_ATTENUATION: float = 1.3
## And whether the beams cast shadows. Only the projecting lamps do, so a vehicle has at most a
## pair of shadow-casting lights and the truck's own body stops its headlights lighting the cab.
const SPOT_SHADOWS: bool = true
## The lamps that do not project still light what they are mounted on: a brake light reddens the
## tailgate, an indicator throws amber on the wing. Small, short and cheap.
const GLOW_RANGE_M: float = 3.2
const GLOW_ENERGY: float = 2.4


## How hard the pedal has to be pressed before the brake lights come on, and how fast an
## indicator blinks. Upstream's own blink delay is per flare and in milliseconds; this is the
## default it uses when a row does not say.
const BRAKE_THRESHOLD: float = 0.08
const BLINK_PERIOD_S: float = 0.8


## The shared glow sprite, built on first use and never changed after.
##
## The one `static var` D0 allows, and it is allowed because it is a memo and not state: it is
## derived from constants, it is written once, and no observable behaviour depends on whether it
## was built by this gate or an earlier one. `static_state` knows about it by name — an
## exemption a human granted for a stated reason, not a pattern the lint waves through.
##
## It does outlive a gate container, which means one texture stays allocated for the life of the
## process. That is bounded at one and deliberate: rebuilding a 64 px radial gradient per
## container would be slower and would prove nothing.
static var _glow_sprite: Texture2D = null


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
        holder.set_meta("lamp_colour", colour)
        holder.add_child(_lens(flare, colour))
        if FlareRows.projects(flare):
            holder.add_child(_beam(colour))
        else:
            holder.add_child(_glow(colour))
        holder.transform = to_local * _placement(truck.nodes, flare)
        root.add_child(holder)
        lamps.append(holder)
    # Built dark. A lamp's beam is a Light3D and a Light3D is visible the moment it exists, so a
    # vehicle whose lights nobody has switched on would otherwise spawn with its headlights on.
    set_lit(lamps, truck, false)
    return lamps


## Moves every lamp to where its nodes now are.
static func apply_pose(
    lamps: Array[Node3D], truck: TruckParser, nodes: PackedVector3Array, actor: Transform3D
) -> void:
    var to_local: Transform3D = actor.affine_inverse()
    for i: int in mini(lamps.size(), truck.flares.size()):
        lamps[i].transform = to_local * _placement(nodes, truck.flares[i])


## Turns every lamp on or off together. Kept for the checks that only care whether a lamp can
## light at all; a driven vehicle uses `apply_state`.
static func set_lit(lamps: Array[Node3D], truck: TruckParser, lit: bool) -> void:
    for i: int in mini(lamps.size(), truck.flares.size()):
        _set_lamp(lamps[i], lit)


## Lights each lamp by what the vehicle is doing: headlights with the switch, brake lights with
## the pedal, reversing lights with the gear, indicators with the stalk and the clock.
##
## `state` is {"headlights", "brake", "reverse", "left", "right", "seconds"}. The types are
## upstream's own letters, read by `FlareRows`; what is on when is this project's reading of them,
## and it is here rather than in the parser because it is a rule about driving rather than about
## the file format.
static func apply_state(lamps: Array[Node3D], truck: TruckParser, state: Dictionary) -> void:
    var headlights: bool = bool(state.get("headlights", false))
    var braking: bool = float(state.get("brake", 0.0)) > BRAKE_THRESHOLD
    var reversing: bool = bool(state.get("reverse", false))
    var seconds: float = float(state.get("seconds", 0.0))
    var blink: bool = fmod(seconds, BLINK_PERIOD_S) < BLINK_PERIOD_S * 0.5
    for i: int in mini(lamps.size(), truck.flares.size()):
        var type: String = truck.flares[i]["type"] as String
        var lit: bool = false
        match type:
            FlareRows.HEADLIGHT, FlareRows.HIGH_BEAM, FlareRows.FOG_LIGHT, FlareRows.TAIL_LIGHT, \
            FlareRows.SIDELIGHT, FlareRows.DASHBOARD:
                lit = headlights
            FlareRows.BRAKE_LIGHT:
                # A tail light that also brakes: on with the switch, brighter on the pedal. With
                # one emission level to give it, the pedal wins.
                lit = braking or headlights
            FlareRows.REVERSE_LIGHT:
                lit = reversing
            FlareRows.BLINKER_LEFT:
                lit = bool(state.get("left", false)) and blink
            FlareRows.BLINKER_RIGHT:
                lit = bool(state.get("right", false)) and blink
            _:
                lit = false
        _set_lamp(lamps[i], lit)


static func _set_lamp(lamp: Node3D, lit: bool) -> void:
    for child: Node in lamp.get_children():
        var light: Light3D = child as Light3D
        if light != null:
            light.visible = lit
            continue
        var lens: MeshInstance3D = child as MeshInstance3D
        if lens == null:
            continue
        var material: StandardMaterial3D = lens.material_override as StandardMaterial3D
        if material == null:
            continue
        # The glow's own colour carries its brightness: additive, so off is nothing at all.
        var colour: Color = material.albedo_color
        var energy: float = LENS_EMISSION_ON if lit else LENS_EMISSION_OFF
        material.albedo_color = _lamp_colour(lamp) * energy


## What colour a lamp glows, kept on the holder so that turning it off and on again does not
## fade it away: the glow's own colour is scaled by its brightness, and a colour scaled to
## nothing has no hue left to scale back up.
static func _lamp_colour(lamp: Node3D) -> Color:
    return lamp.get_meta("lamp_colour", DEFAULT_COLOUR) as Color


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
    var size: float = (flare["size"] as float) * LENS_METRES_PER_SIZE * GLOW_SIZE_SCALE
    var quad: QuadMesh = QuadMesh.new()
    quad.size = Vector2(size, size)
    var material: StandardMaterial3D = StandardMaterial3D.new()
    # A glow, not a panel.
    #
    # Two earlier attempts are why this is what it is. An unshaded quad draws its albedo and
    # ignores emission, so the lamp looked identical on and off — 0.723 display luma in both
    # states. A lit quad with a dark albedo and emission did switch, and a session saw the thing
    # it actually is: a square standing proud of the headlight. So the lens is additive with a
    # radial falloff — bright in the middle, nothing at the edge, and nothing at all when it is
    # off, because adding zero adds nothing. That is also what upstream draws: a flare sprite.
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
    material.albedo_texture = _glow_texture()
    material.albedo_color = colour * LENS_EMISSION_OFF
    material.disable_receive_shadows = true
    # Seen from behind a lamp is not there, rather than being a bright disc inside the wing.
    material.cull_mode = BaseMaterial3D.CULL_BACK
    var lens: MeshInstance3D = MeshInstance3D.new()
    lens.name = "Lens"
    lens.mesh = quad
    lens.material_override = material
    lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    # Out along the lamp's own normal, which the holder's -Z is — and turned to face that way.
    #
    # A QuadMesh faces its own +Z, and the holder is built with -Z along the lamp's normal, so a
    # lens added without this turn shows its back to the world: culled from outside the vehicle
    # and visible from inside it.
    lens.transform = Transform3D(
        Basis(Vector3.UP, PI), Vector3(0.0, 0.0, -LENS_STANDOFF_M)
    )
    return lens


## The glow sprite every lens is drawn with: white in the middle, fading to nothing at the edge.
##
## Built once and shared. A radial falloff rather than a disc, because an additive disc has an
## edge and an edge is what makes a lamp look like a sticker.
static func _glow_texture() -> Texture2D:
    if _glow_sprite != null:
        return _glow_sprite
    var image: Image = Image.create_empty(
        GLOW_TEXTURE_PX, GLOW_TEXTURE_PX, false, Image.FORMAT_RGBAF
    )
    var centre: float = float(GLOW_TEXTURE_PX - 1) * 0.5
    for y: int in GLOW_TEXTURE_PX:
        for x: int in GLOW_TEXTURE_PX:
            var away: float = Vector2(float(x) - centre, float(y) - centre).length() / centre
            # A bright core inside a wider halo, which is what a lamp at night looks like.
            var core: float = pow(clampf(1.0 - away / GLOW_CORE, 0.0, 1.0), 2.0)
            var halo: float = pow(clampf(1.0 - away, 0.0, 1.0), 3.0)
            var value: float = clampf(core + halo * GLOW_HALO, 0.0, 1.0)
            image.set_pixel(x, y, Color(value, value, value, value))
    if not image.is_compressed():
        image.generate_mipmaps()
    _glow_sprite = ImageTexture.create_from_image(image)
    return _glow_sprite


static func _beam(colour: Color) -> SpotLight3D:
    var light: SpotLight3D = SpotLight3D.new()
    light.name = "Beam"
    light.light_color = colour
    light.light_energy = SPOT_ENERGY
    light.spot_range = SPOT_RANGE_M
    light.spot_angle = SPOT_ANGLE_DEG
    light.spot_angle_attenuation = SPOT_ANGLE_ATTENUATION
    light.spot_attenuation = SPOT_ATTENUATION
    light.shadow_enabled = SPOT_SHADOWS
    light.visible = false
    return light


## What a lamp that does not project still does: light its own corner of the vehicle.
static func _glow(colour: Color) -> OmniLight3D:
    var light: OmniLight3D = OmniLight3D.new()
    light.name = "Glow"
    light.light_color = colour
    light.light_energy = GLOW_ENERGY
    light.omni_range = GLOW_RANGE_M
    light.shadow_enabled = false
    light.visible = false
    return light
