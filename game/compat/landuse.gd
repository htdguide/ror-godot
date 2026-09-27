class_name Landuse
extends RefCounted
## Reads a Rigs of Rods terrain's traction map config: which colour in an image means which
## surface a vehicle grips.
##
## This is the whole of a terrain's friction description. A pixel of the named image covers a
## patch of ground, its colour is looked up in `[use-map]`, and the surface that comes back is a
## ground model — the numbers that decide whether a wheel holds or lets go. A colour with no entry
## is the file's own `defaultuse`, which is why La Paz can leave `softsand` commented out in its
## map and still expect sand everywhere it did not paint.
##
## Colours are written `0xAARRGGBB` and the alpha byte is always `ff`. It is dropped here: an
## image's alpha is not what identifies a surface, and comparing a three-channel pixel against a
## four-byte key is how a traction map silently becomes one surface everywhere.


## Reads a landuse config. Returns a dictionary whose "error" is "" on success.
static func read(path: String) -> Dictionary:
    var out: Dictionary = {
        "error": "",
        "texture": "",
        "default_use": "",
        "ground_model_configs": PackedStringArray(),
        "surfaces": {},
    }
    var text: String = RorText.read(path)
    if text.is_empty():
        out["error"] = "the traction map config at %s could not be read" % path
        return out
    var section: String = ""
    var surfaces: Dictionary = {}
    var configs: PackedStringArray = PackedStringArray()
    for raw_line: String in text.split("\n"):
        var line: String = RorText.strip_comment(raw_line)
        if line.is_empty():
            continue
        if line.begins_with("[") and line.ends_with("]"):
            section = line.substr(1, line.length() - 2).to_lower()
            continue
        if not line.contains("="):
            continue
        var key: String = line.get_slice("=", 0).strip_edges()
        var value: String = line.substr(line.find("=") + 1).strip_edges()
        if section == "use-map":
            surfaces[colour_key(key)] = value.to_lower()
            continue
        match key.to_lower():
            "texture":
                out["texture"] = value
            "defaultuse":
                out["default_use"] = value.to_lower()
            "loadgroundmodelsconfig":
                configs.append(value)
    out["surfaces"] = surfaces
    out["ground_model_configs"] = configs
    if (out["texture"] as String).is_empty():
        out["error"] = "%s names no traction map image" % path.get_file()
    return out


## The key a colour is stored under: its three colour bytes, alpha dropped.
static func colour_key(written: String) -> int:
    return written.strip_edges().hex_to_int() & 0xFFFFFF


## The same key for a pixel of the traction map image.
static func pixel_key(pixel: Color) -> int:
    var red: int = clampi(int(round(pixel.r * 255.0)), 0, 255)
    var green: int = clampi(int(round(pixel.g * 255.0)), 0, 255)
    var blue: int = clampi(int(round(pixel.b * 255.0)), 0, 255)
    return (red << 16) | (green << 8) | blue


## Which surface a pixel means, or the config's own default where the colour is not in the map.
static func surface_of(config: Dictionary, pixel: Color) -> String:
    var surfaces: Dictionary = config["surfaces"] as Dictionary
    var key: int = pixel_key(pixel)
    if surfaces.has(key):
        return surfaces[key] as String
    return config["default_use"] as String
