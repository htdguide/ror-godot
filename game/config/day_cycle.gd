class_name DayCycle
extends RefCounted
## One hour of the day, as everything the world needs to look like that hour.
##
## **A weather preset is a snapshot and a day is a path.** The presets stay — a gate asks for
## `noon_clear` by name and gets the same light every time, which is what makes a measurement
## comparable — and this is the continuous thing beside them: give it an hour between 0 and 24
## and it returns a weather dictionary of exactly the kind `BlockoutWorld.apply_weather` and
## `PhysicalCamera.reexpose` already take. Nothing downstream knows the difference.
##
## What moves with the hour:
##
## - **The sun**, along an arc: up in the east at six, highest at noon, down in the west at six
##   again. Its illuminance follows its own height, because that is what makes a low sun dim as
##   well as orange — 100,000 lux overhead, a few hundred at the horizon.
## - **The moon**, which is the same light after dark. One directional light, not two: at night it
##   takes the moon's own path and the moon's own quarter of a lux, and the sky shader draws its
##   disc because the shader puts a disc wherever the first directional light is.
## - **The sky**, from a daylight blue through the warm band at the horizon to a navy night, with
##   its brightness falling four thousand-fold across the twilight.
## - **The exposure**, because under physical light units an hour that states its light in lux has
##   to state what that light was metered for. f/8 at a hundred-and-twenty-fifth and ISO 32 at
##   noon; f/2.8 at a sixtieth and ISO 1600 under the moon.
## - **The stars**, which come up through the same twilight the sky goes down through.
##
## The arc is a plain sinusoid rather than an ephemeris. A real one takes a date, a latitude and
## a longitude, and a Rigs of Rods terrain states none of them; what a session wants from this is
## an hour it can drag, with a sun that rises where it set.

## When the sun crosses the horizon. Six and eighteen, which is an equinox day and the one every
## terrain in this library is lit for.
const SUNRISE_H: float = 6.0
const SUNSET_H: float = 18.0
## How high the sun gets at noon.
const NOON_ELEVATION_DEG: float = 62.0
## And the moon, which rides lower.
const MOON_ELEVATION_DEG: float = 48.0
## Full daylight at this elevation and full night at this one, with the twilight between them.
## Civil twilight ends around six degrees below the horizon; this is a little wider so that the
## change reads as a change rather than as a switch.
const DAY_ELEVATION_DEG: float = 6.0
const NIGHT_ELEVATION_DEG: float = -9.0
## How high the sun has to climb before its light stops being the colour of the horizon.
##
## **This is the golden hour and it is much longer than the twilight.** How bright an hour is and
## what colour it is are two different questions, and answering both with one number made an hour
## after sunrise look like noon: the sun was at 15.7 degrees, the brightness had saturated, and
## with it went every trace of the warmth — a pale blue-white frame at seven in the morning.
## Reported from a window as "a few moments when it looks weirdly white when it is supposed to be
## sunset or sunrise".
const WARM_ELEVATION_DEG: float = 30.0
## And where the stars go out: they are gone before the sun itself is up.
const STARS_FROM_DEG: float = -13.0
const STARS_TO_DEG: float = -1.5

## The sun at its highest, and what is left of it on the horizon. A low sun is dim as well as
## red: the light comes through far more air.
const SUN_LUX_NOON: float = 100000.0
const SUN_LUX_HORIZON: float = 450.0
## What a full moon puts on the ground.
const MOON_LUX: float = 0.25
## Colours. A midday sun is near white, a setting one is the colour of its own name, and
## moonlight is sunlight reflected off grey rock — cool only because an eye at night says so.
const SUN_COLOUR_NOON: Color = Color(1.0, 0.97, 0.92)
const SUN_COLOUR_HORIZON: Color = Color(1.0, 0.62, 0.32)
const MOON_COLOUR: Color = Color(0.62, 0.72, 1.0)
## How big a disc each is, in degrees. Both are about half a degree across in the sky; the sun's
## is left at the project's own figure and the moon's is sharper because it casts a sharper
## shadow.
const SUN_ANGULAR_DEG: float = 1.8
const MOON_ANGULAR_DEG: float = 0.6

