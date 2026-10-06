class_name PlayWeather
extends RefCounted
## Which weather a session is in, and how it changes.
##
## Split out of `PlayRig` when that file went over the source cap, and it is a seam worth having:
## two front ends choose a weather — F2 cycles, the settings panel picks — and this is the one
## place that applies one, so the two cannot drift into applying a preset differently.
##
## The name the HUD shows follows whichever way the weather was chosen. Picking one in the panel
## used to leave the index behind, so the HUD kept naming the weather before last, reported from
## a window as a night scene labelled `noon_clear`.

var names: Array[String] = []
var index: int = 0
## The camera to re-meter when the hour changes, and the shot it was framed for. Set once by the
## window. Null in anything that only wants the lights moved.
var camera: Camera3D = null
var shot: Dictionary = {}
## The hour the clock is at, when a session is running the day rather than a named preset. -1
## while a preset is what is on.
var hour: float = -1.0
## What this session has moved by hand, over whatever the hour or the preset says.
##
## **A preset is a set of values and not a mode.** A session used to pick one and then drag the
## clock, which left the two disagreeing — a night preset with a midday sun in it — and a cloud
## slider that went back to the preset's weather the moment the hour moved. A knob moved here
## stays moved until a preset is chosen again, which is what clears them.
var overrides: Dictionary = {}


## `with_camera` and `with_shot` are what an hour is metered through: under physical light units
## a preset that states its light in lux states the exposure that light was metered for, so
## changing the hour has to open the lens as well as put the sun out.
func _init(wanted: String, with_camera: Camera3D = null, with_shot: Dictionary = {}) -> void:
    camera = with_camera
    shot = with_shot
    for key: String in WeatherCfg.PRESETS.keys():
        # Measurement presets are instruments: `spike_black` is an unlit void that exists so a
        # gate can encode a number into a pixel and read it back, and a session that cycles into
        # it gets a black world with headlights that appear not to work. A gate still names it
        # directly; the window does not offer it.
        if bool((WeatherCfg.get_preset(key)).get("measurement", false)):
            continue
        names.append(key)
    index = maxi(0, names.find(wanted))


## What is on now: an hour when the clock is running, the preset's name otherwise.
func current() -> String:
    var moved: String = " custom" if not overrides.is_empty() else ""
    if hour >= 0.0:
        return "%02d:%02d%s" % [int(hour), int(fposmod(hour * 60.0, 60.0)), moved]
    return (names[index] if index < names.size() else "") + moved


## Puts one hour of the day on the live scene.
##
## The same path a preset takes — `DayCycle.at` returns a weather dictionary of exactly the kind
## `apply` is given — so the sun, the sky, the stars, the haze and the exposure all move together
## and nothing downstream knows whether the hour came off a clock or out of a preset.
func set_hour(world: Node3D, wanted: float) -> void:
    hour = fposmod(wanted, 24.0)
    _put(world, state())


## One thing a session has moved by hand, kept and applied over the hour.
func set_override(world: Node3D, key: String, value: Variant) -> void:
    overrides[key] = value
    # Cloud cover is two things at once: how much marched cloud is drawn, and how far the sky
    # itself has gone over to the overcast capture. See `SkyMaps.cloudy_share`.
    if key == "cloud_coverage":
        overrides["hdri_cloudy_mix"] = SkyMaps.cloudy_share(float(value))
    _put(world, state())


## The weather as it stands: the hour's, or the preset's, with everything moved by hand on top.
func state() -> Dictionary:
    var base: Dictionary = (
        DayCycle.at(hour) if hour >= 0.0
        else WeatherCfg.get_preset(names[index] if index < names.size() else "")
    )
    var out: Dictionary = base.duplicate(true)
    out.merge(overrides, true)
    return out


## Puts one preset on the live scene.
##
## Everything the preset says, through the same function that builds a world from one. This used
## to aim the sun, set its energy trim and colour, and change two environment fields. It never
## set `light_intensity_lux`, which is what actually decides a light's brightness under physical
## units, so the sun barely changed; it never touched the fill, so a 12 000 lux cool light kept
## burning through a night preset; and it never rebuilt the sky, so the atmosphere stayed as
## built. `a_weather_switch_is_a_weather` holds the two paths together.
func apply(world: Node3D, name: String) -> void:
    hour = -1.0
    overrides.clear()
    index = maxi(0, names.find(name))
    _put(world, state())
    print("PLAY  weather %s" % name)


## Everything a weather dictionary decides, applied to a world that already exists.
func _put(world: Node3D, weather: Dictionary) -> void:
    BlockoutWorld.apply_weather(world, weather, RenderCfg.CLOUDS_ENABLED)
    # The exposure, because an hour that states its light in lux states what that light was
    # metered for. Without this, switching to a night gives a black window with working
    # headlights in it and nothing to see them by.
    if camera != null and is_instance_valid(camera):
        PhysicalCamera.reexpose(camera, shot, weather)
    # And the vehicle's own reflection, which was taken once under whatever sky was up then.
    ActorProbe.recapture(
        world, float(weather.get("probe_intensity", ActorProbe.INTENSITY))
    )


## The next preset in the list, applied.
func cycle(world: Node3D) -> void:
    apply(world, names[(index + 1) % names.size()])
