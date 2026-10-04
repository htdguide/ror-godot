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


func _init(wanted: String) -> void:
    for key: String in WeatherCfg.PRESETS.keys():
        # Measurement presets are instruments: `spike_black` is an unlit void that exists so a
        # gate can encode a number into a pixel and read it back, and a session that cycles into
        # it gets a black world with headlights that appear not to work. A gate still names it
        # directly; the window does not offer it.
        if bool((WeatherCfg.get_preset(key)).get("measurement", false)):
            continue
        names.append(key)
    index = maxi(0, names.find(wanted))


## What is on now.
func current() -> String:
    return names[index] if index < names.size() else ""


## Puts one preset on the live scene.
##
## Everything the preset says, through the same function that builds a world from one. This used
## to aim the sun, set its energy trim and colour, and change two environment fields. It never
## set `light_intensity_lux`, which is what actually decides a light's brightness under physical
## units, so the sun barely changed; it never touched the fill, so a 12 000 lux cool light kept
## burning through a night preset; and it never rebuilt the sky, so the atmosphere stayed as
## built. `a_weather_switch_is_a_weather` holds the two paths together.
func apply(world: Node3D, name: String) -> void:
    var preset: Dictionary = WeatherCfg.get_preset(name)
    BlockoutWorld.apply_weather(world, preset, RenderCfg.CLOUDS_ENABLED)
    # And the exposure, because an hour that states its light in lux states what that light was
    # metered for. Without this, switching to the night preset gives a black window with working
    # headlights in it and nothing to see them by.
    if camera != null and is_instance_valid(camera):
        PhysicalCamera.reexpose(camera, shot, preset)
    # And the vehicle's own reflection, which was taken once under whatever sky was up then.
    ActorProbe.recapture(world)
    index = maxi(0, names.find(name))
    print("PLAY  weather %s" % name)


## The next preset in the list, applied.
func cycle(world: Node3D) -> void:
    apply(world, names[(index + 1) % names.size()])
