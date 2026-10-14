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
    # Upstream's indicator keys, comma and period; X turns them off.
    "indicator_left": [KEY_COMMA], "indicator_right": [KEY_PERIOD], "indicators_off": [KEY_X],
    # Upstream's gearbox keys (`GearboxKeys`): Q the mode, A and Z a gear up and down, D neutral,
    # PgUp and PgDn the automatic selector, Left Shift the manual clutch.
    "shift_mode": [KEY_Q], "shift_up": [KEY_A], "shift_down": [KEY_Z], "shift_neutral": [KEY_D],
    "auto_up": [KEY_PAGEUP], "auto_down": [KEY_PAGEDOWN], "clutch": [KEY_SHIFT],
    # Upstream's hazards key (minus), and the fog lights, Alt+N there.
    "hazards": [KEY_MINUS], "fog_lights": [KEY_F],
    # Upstream's differential switches: each axle's own, and the ones between axles.
    "wheel_diffs": [KEY_V], "axle_diffs": [KEY_J],
    # Upstream's transfer case keys, Ctrl+W and Shift+W there: 2WD or 4WD, and high or low range.
    "transfer_case": [KEY_T], "transfer_range": [KEY_Y],
    # Upstream's tie key: every tie reaches for the nearest ropable, or lets go.
    "ties": [KEY_O],
    # Command keys 1 to 10, in order: a vehicle's own rams, its doors on the hero. Upstream puts
    # them on F1-F12, which this window answers to itself.
    "commands": [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0],
}

## Actions on Shift and a key in the one-driver window: upstream's driving aid toggles.
const SOLO_SHIFTED: Dictionary = {"antilock": KEY_B, "traction_control": KEY_T, "cruise_control": KEY_SPACE}
const SHIFTED_NAMES: Dictionary = {"antilock": "ABS", "traction_control": "traction control",
        "cruise_control": "cruise control (Ctrl+R faster, Ctrl+F slower, Ctrl+Space match)"}
## Rigs of Rods' cruise control adjusting keys, held: faster, slower, match the current speed.
const CRUISE_HELD: Array[Key] = [KEY_R, KEY_F, KEY_SPACE]

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
    "hazards": "hazards", "fog_lights": "fog lights", "hook": "hooks (Alt: let auto-locks go, Ctrl: ropes)",
    "wheel_diffs": "axle differentials", "axle_diffs": "interaxle differentials",
    "transfer_case": "2WD/4WD", "transfer_range": "high/low range",
    "ties": "ties",
    "shift_mode": "gearbox mode", "shift_up": "gear up", "shift_down": "gear down", "shift_neutral": "gear neutral",
    "auto_up": "selector up", "auto_down": "selector down", "clutch": "clutch (manual modes)",
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
    if keys == SOLO:
        for action: String in SOLO_SHIFTED:
            parts.append("Shift+%s %s" % [OS.get_keycode_string(SOLO_SHIFTED[action]), SHIFTED_NAMES[action]])
    return "%s  %s" % [label, ", ".join(parts)]


## Shift+Space and Ctrl+Space are cruise control's, so Space with either is not the handbrake.
static func cruise_modifier(keys: Dictionary) -> bool:
    return keys == SOLO and (Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL))


## Whether `keycode` with Ctrl down is a cruise control key in `keys`, which nothing else may take.
static func is_cruise_key(keys: Dictionary, keycode: Key) -> bool:
    return keys == SOLO and Input.is_key_pressed(KEY_CTRL) and CRUISE_HELD.has(keycode)


## Upstream's `UpdateTruckFeatures` once a frame after the driver's own controls: the cruise
## control while it is on (one driver's keys only), then the speed limiter, which every vehicle has.
static func drive_cruise(solver: RefCounted, keys: Dictionary, delta: float) -> void:
    if keys == SOLO and solver.cruise_control_on():
        var ctrl: bool = Input.is_key_pressed(KEY_CTRL)
        solver.update_cruise_control(delta, 1.0 if held(keys, "brake") else 0.0, 1.0 if held(keys, "throttle") else 0.0,
                ctrl and Input.is_key_pressed(KEY_R), ctrl and Input.is_key_pressed(KEY_F), ctrl and Input.is_key_pressed(KEY_SPACE))
    solver.update_speed_limiter()
