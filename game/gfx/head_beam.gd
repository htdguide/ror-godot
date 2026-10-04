class_name HeadBeam
extends RefCounted
## The light a vehicle's forward lamps actually throw, as a real beam rather than a cone of even
## brightness.
##
## **A headlight is not a torch.** A low beam has a flat cut-off along its top edge so that it
## lights the road without lighting the eyes of whoever is coming the other way, a hot spot a
## little below that line, and a wide dim spill in front of the bumper. A main beam has no
## cut-off and reaches four times as far down a narrower cone. A fog lamp is a wide low bar. None
## of that can be said with an angle and a brightness, so each kind carries a projector — a
## texture the light is seen through — and the shape is in the texture.
##
## **Brightness is stated in candela, which is how a lamp is specified.** A European low beam is
## around twenty thousand candela at its hot spot and a main beam up to seventy-five thousand;
## those are the numbers on the box, and they are what makes a beam read as a beam against a
## moonlit road. Godot takes a spot light's output as lumens over the whole sphere, so the
## conversion is here: `lumens = candela x 4 pi`.
##
## Upstream's own figures are the shape of this, from `ActorSpawner.cpp`: a headlight is a
## spotlight of 200 range with a 35 degree inner and 45 degree outer cone, a main beam the same
## cone at 400, and neither casts a shadow. Ogre states a full cone where Godot states the half
## angle, so 45 there is 22.5 here, and this is a little wider because the cut-off in the
## projector, not the cone edge, is what shapes a low beam.

## What each kind of forward lamp is, in the units a lamp is sold in.
##
## `candela` is the hot spot, `angle_deg` the half-angle of the cone it lives in, `range_m` how
## far it is allowed to reach, and `tilt_deg` how far below the lamp's own axis it is aimed — a
## low beam points at the road a few car lengths ahead, not at the horizon.
const KINDS: Dictionary = {
    "low": {
        "candela": 22000.0,
        "angle_deg": 30.0,
        "range_m": 150.0,
        "tilt_deg": 1.4,
        "colour": Color(1.0, 0.94, 0.85),
    },
    "high": {
        "candela": 62000.0,
        "angle_deg": 19.0,
        "range_m": 320.0,
        "tilt_deg": 0.2,
        "colour": Color(1.0, 0.97, 0.93),
    },
    "fog": {
        "candela": 9000.0,
        "angle_deg": 38.0,
        "range_m": 55.0,
        "tilt_deg": 3.2,
        "colour": Color(1.0, 0.89, 0.7),
    },
}
## Which kind each of upstream's forward flare letters is.
const OF_TYPE: Dictionary = {
    FlareRows.HEADLIGHT: "low",
    FlareRows.HIGH_BEAM: "high",
    FlareRows.FOG_LIGHT: "fog",
}
## How the cone falls off across its width and along its length. The width figure is low because
## the projector already shapes the beam; left higher, the two fades multiply and the hot spot is
## the only thing left.
const ANGLE_ATTENUATION: float = 0.35
const ATTENUATION: float = 1.2
## Headlights cast a shadow, and they have to.
##
## **A projector is only sampled on a light that has its shadow map.** Upstream turns headlight
## shadows off and this did too, and the result was a lamp at a quarter of a million lumens that
## lit nothing whatever: with the projector attached and shadows off, the road ahead measured
## 0.2150 lit and 0.2150 dark, the same frame to four decimals. Switching shadows on with the
## same projector took it to 0.3774 on low beam and 0.7006 on main.
##
## It is also the better picture. A beam that is stopped by a pole throws the pole across the
## road, which is most of what driving at night looks like, and two shadow maps for the two
## forward lamps is what it costs.
const SHADOWS: bool = true
## How far the shadow is pushed off the surface that casts it. A lamp sits in its own grille and
## a beam that starts inside the bodywork shadows itself into darkness without this.
const SHADOW_BIAS: float = 0.04
const SHADOW_NORMAL_BIAS: float = 1.2
## The projector texture. Small, because it is a beam pattern and not a picture.
const COOKIE_PX: int = 128
## Where the hot spot sits in the pattern, as a fraction of the texture, and how wide it is.
const HOT_SPOT_V: float = 0.58
const HOT_SPOT_WIDTH: float = 0.30
const HOT_SPOT_HEIGHT: float = 0.17
## The low beam's cut-off: the line above which it keeps only a trace of its light, how much of
## that trace is left, and how softly it fades into it. Not zero and not sudden — a real cut-off
## scatters above the line, and a hard edge reads as a stencil rather than as a beam.
const CUT_OFF_V: float = 0.46
const ABOVE_CUT_OFF: float = 0.07
const CUT_OFF_SOFT: float = 0.10
## How far the cut-off rises across the half of the beam on the kerb side, so that a sign at the
## roadside is lit and an oncoming driver is not. Gentle: a step that shows as a staircase on
## the road is worse than no step at all.
const KERB_RISE: float = 0.07
## **The pattern is a square texture and a beam is not square.** A spot light samples its
## projector across the whole image, corners included, so a pattern that still has light at its
## edge is thrown as a rectangle with hard sides — reported from a window as "a weird shape how
## it lights", and it was the texture's own border drawn on the road. Everything past this radius
## is dark, and the last tenth of it fades, so what shapes the beam is the pattern and not the
## image it is stored in.
const PATTERN_RADIUS: float = 0.48
const PATTERN_FADE: float = 0.12


