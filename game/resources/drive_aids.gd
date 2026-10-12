class_name DriveAids
extends RefCounted
## Reads `AntiLockBrakes` and `TractionControl` lines: upstream's `ParseAntiLockBrakes` and
## `ParseTractionControl`, then the clamps its spawner applies (`ProcessAntiLockBrakes`,
## `ProcessTractionControl`).
##
##   AntiLockBrakes  regulation_force, min_speed_kmh, pulse_per_sec, mode: ON & NODASH & NOTOGGLE
##   TractionControl regulation_force, wheel_slip, fade_speed, pulse_per_sec, mode: ...
##
## Upstream splits what follows the keyword on commas only. The slip and fade speed are read and
## no longer used upstream; ABS reads its pulse only when a fourth field follows it, a quirk kept.


## Fills `drive["abs"]` or `drive["tc"]` from one line; an error, or "".
static func read(section: String, line: String, drive: Dictionary) -> String:
    var keyword_length: int = "antilockbrakes".length() if section == "antilockbrakes" else "tractioncontrol".length()
    var tokens: PackedStringArray = line.substr(keyword_length).split(",")
    if tokens.size() < 2:
        return "%s states %d values, needs 2" % [section, tokens.size()]
    var aid: Dictionary = {
        "ratio": clampf(tokens[0].strip_edges().to_float(), 1.0, 20.0),
        "on": section == "antilockbrakes",
        "toggle": true,
        "pulse_time": 1.0 / 2000.0,
    }
    var pulse: float = 0.0
    var first_mode: int = 3
    if section == "antilockbrakes":
        # km/h to m/s, and never under 0.5 m/s.
        aid["min_speed"] = maxf(0.5, float(tokens[1].strip_edges().to_int()) / 3.6)
        if tokens.size() > 3:
            pulse = tokens[2].strip_edges().to_float()
    else:
        first_mode = 4
        if tokens.size() > 3:
            pulse = tokens[3].strip_edges().to_float()
    if pulse > 1.0 and pulse < 2000.0:
        aid["pulse_time"] = 1.0 / pulse
    for i: int in range(first_mode, tokens.size()):
        var pair: PackedStringArray = tokens[i].split(":")
        if pair[0].strip_edges().to_lower() == "mode" and pair.size() == 2:
            for attr: String in pair[1].split("&"):
                var word: String = attr.strip_edges().to_lower()
                if word.begins_with("notoggle"):
                    aid["toggle"] = false
                elif word.begins_with("on"):
                    aid["on"] = true
                elif word.begins_with("off"):
                    aid["on"] = false
        else:
            # Upstream's "missing mode": anything else there puts the aid back on and toggleable.
            aid["on"] = true
            aid["toggle"] = true
    drive["abs" if section == "antilockbrakes" else "tc"] = aid
    return ""
