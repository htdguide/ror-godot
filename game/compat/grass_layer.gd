class_name GrassLayer
extends RefCounted
## Reads a Rigs of Rods vegetation line: what grows on a terrain, how big, how thick and where.
##
## The line is positional and its fields are upstream's `TObjParser`'s, in its order:
##
##     grass  range, sway speed, sway length, sway distribution, density,
##            min width, min height, max width, max height,
##            grow technique, lowest ground, highest ground,
##            material, colour map, density map
##
## `grass2` is the same with a render technique after the range. Both are read here, because a
## terrain that uses one is as common as a terrain that uses the other and the difference is one
## integer.
##
## The density map is what actually decides where grass is: a greyscale image over the whole
## terrain whose brightness is the share of the stated density that grows at that point. Without
## it a terrain is uniformly grassy, including its roads and its rock faces.

## What the fields mean when a terrain leaves them out, from upstream's own defaults.
const DEFAULT_RANGE_M: float = 80.0
const DEFAULT_DENSITY: float = 0.6
const DEFAULT_MIN_SIZE: Vector2 = Vector2(0.2, 0.2)
const DEFAULT_MAX_SIZE: Vector2 = Vector2(1.0, 0.6)
## Upstream's "no limit" heights. A terrain that states 0 and 0 means the same thing: a height
## band of zero metres would grow nothing at all, and every terrain that writes it is grassy.
const NO_LIMIT_M: float = 9999.0


## Reads one vegetation line as {"range_m", "density", "min_size", "max_size", "min_h", "max_h",
## "material", "colour_map", "density_map", "sway"}.
static func read(line: Dictionary) -> Dictionary:
    var fields: PackedStringArray = line["fields"] as PackedStringArray
    var grass2: bool = (line["line"] as String).begins_with("grass2")
    # grass2 puts a render technique after the range; nothing else differs.
    var at: int = 1 if grass2 else 0
    var out: Dictionary = {
        "range_m": _number(fields, 0, DEFAULT_RANGE_M),
        "sway": _number(fields, at + 1, 0.0),
        "density": _number(fields, at + 4, DEFAULT_DENSITY),
        "min_size": Vector2(
            _number(fields, at + 5, DEFAULT_MIN_SIZE.x),
            _number(fields, at + 6, DEFAULT_MIN_SIZE.y)
        ),
        "max_size": Vector2(
            _number(fields, at + 7, DEFAULT_MAX_SIZE.x),
            _number(fields, at + 8, DEFAULT_MAX_SIZE.y)
        ),
        "min_h": _number(fields, at + 10, -NO_LIMIT_M),
        "max_h": _number(fields, at + 11, NO_LIMIT_M),
        "material": "",
        "colour_map": "",
        "density_map": "",
    }
    # The last field is three space-separated names rather than commas, as the format has it.
    var names: PackedStringArray = _names(fields, at + 12)
    out["material"] = names[0] if names.size() > 0 else ""
    out["colour_map"] = _file(names, 1)
    out["density_map"] = _file(names, 2)
    if is_equal_approx(out["min_h"] as float, out["max_h"] as float):
        out["min_h"] = -NO_LIMIT_M
        out["max_h"] = NO_LIMIT_M
    return out


## Whether a point's ground height is inside a layer's band.
static func grows_at(layer: Dictionary, height: float) -> bool:
    return height >= (layer["min_h"] as float) and height <= (layer["max_h"] as float)


static func _number(fields: PackedStringArray, at: int, fallback: float) -> float:
    if at < 0 or at >= fields.size():
        return fallback
    var raw: String = fields[at].strip_edges()
    return raw.to_float() if raw.is_valid_float() else fallback


## The material, colour map and density map, which share the line's last comma field.
static func _names(fields: PackedStringArray, at: int) -> PackedStringArray:
    if at < 0 or at >= fields.size():
        return PackedStringArray()
    return fields[at].split(" ", false)


## One of those names, with the format's own "none" read as absent.
static func _file(names: PackedStringArray, at: int) -> String:
    if at >= names.size():
        return ""
    var name: String = names[at].strip_edges()
    return "" if name.to_lower() == "none" else name
