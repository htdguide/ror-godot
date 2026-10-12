class_name DriveKeys
extends RefCounted
## Which key does what for a driver, as data, so one window can hold two drivers.
##
## The play window used to read its keys straight off the keyboard inside `PlayDrive`: Up was the
## throttle wherever there was a vehicle. Splitscreen (PLAN §0.12, the test for islands) puts two
## vehicles in one window, one on WASD and one on the arrow keys, and two drivers cannot both own
## Up. So a driver is handed a map, and the map is the only place a key is named.
##
## Each action lists every key that does it. `SOLO` is the one-driver window exactly as it was;
## the two split maps leave out what a split session does not need (indicators, main beam) and
## stay off every key the session itself answers to (F1-F8, M, P, Esc).

## Held actions are read every frame; the rest fire once per press. `commands` is held too, one
## key per command number.
const HELD: PackedStringArray = ["throttle", "brake", "left", "right", "parking", "commands"]

const SOLO: Dictionary = {
    "throttle": [KEY_UP], "brake": [KEY_DOWN], "left": [KEY_LEFT], "right": [KEY_RIGHT],
    "parking": [KEY_SPACE],
    "drive": [KEY_G], "reverse": [KEY_B], "neutral": [KEY_H],
    "respawn": [KEY_R, KEY_BACKSPACE], "recover": [KEY_ENTER], "ignition": [KEY_I],
    "lights": [KEY_N], "main_beam": [KEY_K],
    # Upstream's lock key: every hook reaches for the nearest node in range, or lets go. Alt+L lets
    # the auto-lock hooks go.
    "hook": [KEY_L],
    "indicator_left": [KEY_Z], "indicator_right": [KEY_C], "indicators_off": [KEY_X],
    # Upstream's hazards key (minus), and the fog lights, Alt+N there.
    "hazards": [KEY_MINUS], "fog_lights": [KEY_F],
    # Upstream's differential switches: each axle's own, and the ones between axles.
    "wheel_diffs": [KEY_V], "axle_diffs": [KEY_J],
    # Upstream's transfer case keys, Ctrl+W and Shift+W there: 2WD or 4WD, and high or low range.
    "transfer_case": [KEY_T], "transfer_range": [KEY_Y],
    # Upstream's driving aid toggles, Shift+B and Shift+T there.
    "antilock": [KEY_O], "traction_control": [KEY_U],
    # Command keys 1 to 10, in order: a vehicle's own rams, its doors on the hero. Upstream puts
    # them on F1-F12, which this window answers to itself.
    "commands": [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0],
}

## The left half of a split window.
const SPLIT_LEFT: Dictionary = {
    "throttle": [KEY_W], "brake": [KEY_S], "left": [KEY_A], "right": [KEY_D],
    "parking": [KEY_SPACE],
    "drive": [KEY_E], "reverse": [KEY_Q], "neutral": [KEY_X],
    "respawn": [KEY_R], "recover": [KEY_F], "ignition": [KEY_1], "lights": [KEY_T],
}

## The right half: the arrows, and the keys beside them on a laptop that has no keypad.
const SPLIT_RIGHT: Dictionary = {
    "throttle": [KEY_UP], "brake": [KEY_DOWN], "left": [KEY_LEFT], "right": [KEY_RIGHT],
    "parking": [KEY_SLASH],
    "drive": [KEY_PERIOD], "reverse": [KEY_COMMA], "neutral": [KEY_APOSTROPHE],
    "respawn": [KEY_BRACKETRIGHT], "recover": [KEY_BRACKETLEFT], "ignition": [KEY_BACKSLASH],
    "lights": [KEY_SEMICOLON],
}

## What each action is called in the help text, in the order it is listed.
const NAMES: Dictionary = {
    "throttle": "throttle", "brake": "brake", "left": "left", "right": "right",
    "parking": "handbrake", "drive": "drive", "reverse": "reverse", "neutral": "neutral",
    "respawn": "respawn", "recover": "recover", "ignition": "ignition", "lights": "lights",
    "main_beam": "main beam", "indicator_left": "left indicator",
    "indicator_right": "right indicator", "indicators_off": "indicators off",
    "hazards": "hazards", "fog_lights": "fog lights", "hook": "hooks (Alt: let auto-locks go)",
    "wheel_diffs": "axle differentials", "axle_diffs": "interaxle differentials",
    "transfer_case": "2WD/4WD", "transfer_range": "high/low range",
    "antilock": "ABS", "traction_control": "traction control",
    "commands": "commands 1-10 (doors, rams)",
}


## The action a key does in `keys`, or "" for none.
static func action_of(keys: Dictionary, keycode: Key) -> String:
    for action: String in keys:
        if (keys[action] as Array).has(keycode):
            return action
    return ""


## Whether any key for `action` is held down now.
static func held(keys: Dictionary, action: String) -> bool:
    for keycode: Key in keys.get(action, []) as Array:
        if Input.is_key_pressed(keycode):
            return true
    return false


## One line per driver for the help text, read off the map itself.
static func help(keys: Dictionary, label: String) -> String:
    var parts: PackedStringArray = PackedStringArray()
    for action: String in NAMES:
        if not keys.has(action):
            continue
        var names: PackedStringArray = PackedStringArray()
        for keycode: Key in keys[action] as Array:
            names.append(OS.get_keycode_string(keycode))
        parts.append("%s %s" % ["/".join(names), NAMES[action]])
    return "%s  %s" % [label, ", ".join(parts)]
