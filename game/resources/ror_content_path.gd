class_name RorContentPath
extends RefCounted
## Where to look for a file a mod names but does not ship.
##
## **Rigs of Rods resolves content by name, not by path.** Ogre's resource groups pool every
## registered directory, so a terrain that says `seat.mesh` or a mesh that asks for the material
## `tracks/master` gets the game's own copy without saying where it is. This project looked only
## in the folder the mod was unpacked into, so every one of those came back missing.
##
## Measured before this existed: Starling Island's vehicles ask for `seat.mesh`,
## `dashboard-small.mesh` and `lightbar.mesh`; its scenery asks for the materials `tracks/master`
## and `default`; 56 named meshes across the library resolved to nothing and 48 object surfaces
## drew untextured. All of it is in `vendor/rigs-of-rods/resources`, which is a pinned submodule
## this checkout already has — the content was never missing, it was never looked for.
##
## The mod's own directory always wins. A pack that ships its own `seat.mesh` means that one.

## The game's own resource directories, under the pinned upstream checkout. Ogre registers these
## at startup and every mod may name anything in them.
const BASE_ROOT: String = "vendor/rigs-of-rods/resources"
const BASE_DIRECTORIES: PackedStringArray = [
    "meshes", "materials", "managed_materials", "textures", "beamobjects",
]


## Every directory a file may be found in, the mod's own first.
static func roots(local_directory: String) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray([local_directory])
    var base: String = SourceScan.repo_root().path_join(BASE_ROOT)
    for directory: String in BASE_DIRECTORIES:
        out.append(base.path_join(directory))
    return out


## The first directory holding `file`, or the mod's own when nothing does — so a caller that
## wants to report a missing file still gets the path it expected.
static func find(file: String, local_directory: String) -> String:
    if file.is_empty():
        return local_directory.path_join(file)
    for directory: String in roots(local_directory):
        var path: String = directory.path_join(file)
        if FileAccess.file_exists(path):
            return path
    return local_directory.path_join(file)


## Whether `file` exists anywhere a mod may name it from.
static func has(file: String, local_directory: String) -> bool:
    if file.is_empty():
        return false
    for directory: String in roots(local_directory):
        if FileAccess.file_exists(directory.path_join(file)):
            return true
    return false


## Every Ogre material declaration a mod may refer to: the game's own, with the mod's own laid
## over the top so a pack that redeclares a name gets its own.
##
## The base scripts are read once per call and there are 25 of them holding a couple of hundred
## declarations, which is cheap next to reading a single mesh — and a cache here would be
## process-global state, which this project refuses.
static func materials(local_directory: String) -> Dictionary:
    var out: Dictionary = {}
    var base: String = SourceScan.repo_root().path_join(BASE_ROOT)
    for directory: String in ["materials", "managed_materials"]:
        out.merge(OgreMaterial.read_directory(base.path_join(directory)), true)
    out.merge(OgreMaterial.read_directory(local_directory), true)
    return out
