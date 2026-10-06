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
        # Lit by a captured sky rather than a flat colour or a model, so surfaces have something
        # real to reflect and the shadows are filled by the light that place actually had.
        "physical_sky": true,
        "hdri": "qwantani_afternoon_puresky_2k.hdr",
        # **What the map is worth as light, set from daylight rather than from taste.** A Poly
        # Haven sky is normalised so its picture reads well and says nothing about whether it is a
        # hundred thousand lux or fifteen, so the number is calibrated: clear-sky daylight puts
        # about 95,000 lux of direct sun on a surface facing it and about 8,000 of skylight, which
        # is 13:1, and `daylight_shadows_are_readable` measures 13.3:1 at this value. It was 5.4:1
        # with the map taken as it came.
        "sky_energy": 1.0,
        "hdri_gain": 0.27,
        "hdri_mix": 1.0,
        # Where this map's own sun is: the brightest tenth of a per cent of it, weighted, which
        # comes out at 40.8 degrees of elevation. Measured rather than chosen, because a sky whose
        # bright spot is in one place and whose shadows fall from another is a scene with two suns
        # in it — `a_captured_sky_and_its_sun_agree` is what holds the two together.
        "sun_from": Vector3(-0.446, 0.654, 0.611),
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
        # **These three used to be a fiftieth, a twentieth and a fiftieth, and all three were
        # cancelling the same bug.** The sky's light was exposed twice — once into the radiance
        # map and once when lighting with it — so a night metered 852 times a midday exposure lit
        # the scene 852 times too hard, and a white truck came back at 0.57 on a black road. They
        # are 1.0 now because the sky no longer follows the camera (see
        # `PhysicalCamera.exposure_scale`) and because the moon's own quarter-lux against a
        # midday sun's hundred thousand is what should be dimming the clouds and the disc.
        "radiance_scale": 1.0,
        "cloud_light": 1.0,
        "disc_energy": 1.0,
        # This project's own sky shader rather than the atmosphere model, because it is the one
        # that can state a radiance scale, and because a modelled atmosphere lit by a moon is a
        # daylight sky with the brightness turned down.
        "sky_shader": true,
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
        # How much light a night sky gives against a midday one, which is almost none: a moonlit
        # sky is about a thousandth of a lux where a day sky is fifteen thousand. The camera is
        # applied to it in `BlockoutWorld._grade_environment`, so this is an irradiance rather
        # than a number with the night's own film already in it.
        "ambient_energy": 0.0000025,
        "bg_color": Color(0.015, 0.025, 0.055),
        "fill_energy": 0.0,
        # A moon is a disc like the sun and casts a shadow with an edge of its own.
        "sun_angular_deg": 0.6,
        # Nothing fills a shadow at night.
        "shadow_opacity": 1.0,
        # Nothing to reflect but a dark sky: see `ActorProbe.recapture`.
        "probe_intensity": 0.12,
        # The eye a driver brings to it: wide open, slow, and sensitive.
        "iso": 1600.0,
        "f_stop": 2.8,
        "shutter_s": 0.0167,
        # 850 times a midday exposure, which is where a 22,000 cd low beam lands a little under
        # a sunlit road and a quarter-lux moon lands near black. Measured: at ISO 6400 the same
        # beam is two and a half times a sunlit road and clips.
        # The haze is what the night is, not what the day is: thinner, and the colour of the
        # sky rather than of a bright overcast.
        "fog_density": 0.00008,
        "fog_colour": Color(0.006, 0.009, 0.018),
        # Air for the beams to stand in.
        "volumetric": true,
    },
    # A flat grey day, captured. The one hour in this set with no sun in it at all: the cloud deck
    # is the light source, which is why the shadows are soft and shallow and the whole scene sits
    # six times below a clear noon.
    "overcast": {
        "physical_sky": true,
        "hdri": "kloofendal_overcast_puresky_2k.hdr",
        "hdri_mix": 1.0,
        # The cloud is the sky and the sky is the light, so this carries nearly all of it. Set
        # against the clear day's: overcast daylight is about fifteen thousand lux where a clear
        # noon is a hundred thousand, and nearly all of the fifteen is diffuse.
        "sky_energy": 1.0,
        "hdri_gain": 0.05,
        # Where the sun is behind the cloud — the brightest tenth of a per cent of the map,
        # weighted. A disc this soft still has a direction, and a scene with no direction at all
        # has no form in it.
        "sun_from": Vector3(-0.497, 0.384, 0.778),
        "sun_lux": 8000.0,
        "sun_energy": 1.0,
        "sun_color": Color(0.95, 0.96, 1.0),
        # A cloud deck is a light the size of the sky, so its shadow has no edge to speak of and
        # takes little away.
        "sun_angular_deg": 12.0,
        "shadow_opacity": 0.45,
        "ambient_energy": 1.0,
        "sky_top": Color(0.62, 0.64, 0.68),
        "sky_horizon": Color(0.72, 0.73, 0.75),
        "bg_color": Color(0.66, 0.67, 0.70),
        # Six times under a clear noon asks for two and a half stops, the way the hour does.
        "iso": 100.0,
        "f_stop": 6.3,
        "shutter_s": 0.008,
        # The haze an overcast day has: thicker than a clear one, pale, and the colour of the
        # cloud rather than of a blue sky. 0.0004 is a visual range of ten kilometres, which is
        # what an overcast morning has against a clear afternoon's fifty — see `RenderCfg.FOG_DENSITY`.
        "fog_density": 0.0004,
        "fog_colour": Color(0.70, 0.72, 0.75),
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
        # A real sunset, captured. The map holds no solar disc — the sun is in the haze at the
        # horizon — so the direction below is the brightest tenth of a per cent of the sky,
        # weighted, which is where the light in the picture is coming from.
        "hdri": "qwantani_dusk_2_puresky_2k.hdr",
        "sky_energy": 1.0,
        "hdri_gain": 0.019,
        "hdri_mix": 1.0,
        "sun_from": Vector3(-0.577, 0.197, 0.792),
        # **A low sun is a weak sun.** The beam crosses five atmospheres at eleven degrees of
        # elevation instead of one and a half at forty, and clear-sky direct normal illuminance
        # falls from about 95,000 lux to 35,000 for it. This used to be nine tenths of a midday
        # sun pointed at the horizon, which is a midday sun with a sunset painted behind it.
        "sun_lux": 35000.0,
        "sun_energy": 1.0,
        "sun_color": Color(1.0, 0.72, 0.45),
        "sky_top": Color(0.16, 0.22, 0.42),
        "sky_horizon": Color(0.86, 0.58, 0.36),
        "ambient_energy": 1.0,
        "bg_color": Color(0.26, 0.24, 0.32),
        # **The hour states its own film, because the light is a third of a midday's.** A camera
        # metered for noon photographs a sunset as a silhouette: the shaded side of a subject came
        # back at 0.0176 display luma, a third of what an eight-bit image can still hold detail
        # in. Two and a third stops open — f/6.3 at ISO 100 — is what a photographer does at this
        # hour, and it is what the sun's own fall from 95,000 lux to 35,000 asks for.
        "iso": 100.0,
        "f_stop": 6.3,
        "shutter_s": 0.008,
    },
}


static func has(preset: String) -> bool:
    return PRESETS.has(preset)


static func get_preset(preset: String) -> Dictionary:
    return PRESETS.get(preset, {}) as Dictionary
