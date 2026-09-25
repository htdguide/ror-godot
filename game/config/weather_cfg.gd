class_name WeatherCfg
extends RefCounted
## Time-of-day and weather presets. Data only.
##
## A preset is selectable from the command line, so any gate can be run under any
## lighting without a second scene. M0 defines only what a blockout world needs;
## M2 fills in the full set once there is a sky, fog and PBR materials to drive.
##
## Keys:
##   sun_euler_deg  Vector3 directional light rotation in degrees
##   sun_energy     float directional light energy
##   sun_color      Color directional light colour
##   ambient_energy float flat ambient energy, replaced by sky IBL at M2
##   bg_color       Color clear colour, replaced by a sky at M2

const PRESETS: Dictionary = {
    "noon_clear": {
        "sun_euler_deg": Vector3(-65.0, -35.0, 0.0),
        "sun_energy": 1.0,
        "sun_color": Color(1.0, 0.97, 0.92),
        "ambient_energy": 0.35,
        "bg_color": Color(0.42, 0.55, 0.72),
    },
    "golden_dusk": {
        "sun_euler_deg": Vector3(-8.0, -110.0, 0.0),
        "sun_energy": 1.4,
        "sun_color": Color(1.0, 0.72, 0.45),
        "ambient_energy": 0.18,
        "bg_color": Color(0.26, 0.24, 0.32),
    },
}


static func has(preset: String) -> bool:
    return PRESETS.has(preset)


static func get_preset(preset: String) -> Dictionary:
    return PRESETS.get(preset, {}) as Dictionary
