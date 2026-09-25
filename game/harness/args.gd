class_name HarnessArgs
extends RefCounted
## Parses the arguments that follow `--` on the Godot command line.
##
## Accepts `--key value` and bare `--flag`. Unknown keys are an error rather than a
## silent no-op: a typo in a gate invocation must not quietly capture the default
## image and report success.

const KNOWN_VALUE_KEYS: Array[String] = [
    "gate", "shot", "scenario", "weather", "seed", "tick", "converge",
    "frames", "out", "movie", "width", "height", "at", "compare", "record",
    "replay", "golden", "vehicle",
]

const KNOWN_FLAGS: Array[String] = [
    "deterministic", "play", "update-golden", "list", "hud", "verbose", "terrain",
]

var values: Dictionary = {}
var flags: Dictionary = {}
var error: String = ""


func _init(raw: PackedStringArray) -> void:
    var i: int = 0
    while i < raw.size():
        var token: String = raw[i]
        if not token.begins_with("--"):
            error = "unexpected token '%s': arguments must start with --" % token
            return
        var key: String = token.substr(2)
        var inline_value: String = ""
        var eq: int = key.find("=")
        if eq >= 0:
            inline_value = key.substr(eq + 1)
            key = key.substr(0, eq)
        if KNOWN_FLAGS.has(key):
            flags[key] = true
            i += 1
            continue
        if not KNOWN_VALUE_KEYS.has(key):
            error = "unknown argument '--%s'" % key
            return
        if inline_value != "":
            values[key] = inline_value
            i += 1
            continue
        if i + 1 >= raw.size():
            error = "argument '--%s' needs a value" % key
            return
        values[key] = raw[i + 1]
        i += 2


func has_flag(name: String) -> bool:
    return flags.get(name, false) as bool


func get_string(key: String, fallback: String) -> String:
    return values.get(key, fallback) as String


func get_int(key: String, fallback: int) -> int:
    if not values.has(key):
        return fallback
    var raw: String = values[key] as String
    if not raw.is_valid_int():
        error = "argument '--%s' expects an integer, got '%s'" % [key, raw]
        return fallback
    return raw.to_int()


func describe() -> String:
    return "values=%s flags=%s" % [values, flags]