## The sky's brightness at noon and under the moon, and how much of that brightness reaches the
## radiance map every glossy surface reflects. See `sky_clouds.gdshader` on the second one: a
## night sky left at its own brightness lights a white vehicle harder than its own headlights do.
const SKY_ENERGY_DAY: float = 1.0
const SKY_ENERGY_NIGHT: float = 0.0004
const RADIANCE_DAY: float = 1.0
const RADIANCE_NIGHT: float = 0.006
## The sky's own colours at noon, at the horizon's own hour, and at midnight.
const SKY_TOP_DAY: Color = Color(0.22, 0.42, 0.78)
const SKY_HORIZON_DAY: Color = Color(0.62, 0.74, 0.88)
const SKY_TOP_DUSK: Color = Color(0.16, 0.22, 0.42)
const SKY_HORIZON_DUSK: Color = Color(0.92, 0.52, 0.26)
const SKY_TOP_NIGHT: Color = Color(0.015, 0.025, 0.055)
const SKY_HORIZON_NIGHT: Color = Color(0.05, 0.07, 0.13)

## The ambient term. By day it is the sky's own irradiance; after dark the sky is not bright
## enough to light anything and a stated colour stands in for the rest of the world's bounce.
const AMBIENT_FROM_SKY_DAY: float = 1.0
const AMBIENT_FROM_SKY_NIGHT: float = 0.0
const AMBIENT_COLOUR_NIGHT: Color = Color(0.42, 0.55, 1.0)
const AMBIENT_ENERGY_DAY: float = 1.0
const AMBIENT_ENERGY_NIGHT: float = 0.002

## The haze: a pale daylight one, the colour of the sky it hangs in at night.
const FOG_DENSITY_DAY: float = 0.0006
const FOG_DENSITY_NIGHT: float = 0.0004
const FOG_COLOUR_DAY: Color = Color(0.68, 0.72, 0.78)
## The haze a low sun comes through, which is the colour of the light that is in it.
const FOG_COLOUR_DUSK: Color = Color(0.72, 0.46, 0.3)
## **A haze is as dark as the sky it hangs in.** The night's own sky colour looks like the right
## figure here and is not: fog colour is an absolute, not something the sky's brightness scales,
## so a navy that reads correctly as a sky washed every distant hill to a visible grey band
## standing over a black world at midnight. Measured, the far terrain came back at 0.2 display
## luminance on a ground of 0.0002.
const FOG_COLOUR_NIGHT: Color = Color(0.006, 0.009, 0.018)

## The photographer's three numbers at either end of the day, and the light each end was metered
## for.
##
## **The camera meters the light, not the clock.** The exposure used to be interpolated on how
## much of the day it was, and the light does not follow that curve: half past six in the evening
## is six per cent of the way through the twilight — a night sky, stars out — while the ground
## still has 4.6 lux on it, eighteen times a full moon. A night exposure on eighteen moons is a
## scene lit like dusk under a sky like midnight, with the vehicle the brightest thing in it.
## Metering on the hour's own illuminance in log space keeps the two together at every hour.
const DAY_LUX_ANCHOR: float = SUN_LUX_NOON
const NIGHT_LUX_ANCHOR: float = MOON_LUX
const ISO_DAY: float = 32.0
const ISO_NIGHT: float = 1600.0
const F_STOP_DAY: float = 8.0
const F_STOP_NIGHT: float = 2.8
const SHUTTER_DAY_S: float = 0.008
const SHUTTER_NIGHT_S: float = 0.0167

## The fill light, which is a daylight device: a cool bounce against a warm sun. There is nothing
## for it to bounce off at night.
##
## **It is a share of the sun and not a number of its own.** `FILL_LUX` is twelve thousand lux,
## and an hour that scaled only the trim left 720 lux of cool white light standing against a sun
## of 4.6 at half past six in the evening — a hundred and fifty times the light that was actually
## there. The vehicle went white while the road beside it stayed grey, which is what a session saw
## as "a weird too bright white reflection on the truck when getting closer to the sunset". A
## bounce cannot be brighter than what it bounces.
const FILL_SHARE: float = 0.05
const FILL_ENERGY_DAY: float = 1.0


