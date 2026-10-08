extends GateBase
## Switching to a weather gives the same world as building with it.
##
## **Reported from the window:** cycling the weather at night left a scene that was still partly
## lit by noon, and the HUD label named the weather before last. The cause was that the window
## applied weather itself — aiming the sun, setting its energy trim and colour, and changing two
## environment fields — while `BlockoutWorld.build` applied far more. Three things were never
## switched at all:
##
## - **`light_intensity_lux`**, which under physical light units is what actually sets a light's
##   brightness. The window set only `light_energy`, the trim on top, so the sun stayed at a noon
##   100 000 lux through every preset and barely changed.
## - **The fill**, which was never touched, so a 12 000 lux cool light kept burning through a
##   night preset — with its own shadow, which is why the dark presets looked strangest.
## - **The sky**, never rebuilt, so the atmosphere stayed as the world was first built.
##
## There is now one function, `BlockoutWorld.apply_weather`, called by the build and by the
## window. This gate is what stops them drifting apart again: it builds a world under one preset,
## builds another under a different one and switches it, and requires the two to agree on every
## property a weather preset can set.
##
## **It compares two worlds rather than checking a list of fields against expected values.** A
## list would have to be kept in step with the presets by hand, which is the same class of
## mistake as the bug — one place knowing something another place does not. Two worlds built the
## two ways either match or they do not, whatever a preset learns to say next.
##
## **What it therefore cannot catch, stated plainly:** an omission common to both paths. Deleting
## a line from `_grade_sun` breaks the build and the switch identically, and two identically
## wrong worlds compare equal — verified, not assumed. This gate guards the seam between building
## and switching, which is where the reported bug lived; it is not a check that any particular
## property is applied at all.

const SHOT: String = "diag_origin"
## Switched **from** a preset that differs in kind, not just in degree: `spike_black` has no
## atmosphere at all — a flat background colour and a colour ambient — where `noon_clear` has a
## physical sky lighting the scene from its own irradiance. Chosen after `golden_dusk` turned out
## to share every environment field compared here with `noon_clear`, which left the environment
## half of this gate passing no matter what was broken.
const FROM: String = "spike_black"
const TO: String = "noon_clear"
## Light directions are compared as an angle. Nothing here should differ at all, so this is float
## slack rather than a tolerance: both worlds run the same arithmetic on the same preset.
const MAX_ANGLE_DEG: float = 0.01
const MAX_RELATIVE: float = 0.0001


static func meta() -> Dictionary:
    return {
        "name": "a_weather_switch_is_a_weather",
        "proves": "switching a built world to a weather preset leaves it identical to a world built with that preset",
        "builds_on": ["smoke"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "every light and environment property a preset sets agrees within %.4f relative,"
            % MAX_RELATIVE + " and light directions within %.2f degrees" % MAX_ANGLE_DEG
        ),
        "why": (
            "the window applied weather with its own code and applied less of it than the build"
            + " did: never `light_intensity_lux`, which is the whole of a light's brightness"
            + " under physical units, never the fill, and never the sky. Cycling to a night"
            + " preset left a 12 000 lux cool fill burning and a sun still at noon."
        ),
        "budget_s": 60.0,
        "needs_gpu": true,
        "milestone": "D0",
    }


func run(harness: Node) -> Dictionary:
    # The reference world comes from the harness, so it is **in the scene tree**. That is not a
    # detail: `look_at_from_position` does nothing on a detached node, so two worlds built outside
    # the tree both kept an unaimed light pointing down -Z and compared equal no matter what was
    # broken. A first version of this gate did exactly that and passed with the fill deliberately
    # left unswitched.
    var err: String = harness.setup_for(SHOT, TO)
    if err != "":
        return fail(err)
    var built: Node3D = harness.world

    var switched: Node3D = BlockoutWorld.build(WeatherCfg.get_preset(FROM), true, false)
    built.add_child(switched)
    BlockoutWorld.apply_weather(switched, WeatherCfg.get_preset(TO), false)

    var problems: PackedStringArray = PackedStringArray()
    for light_name: String in ["Sun", "Fill"]:
        problems.append_array(_compare_light(built, switched, light_name))
    problems.append_array(_compare_environment(built, switched))

    built.remove_child(switched)
    switched.queue_free()
    if not problems.is_empty():
        return fail(
            "a world switched from %s to %s is not a world built as %s: %s"
            % [FROM, TO, TO, "; ".join(problems)],
            problems.size()
        )
    return ok(
        "a world switched from %s to %s matches one built as %s on every light and environment"
        % [FROM, TO, TO] + " property a preset sets",
        0
    )


