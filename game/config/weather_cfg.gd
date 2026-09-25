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
        # Lit by a physical sky rather than a flat colour, so surfaces have something to
        # reflect and shadows are filled by sky light instead of a constant.
        "physical_sky": true,
        "sky_energy": 1.0,
        "sun_euler_deg": Vector3(-55.0, -125.0, 0.0),
        # A clear midday sun is bright, and the sky fills the shadows on its own. With a
        # physical sky the ambient term is the sky's own irradiance rather than a flat
        # colour, so it runs at full strength instead of being dialled down.
        "sun_energy": 1.6,
        "sun_color": Color(1.0, 0.97, 0.92),
        "ambient_energy": 1.0,
        "bg_color": Color(0.42, 0.55, 0.72),
    },
    # A black, unlit environment. Measurement gates encode numbers into pixels, so any
    # ambient contribution would be added to the value being read back.
    "spike_black": {
        "sun_euler_deg": Vector3(-90.0, 0.0, 0.0),
        "sun_energy": 0.0,
        "sun_color": Color(0.0, 0.0, 0.0),
        "ambient_energy": 0.0,
        "bg_color": Color(0.0, 0.0, 0.0),
    },
    "golden_dusk": {
        "physical_sky": true,
        "sky_energy": 1.0,
        "sun_euler_deg": Vector3(-8.0, -110.0, 0.0),
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