## Everything about one hour of the day, in the form a weather preset takes.
##
## `hour` is a clock hour and wraps: 25.5 is half past one in the morning.
static func at(hour: float) -> Dictionary:
    var clock: float = fposmod(hour, 24.0)
    var elevation: float = sun_elevation_deg(clock)
    # How much of the day this hour is, across the twilight. One at noon, zero at midnight, and
    # everything between while the sun is near the horizon.
    var day: float = clampf(
        (elevation - NIGHT_ELEVATION_DEG) / (DAY_ELEVATION_DEG - NIGHT_ELEVATION_DEG), 0.0, 1.0
    )
    var daylight: bool = elevation > 0.0
    var lux: float = _lux(
        elevation, daylight,
        MOON_LUX * clampf(sin(deg_to_rad(moon_elevation_deg(clock))), 0.12, 1.0)
    )
    # Where this hour's light sits between a full moon and a midday sun, in ratios. This is what
    # the camera is set from.
    var metered: float = clampf(
        log(maxf(lux, NIGHT_LUX_ANCHOR) / NIGHT_LUX_ANCHOR)
        / log(DAY_LUX_ANCHOR / NIGHT_LUX_ANCHOR), 0.0, 1.0
    )
    # How much of the horizon's own colour this hour has. Not the same question as how bright it
    # is: the sun is warm for an hour after it is fully up, and this is what says so.
    # The curve favours the low sun: halfway up the band is still most of the way warm, which is
    # what an hour after sunrise actually looks like.
    var warmth: float = (
        pow(1.0 - clampf(absf(elevation) / WARM_ELEVATION_DEG, 0.0, 1.0), 0.6)
        * smoothstep(NIGHT_ELEVATION_DEG - 4.0, 0.0, elevation)
    )
    return {
        "physical_sky": true,
        # This project's own sky shader rather than the atmosphere model: it is the one that can
        # state how much of its brightness is light rather than only a picture.
        "sky_shader": true,
        "sun_from": toward_light(clock),
        # The moon's own height matters the way the sun's does: a moon near the horizon lights
        # the ground less than one overhead, and a night that is one brightness from dusk to
        # dawn is a night nobody has stood in.
        "sun_lux": lux,
        "sun_energy": 1.0,
        "sun_color": (
            SUN_COLOUR_NOON.lerp(SUN_COLOUR_HORIZON, warmth) if daylight else MOON_COLOUR
        ),
        "sun_angular_deg": SUN_ANGULAR_DEG if daylight else MOON_ANGULAR_DEG,
        "sky_energy": _between(SKY_ENERGY_NIGHT, SKY_ENERGY_DAY, day),
        "radiance_scale": _between(RADIANCE_NIGHT, RADIANCE_DAY, day),
        "sky_top": _sky_colour(SKY_TOP_NIGHT, SKY_TOP_DUSK, SKY_TOP_DAY, day, warmth),
        "sky_horizon": _sky_colour(
            SKY_HORIZON_NIGHT, SKY_HORIZON_DUSK, SKY_HORIZON_DAY, day, warmth
        ),
        "stars": 1.0 - smoothstep(STARS_FROM_DEG, STARS_TO_DEG, elevation),
        # What is falling on the clouds. They are lit by whatever is up, so they go out with it:
        # a moonlit cloud is a dim grey shape and not a white one.
        "cloud_light": maxf(day, 0.03),
        # The disc of whatever is up, drawn with its own brightness rather than the sky's. A moon
        # at the sky's own night multiplier is not a moon, it is nothing.
        "disc_energy": maxf(day, 0.015),
        "ambient_from_sky": lerpf(AMBIENT_FROM_SKY_NIGHT, AMBIENT_FROM_SKY_DAY, day),
        "ambient_colour": AMBIENT_COLOUR_NIGHT,
        "ambient_energy": _between(AMBIENT_ENERGY_NIGHT, AMBIENT_ENERGY_DAY, day),
        "bg_color": SKY_TOP_NIGHT.lerp(SKY_TOP_DAY, day),
        "fill_energy": FILL_ENERGY_DAY * day,
        "fill_lux": lux * FILL_SHARE,
        "fog_density": lerpf(FOG_DENSITY_NIGHT, FOG_DENSITY_DAY, day),
        # The haze takes the hour's colour too: a low sun reddens the air it comes through, and a
        # pale grey daylight haze under an orange sky is the other half of what read as white.
        "fog_colour": FOG_COLOUR_NIGHT.lerp(FOG_COLOUR_DAY, day).lerp(
            FOG_COLOUR_DUSK, warmth * 0.85
        ),
        # Air for a headlight to stand in, while there is a headlight worth seeing.
        "volumetric": day < 0.5,
        "iso": _between(ISO_NIGHT, ISO_DAY, metered),
        "f_stop": lerpf(F_STOP_NIGHT, F_STOP_DAY, metered),
        "shutter_s": lerpf(SHUTTER_NIGHT_S, SHUTTER_DAY_S, metered),
        # What an unlit surface is scaled by. A terrain's horizon backdrop is a photograph with
        # the daylight painted into it and cannot be lit; this is the only thing that can carry
        # it through a night. Never quite nothing: a horizon that vanishes is as wrong as one
        # that glows.
        "unlit_dim": maxf(day, 0.03),
        "hour": clock,
    }


