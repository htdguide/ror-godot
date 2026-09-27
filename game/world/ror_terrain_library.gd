class_name RorTerrainLibrary
extends RefCounted
## What terrains this checkout holds, and what each one says about itself.
##
## A terrain is a directory with a `.terrn2` in it, dropped under `assets/terrains/`. Nothing is
## registered, indexed or converted: the library is the filesystem, so a terrain downloaded from
## the repository five minutes ago is playable without a build step.
##
## What is reported about each one comes from its own files — its name, how big it is, where it
## starts a vehicle — because that is what a person choosing between them wants, and because a
## terrain that cannot answer those is a terrain that will not load.

const TERRAIN_ROOT: String = "assets/terrains"


## Where terrains live in this checkout.
static func root() -> String:
    return SourceScan.repo_root().path_join(TERRAIN_ROOT)


## Every terrain directory, by name, in a stable order.
static func names() -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    var base: String = root()
    if not DirAccess.dir_exists_absolute(base):
        return out
    for directory: String in DirAccess.get_directories_at(base):
        if _terrn2_in(base.path_join(directory)) != "":
            out.append(directory)
    out.sort()
    return out


## What each terrain says about itself: {"directory", "name", "title", "size_m", "start", "error"}.
##
## A terrain that will not load is listed with its error rather than left out, because "it is not
## in the list" and "it is broken" are different problems and only one of them is the library's.
static func summaries() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for name: String in names():
        var directory: String = root().path_join(name)
        var loaded: Dictionary = RorTerrain.load_from(directory)
        if (loaded["error"] as String) != "":
            out.append({
                "directory": name,
                "name": name,
                "size_m": 0.0,
                "start": Vector3.ZERO,
                "error": loaded["error"] as String,
            })
            continue
        var terrain: RorTerrain = loaded["terrain"] as RorTerrain
        out.append({
            "directory": name,
            "name": terrain.name,
            "size_m": terrain.geometry["world_x"] as float,
            "start": terrain.start_position(),
            "error": "",
        })
    return out


## The directory a name refers to, whether it is a library name or a path. Returns "" when there
## is no terrain there.
static func resolve(wanted: String) -> String:
    if wanted.is_empty():
        return ""
    var direct: String = wanted
    if not direct.is_absolute_path():
        direct = SourceScan.repo_root().path_join(wanted)
    if _terrn2_in(direct) != "":
        return direct
    var in_library: String = root().path_join(wanted)
    if _terrn2_in(in_library) != "":
        return in_library
    return ""


## The .terrn2 in a directory, or "" when it holds none.
static func _terrn2_in(directory: String) -> String:
    if not DirAccess.dir_exists_absolute(directory):
        return ""
    for file: String in DirAccess.get_files_at(directory):
        if file.get_extension().to_lower() == "terrn2":
            return directory.path_join(file)
    return ""
