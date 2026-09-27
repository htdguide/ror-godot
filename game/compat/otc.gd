class_name Otc
extends RefCounted
## Reads a Rigs of Rods terrain's geometry config: the `.otc` a `.terrn2` names, and the page file
## that one names in turn.
##
## The `.otc` is key = value and describes the whole terrain: how big it is in metres, how tall its
## heightmap's full range is, and how many samples across. The page file is positional instead —
## first line the heightmap's filename, second the number of texture layers, then one line per
## layer — and it is where the raw heightmap is actually named.
##
## Two numbers here decide whether a terrain is the shape its author drew. `WorldSizeY` is the
## metres the heightmap's full 16-bit range spans, so a height is `sample / 65535 * WorldSizeY`;
## and the sample count is one more than the number of cells, because a 2049-sample page is
## 2048 cells of 1.953125 m across 4000 m. Reading either as the other puts the terrain at the
## wrong height or the wrong scale, both of which look plausible until something is driven on it.


## Reads a .otc. Returns a dictionary whose "error" is "" on success.
static func read(path: String) -> Dictionary:
    var out: Dictionary = {
        "error": "",
        "samples": 0,
        "bytes_per_sample": 2,
        "flip_x": false,
        "world_x": 0.0,
        "world_z": 0.0,
        "world_y": 0.0,
        "page_file": "",
    }
    var text: String = RorText.read(path)
    if text.is_empty():
        out["error"] = "the geometry config at %s could not be read" % path
        return out
    for raw_line: String in text.split("\n"):
        var line: String = RorText.strip_comment(raw_line)
        if not line.contains("="):
            continue
        var key: String = line.get_slice("=", 0).strip_edges().to_lower()
        var value: String = line.substr(line.find("=") + 1).strip_edges()
        match key:
            "heightmap.0.0.raw.size", "pagesize":
                out["samples"] = maxi(out["samples"] as int, value.to_int())
            "heightmap.0.0.raw.bpp":
                out["bytes_per_sample"] = value.to_int()
            "heightmap.0.0.flipx":
                out["flip_x"] = value.to_int() != 0
            "worldsizex":
                out["world_x"] = value.to_float()
            "worldsizez":
                out["world_z"] = value.to_float()
            "worldsizey":
                out["world_y"] = value.to_float()
            "pagefileformat":
                out["page_file"] = value
    if (out["samples"] as int) < 2:
        out["error"] = "%s states no heightmap size" % path.get_file()
    elif (out["world_x"] as float) <= 0.0 or (out["world_y"] as float) <= 0.0:
        out["error"] = "%s states no world size" % path.get_file()
    return out


## Reads the page file a .otc names: the heightmap and the texture layers.
##
## Positional, and blank lines carry no meaning, so the first two non-empty lines are the
## heightmap and the layer count and everything after them is a layer.
static func read_page(path: String) -> Dictionary:
    var out: Dictionary = {
        "error": "",
        "heightmap": "",
        "layers": [] as Array[Dictionary],
    }
    var text: String = RorText.read(path)
    if text.is_empty():
        out["error"] = "the page file at %s could not be read" % path
        return out
    var wanted: int = 0
    var layers: Array[Dictionary] = []
    for raw_line: String in text.split("\n"):
        var line: String = RorText.strip_comment(raw_line)
        if line.is_empty():
            continue
        if (out["heightmap"] as String).is_empty():
            out["heightmap"] = line
            continue
        if wanted == 0:
            wanted = line.to_int()
            continue
        if layers.size() >= wanted:
            continue
        layers.append(_layer(RorText.fields(line)))
    out["layers"] = layers
    if (out["heightmap"] as String).is_empty():
        out["error"] = "%s names no heightmap" % path.get_file()
    elif layers.size() < wanted:
        out["error"] = "%s promises %d layers and lists %d" % [
            path.get_file(), wanted, layers.size()
        ]
    return out


## One texture layer: how many metres it tiles over, its textures, and which channel of which
## blend map selects it. The first layer has no blend map — it is what everything else is
## painted over.
static func _layer(fields: PackedStringArray) -> Dictionary:
    return {
        "tile_m": fields[0].to_float() if fields.size() > 0 else 0.0,
        "albedo": fields[1] if fields.size() > 1 else "",
        "normal": fields[2] if fields.size() > 2 else "",
        "blend_map": fields[3] if fields.size() > 3 else "",
        "channel": (fields[4] if fields.size() > 4 else "").to_upper(),
        "alpha": fields[5].to_float() if fields.size() > 5 else 1.0,
    }
