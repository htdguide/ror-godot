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
##
## Most keys are optional, and a terrain that omits one means upstream's default rather than zero.
## The defaults here are `OTCParser::LoadMasterConfig`'s own, field for field, because a terrain
## written against them is a terrain that states only what it changes: Rigs of Rods' own shipped
## map sets four keys and leaves nine to the parser.
##
## `Flat=1` is the case where there is no heightmap at all. Upstream defines the page at height
## zero and `TerrainGeometryManager::getHeightAt` returns 0.0 before it looks at anything, so the
## page file's heightmap name is never opened — which is why the shipped map names a `.png` it
## does not ship. A flat terrain still has a size, a lattice and texture layers; it just has no
## relief, so `WorldSizeY` is meaningless on one and is not required to be set.


## Upstream's own defaults for the keys a terrain may omit, from `OTCParser::LoadMasterConfig`.
## A terrain that leaves `PageSize` out is a 1025-sample terrain, not a zero-sample one.
const DEFAULT_SAMPLES: int = 1025
const DEFAULT_BYTES_PER_SAMPLE: int = 2
const DEFAULT_WORLD_X: float = 1024.0
const DEFAULT_WORLD_Y: float = 50.0
const DEFAULT_WORLD_Z: float = 1024.0


## Reads a .otc. Returns a dictionary whose "error" is "" on success.
static func read(path: String) -> Dictionary:
    var out: Dictionary = {
        "error": "",
        "samples": DEFAULT_SAMPLES,
        "bytes_per_sample": DEFAULT_BYTES_PER_SAMPLE,
        "flip_x": false,
        "flat": false,
        "world_x": DEFAULT_WORLD_X,
        "world_z": DEFAULT_WORLD_Z,
        "world_y": DEFAULT_WORLD_Y,
        "page_file": "%s-page-0-0.otc" % path.get_file().get_basename(),
    }
    var text: String = RorText.read(path)
    if text.is_empty():
        out["error"] = "the geometry config at %s could not be read" % path
        return out
    # A stated size wins over the default, and the two keys that can state it agree or the
    # larger is the page: upstream reads both and a terrain sets whichever its author knew.
    var stated_samples: int = 0
    for raw_line: String in text.split("\n"):
        var line: String = RorText.strip_comment(raw_line)
        if not line.contains("="):
            continue
        var key: String = line.get_slice("=", 0).strip_edges().to_lower()
        var value: String = line.substr(line.find("=") + 1).strip_edges()
        match key:
            "heightmap.0.0.raw.size", "pagesize":
                stated_samples = maxi(stated_samples, value.to_int())
            "heightmap.0.0.raw.bpp":
                out["bytes_per_sample"] = value.to_int()
            "heightmap.0.0.flipx":
                out["flip_x"] = value.to_int() != 0
            "flat":
                out["flat"] = value.to_int() != 0
            "worldsizex":
                out["world_x"] = value.to_float()
            "worldsizez":
                out["world_z"] = value.to_float()
            "worldsizey":
                out["world_y"] = value.to_float()
            "pagefileformat":
                out["page_file"] = value
    if stated_samples >= 2:
        out["samples"] = stated_samples
    # Upstream's format string names the page by index. This project reads the one page at 0,0,
    # so a terrain that writes the placeholders rather than the numbers means the same page.
    out["page_file"] = (out["page_file"] as String).replace("{X}", "0").replace("{Z}", "0")
    if (out["samples"] as int) < 2:
        out["error"] = "%s states a heightmap of %d samples" % [
            path.get_file(), out["samples"]
        ]
    elif (out["world_x"] as float) <= 0.0 or (out["world_z"] as float) <= 0.0:
        out["error"] = "%s states no world size" % path.get_file()
    elif not (out["flat"] as bool) and (out["world_y"] as float) <= 0.0:
        # A relief terrain with no height range is a terrain that would load as a plane while
        # claiming to have hills, which is the failure this reader exists to make loud.
        out["error"] = "%s states no height range and is not flat" % path.get_file()
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
