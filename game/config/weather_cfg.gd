class_name WeatherCfg
extends RefCounted
## Time-of-day and weather presets. Data only.
##
## A preset is selectable from the command line, so any gate can be run under any
## lighting without a second scene. M0 defines only what a blockout world needs;
## M2 fills in the full set once there is a sky, fog and PBR materials to drive.
##
## Keys:
##   sun_from       Vector3 direction from the scene toward the sun
##   sun_energy     float directional light energy
##   sun_color      Color directional light colour
##   ambient_energy float flat ambient energy, replaced by sky IBL at M2
##   bg_color       Color clear colour, replaced by a sky at M2
##   iso, f_stop,   the photographer's three numbers. Under physical light units these are the
##   shutter_s      whole of the exposure, so an hour of the day that states its light in lux
##                  has to state the exposure that light was metered for: a scene lit by a full
##                  moon through a daylight exposure is black whatever its headlights do, which
##                  is exactly how "the headlights do not work at night" was reported.
##   fog_density,   the distance haze. A pale grey daylight haze over a night sky is a grey
##   fog_colour     ceiling with stars behind it.
##   volumetric     whether the air itself catches light. A headlight beam is only visible as a
##                  shaft when there is something in the air to scatter it.

const PRESETS: Dictionary = {
    "noon_clear": {
        # Lit by a physical sky rather than a flat colour, so surfaces have something to
        # reflect and shadows are filled by sky light instead of a constant.
        "physical_sky": true,
        "sky_energy": 1.0,
        # High and over the camera's shoulder, so the side being looked at is the side
        # being lit. A sun behind the subject makes every judgement about materials a
        # judgement about shadow instead.
        "sun_from": Vector3(0.55, 0.78, 0.62),
        # A clear midday sun is bright, and the sky fills the shadows on its own. With a
        # physical sky the ambient term is the sky's own irradiance rather than a flat
        # colour, so it runs at full strength instead of being dialled down.
        "sun_energy": 1.1,
        "sun_color": Color(1.0, 0.97, 0.92),
        "ambient_energy": 1.0,
        "bg_color": Color(0.42, 0.55, 0.72),
    },
    # Night, by a full moon. The sun is the moon: a directional light of about two lux, cool
    # rather than warm, from high and behind the camera's shoulder.
    #
    # **The exposure is part of the hour.** With physical light units a camera metered for a
    # hundred thousand lux of midday sun sees nothing at all by moonlight, and no amount of
    # headlight fixes that: a 22,000 cd low beam puts around 50 lux on the road at twenty
    # metres, which is a two-thousandth of the light the day exposure was set for. So the night
    # opens the lens up the way a driver's own eye does — f/1.8, a thirtieth of a second and
    # ISO 6400 — and the headlights land where they belong.
    "night_moon": {
        "physical_sky": true,
        # The night sky, dark enough that a headlight is the brightest thing in the frame and
        # bright enough to be a sky rather than a hole. Measured against the beams: at 0.004 the
        # moonlit ground is as bright as what the low beams throw, and the lamps read as glow
        # rather than as light.
        "sky_energy": 0.0004,
        # The moon, high and over the camera's left shoulder.
        "sun_from": Vector3(-0.42, 0.74, 0.52),
        # What a full moon actually is. A quarter of a lux against a low beam's fifty-odd on the
        # road ahead, which is the two hundred to one that makes a night drive a night drive.
        "sun_lux": 0.25,
        "sun_energy": 1.0,
        "sun_color": Color(0.62, 0.72, 1.0),
        "sky_top": Color(0.015, 0.025, 0.055),
        "sky_horizon": Color(0.05, 0.07, 0.13),
        # Ambient from a stated colour rather than from the sky: see
        # `BlockoutWorld._grade_environment` on why the energy does nothing while the sky
        # supplies all of it.
        "ambient_from_sky": 0.0,
        "ambient_colour": Color(0.42, 0.55, 1.0),
        "ambient_energy": 0.002,
        "bg_color": Color(0.015, 0.025, 0.055),
        "fill_energy": 0.0,
        # A moon is a disc like the sun and casts a shadow with an edge of its own.
        "sun_angular_deg": 0.6,
        # The eye a driver brings to it: wide open, slow, and sensitive.
        "iso": 1600.0,
        "f_stop": 2.8,
        "shutter_s": 0.0167,
        # 850 times a midday exposure, which is where a 22,000 cd low beam lands a little under
        # a sunlit road and a quarter-lux moon lands near black. Measured: at ISO 6400 the same
        # beam is two and a half times a sunlit road and clips.
        # The haze is what the night is, not what the day is: thinner, and the colour of the
        # sky rather than of a bright overcast.
        "fog_density": 0.0004,
        "fog_colour": Color(0.05, 0.07, 0.13),
        # Air for the beams to stand in.
        "volumetric": true,
    },
    # A black, unlit environment. Measurement gates encode numbers into pixels, so any
    # ambient contribution would be added to the value being read back.
    #
    # **An instrument, not an hour of the day**, and `measurement` is what says so. A window used
    # to cycle into it and find a black world with headlights that did nothing — reported in
    # those words — because it has no sun, no sky and a daylight exposure, and changing any of
    # that would change every number read back through it. `PlayWeather` leaves it out of the
    # cycle and the settings panel; a gate still asks for it by name.
    "spike_black": {
        "measurement": true,
        "sun_from": Vector3(0.0, 1.0, 0.0),
        "sun_energy": 0.0,
        "sun_color": Color(0.0, 0.0, 0.0),
        "ambient_energy": 0.0,
        "bg_color": Color(0.0, 0.0, 0.0),
    },
    "golden_dusk": {
        "physical_sky": true,
        "sky_energy": 1.0,
        "sun_from": Vector3(0.82, 0.18, 0.54),
        "sun_energy": 0.9,
        "sun_color": Color(1.0, 0.72, 0.45),
        "sky_top": Color(0.16, 0.22, 0.42),
        "sky_horizon": Color(0.86, 0.58, 0.36),
        "ambient_energy": 1.0,
        "bg_color": Color(0.26, 0.24, 0.32),
    },
}


static func has(preset: String) -> bool:
    return PRESETS.has(preset)


static func get_preset(preset: String) -> Dictionary:
    return PRESETS.get(preset, {}) as Dictionary