## One forward lamp, dark, for a flare of this type. Null when the type does not project.
static func build(flare_type: String) -> SpotLight3D:
    if not OF_TYPE.has(flare_type):
        return null
    var light: SpotLight3D = SpotLight3D.new()
    light.name = "Beam"
    light.shadow_enabled = SHADOWS
    light.shadow_bias = SHADOW_BIAS
    light.shadow_normal_bias = SHADOW_NORMAL_BIAS
    light.spot_angle_attenuation = ANGLE_ATTENUATION
    light.spot_attenuation = ATTENUATION
    light.visible = false
    light.set_meta("beam_kind", OF_TYPE[flare_type])
    aim(light, OF_TYPE[flare_type] as String)
    return light


## Points a lamp and sets it to one of the kinds, keeping everything else it is.
##
## This is also the main-beam switch. A vehicle that declares `h` flares has separate lamps for
## it and they are simply switched on; one that declares only `f` — which is most of them, the
## hero truck included — has its low beams put on the main-beam pattern instead, which is what a
## two-filament bulb does.
static func aim(light: SpotLight3D, kind: String) -> void:
    var beam: Dictionary = KINDS.get(kind, KINDS["low"]) as Dictionary
    light.light_color = beam["colour"] as Color
    # A spot's output in Godot is lumens spread over the whole sphere, and a lamp is specified
    # by the candela at its hot spot. One is the other times the sphere.
    light.light_intensity_lumens = (beam["candela"] as float) * 4.0 * PI
    light.light_energy = 1.0
    light.spot_range = beam["range_m"] as float
    light.spot_angle = beam["angle_deg"] as float
    light.light_projector = _cookie(kind)
    # Aimed below its own axis. The lamp's axis is the bodywork's normal, and a headlight is
    # aimed at the road rather than along the panel it is set into.
    light.rotation = Vector3(-deg_to_rad(beam["tilt_deg"] as float), 0.0, 0.0)
    light.set_meta("beam_kind", kind)


## Which kind a lamp is set to now.
static func kind_of(light: SpotLight3D) -> String:
    return light.get_meta("beam_kind", "low") as String


## The beam pattern, as a texture the lamp is seen through.
##
## Built per lamp rather than shared. A 128 px pattern is a tenth of a millisecond to make and
## there are four of them on a vehicle; a shared one would be process-global state, which this
## project does not keep without a human exempting it by name.
static func _cookie(kind: String) -> ImageTexture:
    # Eight bits and no mipmaps.
    #
    # **A float image with a generated mip chain sampled as black and put the lamp out.** Godot
    # samples a light projector through the mip chain, and a `FORMAT_RGBAF` texture built at run
    # time came back with nothing in it: the beams were on, pointed the right way, at a quarter
    # of a million lumens, and lit nothing at all. Measured by removing the projector, which
    # took the road ahead from 0.24 to 0.95.
    var image: Image = Image.create_empty(COOKIE_PX, COOKIE_PX, false, Image.FORMAT_RGBA8)
    for y: int in COOKIE_PX:
        var v: float = (float(y) + 0.5) / float(COOKIE_PX)
        for x: int in COOKIE_PX:
            var u: float = (float(x) + 0.5) / float(COOKIE_PX)
            var value: float = _pattern(kind, u, v)
            image.set_pixel(x, y, Color(value, value, value, 1.0))
    return ImageTexture.create_from_image(image)


## How bright the beam is at one point of its own pattern, with the lamp's axis at the middle.
##
## A main beam is a hot spot in a soft surround and nothing else. A low beam and a fog lamp have
## the cut-off, which is the whole point of them: above the line they keep a trace, below it they
## light the road. The low beam's line steps up across the kerb side. Everything is then taken to
## nothing at the edge of the circle the square image holds.
static func _pattern(kind: String, u: float, v: float) -> float:
    var hot_v: float = 0.5 if kind == "high" else HOT_SPOT_V
    var across: float = (u - 0.5) / HOT_SPOT_WIDTH
    var down: float = (v - hot_v) / HOT_SPOT_HEIGHT
    var spot: float = exp(-(across * across + down * down))
    # The spill: everything the lamp throws that is not the hot spot, falling off from the middle.
    var away: float = Vector2(u - 0.5, (v - hot_v) * 1.3).length()
    var spill: float = pow(clampf(1.0 - away / PATTERN_RADIUS, 0.0, 1.0), 2.0)
    var value: float = clampf(spot + spill * 0.6, 0.0, 1.0)
    if kind != "high":
        # The cut-off, stepped up on the kerb side so that the verge is lit and an oncoming
        # driver is not, and faded into rather than cut.
        var line: float = CUT_OFF_V - KERB_RISE * smoothstep(0.5, 0.72, u)
        value *= lerpf(
            1.0, ABOVE_CUT_OFF, clampf((line - v) / CUT_OFF_SOFT, 0.0, 1.0)
        )
    # And nothing at all outside the circle, so the square the pattern is stored in is never
    # what the road sees.
    var radius: float = Vector2(u - 0.5, v - 0.5).length()
    return value * (1.0 - smoothstep(PATTERN_RADIUS - PATTERN_FADE, PATTERN_RADIUS, radius))
