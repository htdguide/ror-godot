class_name TreeLayer
extends RefCounted
## Reads a Rigs of Rods `trees` line: which tree grows on a terrain, how thickly, and how far.
##
## The line is positional and mixed: seven comma-separated numbers, then the file names
## space-separated after them. Upstream reads it with one `sscanf` —
## `TObjFileFormat.cpp`, `ProcessTreesLine`:
##
##     sscanf(m_cur_line, "trees %f, %f, %f, %f, %f, %f, %f, %s %s %s %f %s",
##         &tree.yaw_from,      &tree.yaw_to,
##         &tree.scale_from,    &tree.scale_to,
##         &tree.high_density,
##         &tree.min_distance,  &tree.max_distance,
##          tree.tree_mesh,      tree.color_map,         tree.density_map,
##         &tree.grid_spacing,   tree.collision_mesh);
##
## so Russia's `trees 0, 360, 0.07, 0.09, 1, 100, 800, fir06_30.mesh none Russia-TreeMesh.png`
## is a fir turned any way, scaled between 0.07 and 0.09, one per unit of density, drawn out to
## 800 m, with no colour map and its density painted in `Russia-TreeMesh.png`.
##
## The density map is what decides where a forest is. Without it a terrain is uniformly wooded,
## including its roads and its lake.

## Upstream's own defaults where a line leaves a field out.
const DEFAULT_GRID_M: float = 10.0
const DEFAULT_MAX_DISTANCE_M: float = 800.0
## A colour map named this is upstream's way of saying there is none.
const NO_MAP: String = "none"


## Reads one `trees` line as {"yaw_from", "yaw_to", "scale_from", "scale_to", "high_density",
## "min_distance", "max_distance", "mesh", "colour_map", "density_map", "grid_m",
## "collision_mesh"}.
static func read(line: Dictionary) -> Dictionary:
    var fields: PackedStringArray = line["fields"] as PackedStringArray
    # Everything from the eighth field on is space-separated, in one comma-field.
    var tail: PackedStringArray = PackedStringArray()
    if fields.size() > 7:
        tail = fields[7].split(" ", false)
    return {
        "yaw_from": _number(fields, 0, 0.0),
        "yaw_to": _number(fields, 1, 360.0),
        "scale_from": _number(fields, 2, 1.0),
        "scale_to": _number(fields, 3, 1.0),
        "high_density": _number(fields, 4, 1.0),
        "min_distance": _number(fields, 5, 0.0),
        "max_distance": _number(fields, 6, DEFAULT_MAX_DISTANCE_M),
        "mesh": _word(tail, 0),
        "colour_map": _word(tail, 1),
        "density_map": _word(tail, 2),
        # A grid spacing of zero means upstream's scattered placement on a 10 m grid; a negative
        # one means scattered on a grid of its own size; a positive one means one tree per cell.
        "grid_m": _word(tail, 3).to_float(),
        "collision_mesh": _word(tail, 4),
    }


## Whether a layer names everything it needs. Upstream refuses one with no density map, and says
## so: "tree DensityMap zero!".
static func is_complete(layer: Dictionary) -> bool:
    return (layer["mesh"] as String) != "" and (layer["density_map"] as String) != ""


## How far apart the placement grid is, and whether each cell holds one tree or a scatter.
static func grid_metres(layer: Dictionary) -> float:
    var stated: float = layer["grid_m"] as float
    if stated > 0.0:
        return stated
    if stated < 0.0:
        return -stated
    return DEFAULT_GRID_M


## A positive grid spacing means one tree per cell, at its middle, where the density is high.
static func is_regular(layer: Dictionary) -> bool:
    return (layer["grid_m"] as float) > 0.0


static func _number(fields: PackedStringArray, at: int, fallback: float) -> float:
    if at >= fields.size() or not fields[at].strip_edges().is_valid_float():
        return fallback
    return fields[at].strip_edges().to_float()


static func _word(words: PackedStringArray, at: int) -> String:
    if at >= words.size():
        return ""
    var out: String = words[at].strip_edges()
    return "" if out.to_lower() == NO_MAP else out
