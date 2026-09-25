class_name CameraCfg
extends RefCounted
## Named camera presets. Data only.
##
## A preset is physical: focal length in mm, aperture in f-stops, shutter in seconds.
## Depth of field then follows from the lens instead of being dialled by hand, and
## exposure is comparable between presets. Auto-exposure is never used in a gate,
## because its convergence is temporal and would make captures non-deterministic.
##
## Keys:
##   pos          Vector3 camera position in world space
##   look_at      Vector3 world point the camera aims at
##   focal_mm     float focal length, 35mm-equivalent
##   f_stop       float aperture
##   shutter_s    float shutter speed in seconds, also drives motion blur length
##   exposure     float fixed exposure multiplier
##   scenario     String scenario name from Scenarios
##   weather      String preset name from WeatherCfg

const PRESETS: Dictionary = {
    # Diagnostic presets. Plain framings whose job is to make a specific defect
    # visible, not to look good.
    "diag_origin": {
        "pos": Vector3(6.0, 3.0, 6.0),
        "look_at": Vector3(0.0, 0.5, 0.0),
        "focal_mm": 35.0,
        "f_stop": 8.0,
        "shutter_s": 0.008,
        "exposure": 1.0,
        "scenario": "static",
        "weather": "noon_clear",
    },
    # Frames the spike lattice, which spans roughly 9.6 x 4.8 x 8.0 metres.
    "diag_lattice": {
        "pos": Vector3(13.0, 9.0, 16.0),
        "look_at": Vector3(4.8, 2.4, 4.0),
        "focal_mm": 40.0,
        "f_stop": 11.0,
        "shutter_s": 0.008,
        "exposure": 1.0,
        "scenario": "static",
        "weather": "spike_black",
    },
    "diag_grid_wide": {
        "pos": Vector3(0.0, 24.0, 32.0),
        "look_at": Vector3(0.0, 0.0, 0.0),
        "focal_mm": 24.0,
        "f_stop": 11.0,
        "shutter_s": 0.008,
        "exposure": 1.0,
        "scenario": "static",
        "weather": "noon_clear",
    },
}


static func has(preset: String) -> bool:
    return PRESETS.has(preset)


static func get_preset(preset: String) -> Dictionary:
    return PRESETS.get(preset, {}) as Dictionary


static func names() -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    for key: String in PRESETS.keys():
        out.append(key)
    return out