## How high the sun is at this hour, in degrees above the horizon. Negative after dark.
##
## A sinusoid through sunrise and sunset rather than an ephemeris: a Rigs of Rods terrain states
## no date, latitude or longitude, and what a session wants is an hour it can drag with a sun
## that rises where it set. Zero at six, highest at noon, zero again at six, and as far below the
## horizon at midnight as it was above it at the other end — which is an equinox day, and the one
## every terrain in this library is lit for.
static func sun_elevation_deg(hour: float) -> float:
    return NOON_ELEVATION_DEG * sin(PI * (hour - SUNRISE_H) / (SUNSET_H - SUNRISE_H))


## How high the moon is, in degrees. It rides the half of the clock the sun does not, so a night
## has a moon overhead in the middle of it the way a day has a sun.
static func moon_elevation_deg(hour: float) -> float:
    return MOON_ELEVATION_DEG * sin(PI * (hour - SUNSET_H) / (SUNSET_H - SUNRISE_H))


## The direction from the scene toward whichever body is up, which is what a weather preset's
## `sun_from` means.
##
## East at sunrise, through the south, west at sunset — the northern hemisphere's own arc, on the
## compass a Rigs of Rods terrain is laid out on: +x is east and +z is south. After dark it is
## the moon on the same arc, half a day behind.
static func toward_light(hour: float) -> Vector3:
    var elevation: float = sun_elevation_deg(hour)
    var along: float = (hour - SUNRISE_H) / (SUNSET_H - SUNRISE_H)
    if elevation <= 0.0:
        elevation = moon_elevation_deg(hour)
        along = (fposmod(hour - SUNSET_H, 24.0)) / (SUNSET_H - SUNRISE_H)
    # Never exactly on the horizon: a light that lies in the ground plane lights nothing and
    # leaves the sky shader with no disc to draw.
    var height: float = deg_to_rad(maxf(elevation, 0.75))
    var azimuth: float = PI * clampf(along, 0.0, 1.0)
    return Vector3(
        cos(azimuth) * cos(height), sin(height), sin(azimuth) * cos(height)
    ).normalized()


## What the light on the ground is, in lux.
##
## The sun's own illuminance follows its height — a hundred thousand lux overhead, a few hundred
## at the horizon — because that is what makes a low sun dim as well as orange. Below the horizon
## it is the moon's quarter of a lux, faded in across the twilight so that the sky goes out
## before the stars come up rather than at the same instant.
static func _lux(elevation_deg: float, daylight: bool, moon_lux: float = MOON_LUX) -> float:
    if daylight:
        var height: float = sin(deg_to_rad(maxf(elevation_deg, 0.0)))
        return maxf(SUN_LUX_HORIZON, SUN_LUX_NOON * pow(height, 1.25))
    var dusk: float = clampf(1.0 + elevation_deg / -NIGHT_ELEVATION_DEG, 0.0, 1.0)
    return lerpf(moon_lux, SUN_LUX_HORIZON, dusk * dusk)


## A value that spans orders of magnitude, interpolated the way an eye reads it: in ratios
## rather than in steps. A sky that goes from 0.0004 to 1.0 linearly is full daylight for all but
## the last moments of dusk.
static func _between(dark: float, light: float, day: float) -> float:
    return dark * pow(light / dark, clampf(day, 0.0, 1.0))


## The sky's colour at an hour: night to day, with the horizon's own warmth laid over it.
##
## **Warmth is not a function of brightness.** It used to be `low * day * (1 - day) * 4`, which is
## zero wherever the brightness has settled — so the only warm frames in a day were the two
## half-hours when it happened to be halfway, and seven in the morning was a pale blue noon.
static func _sky_colour(
    night: Color, dusk: Color, day_colour: Color, day: float, warmth: float
) -> Color:
    return night.lerp(day_colour, day).lerp(dusk, warmth)