func _compare_light(built: Node3D, switched: Node3D, light_name: String) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    var a: DirectionalLight3D = built.get_node_or_null(NodePath(light_name)) as DirectionalLight3D
    var b: DirectionalLight3D = (
        switched.get_node_or_null(NodePath(light_name)) as DirectionalLight3D
    )
    if a == null or b == null:
        out.append("%s is missing from one of the two worlds" % light_name)
        return out
    if a.visible != b.visible:
        out.append("%s is %s when built and %s when switched"
            % [light_name, "on" if a.visible else "off", "on" if b.visible else "off"])
    out.append_array(_same(light_name, "lux", a.light_intensity_lux, b.light_intensity_lux))
    out.append_array(_same(light_name, "energy", a.light_energy, b.light_energy))
    out.append_array(_same(light_name, "shadow opacity", a.shadow_opacity, b.shadow_opacity))
    out.append_array(
        _same(light_name, "angular size", a.light_angular_distance, b.light_angular_distance)
    )
    for channel: int in 3:
        out.append_array(_same(
            light_name, "colour component %d" % channel,
            [a.light_color.r, a.light_color.g, a.light_color.b][channel],
            [b.light_color.r, b.light_color.g, b.light_color.b][channel]
        ))
    var apart: float = rad_to_deg(
        (-a.global_basis.z).normalized().angle_to((-b.global_basis.z).normalized())
    )
    if apart > MAX_ANGLE_DEG:
        out.append("%s points %.3f degrees apart" % [light_name, apart])
    return out


func _compare_environment(built: Node3D, switched: Node3D) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    var a: WorldEnvironment = built.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    var b: WorldEnvironment = switched.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    if a == null or b == null or a.environment == null or b.environment == null:
        out.append("one of the two worlds has no environment")
        return out
    if a.environment.background_mode != b.environment.background_mode:
        out.append("background mode %d against %d"
            % [a.environment.background_mode, b.environment.background_mode])
    if a.environment.ambient_light_source != b.environment.ambient_light_source:
        out.append("ambient source %d against %d"
            % [a.environment.ambient_light_source, b.environment.ambient_light_source])
    for pair: Array in [
        ["background colour", a.environment.background_color, b.environment.background_color],
        ["ambient colour", a.environment.ambient_light_color, b.environment.ambient_light_color],
    ]:
        var first: Color = pair[1] as Color
        var second: Color = pair[2] as Color
        for channel: int in 3:
            out.append_array(_same(
                "environment", "%s component %d" % [pair[0], channel],
                [first.r, first.g, first.b][channel], [second.r, second.g, second.b][channel]
            ))
    out.append_array(_same(
        "environment", "ambient energy",
        a.environment.ambient_light_energy, b.environment.ambient_light_energy
    ))
    out.append_array(_same(
        "environment", "sky contribution",
        a.environment.ambient_light_sky_contribution,
        b.environment.ambient_light_sky_contribution
    ))
    out.append_array(_compare_sky(a.environment.sky, b.environment.sky))
    return out


## The sky, which the window never rebuilt at all: same kind of material, same brightness, same
## atmosphere where it has one.
func _compare_sky(a: Sky, b: Sky) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    if (a == null) != (b == null):
        out.append("one world has a sky and the other does not")
        return out
    if a == null:
        return out
    var first: Material = a.sky_material
    var second: Material = b.sky_material
    if first == null or second == null or first.get_class() != second.get_class():
        out.append("sky material is %s against %s"
            % [first.get_class() if first != null else "none",
               second.get_class() if second != null else "none"])
        return out
    # **This project's own sky is a `ShaderMaterial`, and it has no `energy_multiplier`.** Since the
    # daylight skies became photographs every weather with an `hdri` builds one, `get()` answered
    # null for both, and `_same` refused the null with a script error that nobody saw — the suite
    # keeps result lines, not stderr — so the sky's energy was never compared and the gate passed
    # on the rest. The shader's own uniform is `sky_energy`.
    var first_energy: Variant = (
        (first as ShaderMaterial).get_shader_parameter("sky_energy") if first is ShaderMaterial
        else first.get("energy_multiplier")
    )
    var second_energy: Variant = (
        (second as ShaderMaterial).get_shader_parameter("sky_energy") if second is ShaderMaterial
        else second.get("energy_multiplier")
    )
    if first_energy == null or second_energy == null:
        out.append("the sky states no energy this gate knows how to read (%s)" % first.get_class())
    else:
        out.append_array(_same("sky", "energy", float(first_energy), float(second_energy)))
    if first is PhysicalSkyMaterial:
        out.append_array(_same(
            "sky", "turbidity",
            (first as PhysicalSkyMaterial).turbidity, (second as PhysicalSkyMaterial).turbidity
        ))
    return out


## Two numbers that should be the same number.
func _same(owner: String, what: String, built: float, switched: float) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    var scale: float = maxf(absf(built), 0.000001)
    if absf(built - switched) / scale > MAX_RELATIVE:
        out.append("%s %s is %.4f when built and %.4f when switched"
            % [owner, what, built, switched])
    return out
