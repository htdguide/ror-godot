class_name SkyMaps
extends RefCounted
## The captured skies, what each one holds, and which one an hour should be drawn over.
##
## The maps are Poly Haven's, CC0, 2k Radiance HDR — see `THIRD_PARTY.md` — and they are "pure
## sky" captures with no ground in them, because this project's ground is a terrain a mod author
## shipped and a second horizon in the sky is a seam nobody can unsee.
##
## **Everything said about a map here was measured out of its own pixels**, not taken off its
## page: where its sun is, and what its brightness is worth. A photographed sky is normalised so
## that its picture reads well, which says nothing about whether it was a hundred thousand lux or
## fifteen, so the gain is what turns its units into the stated gradient's — set by photographing
## a grey card under it until the sunlit-to-skylit ratio is daylight's. See
## `daylight_shadows_are_readable`.

const DIRECTORY: String = "res://assets/hdri"

## The clear sky the day is drawn over, its sun 40.8 degrees up and 36.1 degrees west of the
## scene's noon. `gain` 0.27 is where a grey card reads 13.3:1 sunlit to skylit, against the 13:1
## of clear daylight; the map as it came read 5.4:1.
const CLEAR: Dictionary = {
    "file": "qwantani_afternoon_puresky_2k.hdr",
    "elevation_deg": 40.8,
    "azimuth_deg": -36.1,
    "gain": 0.27,
}
## The overcast one, which has no solar disc in it at all: the cloud deck is the light. Blended
## toward as the weather thickens, so that a session asking for cloud gets a real overcast sky
## rather than only more marched cloud over a blue one.
const OVERCAST: Dictionary = {
    "file": "kloofendal_overcast_puresky_2k.hdr",
    "elevation_deg": 22.6,
    "azimuth_deg": -32.6,
    "gain": 0.05,
}
## And the sunset, which the `golden_dusk` preset names directly. It is not in the day cycle: a
## captured sky carries the hour it was taken at, and the hours either side of sunset are the ones
## the modelled sky is best at — it has the warm horizon and the stars coming up through it.
const DUSK: Dictionary = {
    "file": "qwantani_dusk_2_puresky_2k.hdr",
    "elevation_deg": 11.4,
    "azimuth_deg": -36.1,
    "gain": 0.019,
}
## How far from a map's own sun the scene's sun may be before the stated gradient takes over, in
## degrees of elevation.
##
## **A photograph carries the hour it was taken at and a yaw cannot change that.** Turning a map
## puts its sun at any compass bearing, which is what a shadow's direction reads; nothing puts it
## at a different height. The clear map's sun is 40.8 degrees up and this project's noon is 62, so
## at midday the two are 19 degrees apart — measured, and caught by
## `a_captured_sky_and_its_sun_agree` the first time the day cycle was given a captured sky. So
## the map is drawn over the hours it fits and faded out of the ones it does not, and midday and
## dusk are the stated gradient, which has no sun of its own to disagree with.
const FITS_WITHIN_DEG: float = 10.0
const GRADIENT_BEYOND_DEG: float = 22.0


## One panorama, or null when the file is not in the checkout. Absent rather than fatal: the maps
## are twelve megabytes of captured sky and a gate that needs one says so and skips.
static func texture(file: String) -> Texture2D:
    if file.is_empty():
        return null
    var path: String = DIRECTORY.path_join(file)
    if not ResourceLoader.exists(path):
        return null
    return load(path) as Texture2D


## Whether this checkout has the sky a weather preset names.
static func present(weather: Dictionary) -> bool:
    var file: String = weather.get("hdri", "") as String
    return not file.is_empty() and ResourceLoader.exists(DIRECTORY.path_join(file))


## How much of the captured sky an hour shows: all of it where the map's own sun is about where
## this hour's is, none of it where they have drifted apart.
static func captured_share(elevation_deg: float) -> float:
    var apart: float = absf(elevation_deg - (CLEAR["elevation_deg"] as float))
    return 1.0 - smoothstep(FITS_WITHIN_DEG, GRADIENT_BEYOND_DEG, apart)


## How far the sky itself has gone over to the overcast capture, by how much cloud a session has
## asked for. Below the first figure the weather is cloud drawn over a clear sky; above the second
## it is an overcast day, which is a different sky and not a cloudier one — the deck is the light
## source, the shadows go soft and the whole scene drops six times under a clear noon.
const CLOUDY_FROM: float = 0.5
const CLOUDY_TO: float = 0.95


static func cloudy_share(coverage: float) -> float:
    return smoothstep(CLOUDY_FROM, CLOUDY_TO, coverage)


## How far a map has to be turned for its own sun to sit where this scene's sun is, in radians.
##
## A photograph's sun is wherever it was when the picture was taken, and a scene whose shadows
## fall one way and whose bright spot in the sky is somewhere else has two suns in it. The map
## turns; the scene's sun does not. `a_captured_sky_and_its_sun_agree` is what holds them together.
static func yaw_for(map: Dictionary, toward_sun: Vector3) -> float:
    var azimuth: float = atan2(toward_sun.x, toward_sun.z)
    return azimuth - deg_to_rad(map["azimuth_deg"] as float)
