class_name RorTerrainLibrary
extends RefCounted
## What terrains this checkout holds, and what each one says about itself.
##
## A terrain is a `.terrn2`. Nothing is registered, indexed or converted: the library is the
## filesystem, so a terrain downloaded from the repository five minutes ago is playable without
## a build step.
##
## Two places are searched. `assets/terrains/` is where a downloaded terrain is unpacked, and it
## is gitignored, because the repository's terrains carry varied and often unstated licensing.
## Rigs of Rods' own shipped content is the other, and it is a pinned submodule under GPL, so a
## fresh clone of this project can open a window on a real Rigs of Rods terrain with nothing
## downloaded at all — which is what the game itself starts with.
##
## The unit is the `.terrn2` and not the directory it sits in, because one directory is often
## several terrains: upstream's shipped map is one set of files and three `.terrn2` over it,
## gravel, asphalt and flooded, and Rigs of Rods lists all three. Keying on the directory would
## have shown one of them, chosen by whatever order the filesystem answered in.
##
## What is reported about each one comes from its own files — its name, how big it is, where it
## starts a vehicle — because that is what a person choosing between them wants, and because a
## terrain that cannot answer those is a terrain that will not load.

## Where downloaded terrains live in this checkout: the build profile's to say (`BuildProfile`).
static func root() -> String:
    return SourceScan.repo_root().path_join(BuildProfile.terrain_root())


## The directories terrains are looked for in: the library, then upstream's shipped content
## where the build bundles it. The production build bundles none.
static func roots() -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray([root()])
    var shipped: String = BuildProfile.shipped_root()
    if shipped != "":
        out.append(SourceScan.repo_root().path_join(shipped))
    return out


## Every terrain this checkout holds: {"name", "directory"}, in a stable order.
##
## `name` is the `.terrn2`'s own basename, which is what a session names on the command line.
static func entries() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var seen: Dictionary = {}
    for base: String in roots():
        if not DirAccess.dir_exists_absolute(base):
            continue
        for directory: String in DirAccess.get_directories_at(base):
            var full: String = base.path_join(directory)
            for terrn2: String in _terrn2_names_in(full):
                # A downloaded terrain wins a name clash with a shipped one: somebody put it
                # there on purpose.
                if seen.has(terrn2):
                    continue
                seen[terrn2] = true
                out.append({"name": terrn2, "directory": full})
    out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return (a["name"] as String) < (b["name"] as String)
    )
    return out


## Every terrain's name, in a stable order.
static func names() -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    for entry: Dictionary in entries():
        out.append(entry["name"] as String)
    return out


## What each terrain says about itself: {"name", "title", "directory", "size_m", "start", "error"}.
##
## A terrain that will not load is listed with its error rather than left out, because "it is not
## in the list" and "it is broken" are different problems and only one of them is the library's.
static func summaries() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for entry: Dictionary in entries():
        var name: String = entry["name"] as String
        var directory: String = entry["directory"] as String
        var loaded: Dictionary = RorTerrain.load_from(directory, name)
        if (loaded["error"] as String) != "":
            out.append({
                "name": name,
                "title": name,
                "directory": directory,
                "size_m": 0.0,
                "start": Vector3.ZERO,
                "error": loaded["error"] as String,
            })
            continue
        var terrain: RorTerrain = loaded["terrain"] as RorTerrain
        out.append({
            "name": name,
            "title": terrain.name,
            "directory": directory,
            "size_m": terrain.geometry["world_x"] as float,
            "start": terrain.start_position(),
            "error": "",
        })
    return out


## The terrain a name refers to, as {"directory", "terrn2"}. `directory` is "" when there is no
## terrain by that name.
##
## A library name is the `.terrn2`'s basename. A path to a directory also works, and takes the
## one `.terrn2` in it, so a terrain that has not been imported can still be driven where it lies.
static func resolve(wanted: String) -> Dictionary:
    var missing: Dictionary = {"directory": "", "terrn2": ""}
    if wanted.is_empty():
        return missing
    for entry: Dictionary in entries():
        if (entry["name"] as String) == wanted:
            return {"directory": entry["directory"] as String, "terrn2": wanted}
    var direct: String = wanted
    if not direct.is_absolute_path():
        direct = SourceScan.repo_root().path_join(wanted)
    var in_directory: PackedStringArray = _terrn2_names_in(direct)
    if not in_directory.is_empty():
        return {"directory": direct, "terrn2": in_directory[0]}
    return missing


## Loads the terrain a name refers to. Returns `RorTerrain.load_from`'s own result, with the
## error naming the library when there is nothing by that name.
static func load_named(wanted: String) -> Dictionary:
    var found: Dictionary = resolve(wanted)
    if (found["directory"] as String).is_empty():
        return {
            "error": "there is no terrain called '%s'; the library holds %s" % [
                wanted, ", ".join(names())
            ],
            "terrain": null,
        }
    return RorTerrain.load_from(found["directory"] as String, found["terrn2"] as String)


## The basenames of the .terrn2 files in a directory, sorted.
static func _terrn2_names_in(directory: String) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    if not DirAccess.dir_exists_absolute(directory):
        return out
    for file: String in DirAccess.get_files_at(directory):
        if file.get_extension().to_lower() == "terrn2":
            out.append(file.get_basename())
    out.sort()
    return out
