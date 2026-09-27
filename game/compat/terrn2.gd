class_name Terrn2
extends RefCounted
## Reads a Rigs of Rods terrain's `.terrn2`: what the terrain is called, where its geometry is
## described, where a vehicle starts, and what gravity and water it asks for.
##
## The format is an INI with a handful of sections. `[General]` is key = value; `[Objects]` is a
## list of bare filenames, one `.tobj` per line. Comments start with `#` or `;`, and a commented
## key is upstream's own way of leaving an alternative in the file — La Paz ships two start
## positions with the unused one commented out — so a comment is dropped rather than parsed.
##
## Nothing here interprets the values. A terrain that states a gravity states it in its own file,
## and the reason to read it rather than choose one is that a terrain was built and driven against
## its own numbers.


## Reads a .terrn2. Returns a dictionary whose "error" is "" on success.
static func read(path: String) -> Dictionary:
    var out: Dictionary = {
        "error": "",
        "name": "",
        "geometry_config": "",
        "traction_map": "",
        "start_position": Vector3.ZERO,
        "gravity": -9.81,
        "water": false,
        "water_line": 0.0,
        "ambient": Color(1.0, 1.0, 1.0),
        "objects": PackedStringArray(),
    }
    var text: String = RorText.read(path)
    if text.is_empty():
        out["error"] = "the terrain config at %s could not be read" % path
        return out
    var section: String = ""
    for raw_line: String in text.split("\n"):
        var line: String = RorText.strip_comment(raw_line)
        if line.is_empty():
            continue
        if line.begins_with("[") and line.ends_with("]"):
            section = line.substr(1, line.length() - 2).to_lower()
            continue
        if section == "objects":
            # Written by an ini writer that puts every entry on the left of an `=`, so La Paz's
            # own file says `lapaz.tobj=` with nothing after it. The filename is the key.
            out["objects"] = _with(
                out["objects"] as PackedStringArray, line.get_slice("=", 0).strip_edges()
            )
            continue
        if not line.contains("="):
            continue
        _take(out, line.get_slice("=", 0).strip_edges().to_lower(),
            line.substr(line.find("=") + 1).strip_edges())
    if (out["name"] as String).is_empty():
        out["error"] = "%s states no Name" % path.get_file()
    return out


## One key from the `[General]` section, as the file spells it.
static func _take(out: Dictionary, key: String, value: String) -> void:
    match key:
        "name":
            out["name"] = value
        "geometryconfig":
            out["geometry_config"] = value
        "tractionmap":
            out["traction_map"] = value
        "startposition":
            out["start_position"] = RorText.vector3(value)
        "gravity":
            out["gravity"] = value.to_float()
        "water":
            # Upstream reads this as a flag: 0 is no water whatever the water line says.
            out["water"] = value.strip_edges() != "0" and value.to_lower() != "false"
        "waterline":
            out["water_line"] = value.to_float()
        "ambientcolor":
            var parts: PackedStringArray = value.split(",")
            if parts.size() >= 3:
                out["ambient"] = Color(
                    parts[0].to_float(), parts[1].to_float(), parts[2].to_float()
                )


static func _with(list: PackedStringArray, value: String) -> PackedStringArray:
    var out: PackedStringArray = list.duplicate()
    out.append(value)
    return out
