class_name RorVehicleLibrary
extends RefCounted
## What vehicles this checkout holds, and what each one says about itself.
##
## The counterpart to `RorTerrainLibrary`, and deliberately the same shape: nothing is registered,
## indexed or converted, so a vehicle downloaded five minutes ago is drivable without a build
## step. The library is the filesystem.
##
## **A vehicle is not always a `.truck`.** Rigs of Rods gives an actor's definition file an
## extension by what it is — a car, a load, a boat, an aeroplane, a trailer, a fixed prop — and
## they are all the same format inside. Measured on four packs downloaded from the repository:
## `mazda626gf` ships no `.truck` at all, only `mazda626sd18i-mt.car`, so a library that looked
## for trucks would have reported that folder as empty. Starling Island ships five actors across
## `.truck` and `.boat`, and NhelensGrass ships a monorail, a bridge and a crane as `.fixed`.
##
## **The unit is the file, not the folder**, for the same reason the terrain library keys on the
## `.terrn2`: one folder is routinely several vehicles. Starling Island's five are one download,
## and a library keyed on the directory would have shown whichever the filesystem answered with
## first.
##
## **Both content roots are searched for both kinds.** A pack is not tidy about what it contains:
## Starling Island and NhelensGrass each ship terrains *and* vehicles in one folder, and that
## folder is unpacked under `assets/terrains/`. Looking for vehicles only under `assets/mods/`
## would have missed six of the nine actors this checkout now holds.

## An actor's definition file is one of these. Upstream's own list, and all one format inside.
const ACTOR_EXTENSIONS: PackedStringArray = [
    "truck", "car", "load", "airplane", "boat", "trailer", "train", "fixed",
]
## Where content is unpacked, and where upstream's own shipped vehicles sit, is the build
## profile's to say: see `BuildProfile`. The production build bundles nothing.


## Every vehicle this checkout holds: {"name", "file", "directory", "kind"}, in a stable order.
##
## `name` is the definition file's basename, which is what a session names on the command line.
## `kind` is its extension, which is the only thing in the format that says what it is meant to
## be — a `.boat` and a `.truck` are told apart by nothing else.
static func entries() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var seen: Dictionary = {}
    for base: String in roots():
        if not DirAccess.dir_exists_absolute(base):
            continue
        # A zip dropped in the folder is a pack: unpacked beside itself, once.
        ContentUnpack.unpack_all(base)
        for directory: String in DirAccess.get_directories_at(base):
            var full: String = base.path_join(directory)
            for file: String in _actor_files_in(full):
                var name: String = file.get_basename()
                # A downloaded vehicle wins a name clash with a shipped one: somebody put it
                # there on purpose. The terrain library makes the same choice.
                if seen.has(name):
                    continue
                seen[name] = true
                out.append({
                    "name": name,
                    "file": file,
                    "directory": full,
                    "kind": file.get_extension().to_lower(),
                })
    out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return (a["name"] as String) < (b["name"] as String)
    )
    return out


## The absolute directories vehicles are looked for in, the shipped content last.
static func roots() -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    for relative: String in BuildProfile.mod_roots():
        out.append(SourceScan.repo_root().path_join(relative))
    var shipped: String = BuildProfile.shipped_root()
    if shipped != "":
        out.append(SourceScan.repo_root().path_join(shipped))
    return out


## Every vehicle's name, in a stable order.
static func names() -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    for entry: Dictionary in entries():
        out.append(entry["name"] as String)
    return out


## What each vehicle says about itself: the entry plus {"title", "author", "error"}.
##
## A vehicle that cannot be read is listed with its error rather than left out, because "it is not
## in the list" and "it is broken" are different problems and only one of them is the library's.
## That is `RorTerrainLibrary`'s rule and it earned itself the day it was written: NhelensGrass's
## terrain reports an unreadable traction map instead of silently vanishing.
static func summaries() -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for entry: Dictionary in entries():
        var summary: Dictionary = entry.duplicate()
        summary.merge(_describe(entry["directory"].path_join(entry["file"] as String) as String))
        out.append(summary)
    return out


## The entry for one name, or an empty dictionary.
static func find(name: String) -> Dictionary:
    for entry: Dictionary in entries():
        if (entry["name"] as String) == name:
            return entry
    return {}


## The title and author out of a definition file's own first lines.
##
## Only the head of the file is read. A vehicle's title is its first content line — before any
## section keyword, which is what `TruckParser` does too — and the author line is near the top by
## convention. Parsing the whole file to fill in a menu would mean reading every node and beam of
## every vehicle on the disk to draw a list.
static func _describe(path: String) -> Dictionary:
    var handle: FileAccess = FileAccess.open(path, FileAccess.READ)
    if handle == null:
        return {"title": path.get_file().get_basename(), "author": "", "error":
            "cannot open %s" % path.get_file()}
    var title: String = ""
    var author: String = ""
    var read: int = 0
    while not handle.eof_reached() and read < HEAD_LINES:
        var line: String = TruckLexer.strip(handle.get_line())
        read += 1
        if line.is_empty():
            continue
        if title.is_empty():
            title = line
            continue
        if line.to_lower().begins_with("author"):
            # `author <kind> <id> <name> <email>`: the name is what a person wants to see.
            var words: PackedStringArray = line.split(" ", false)
            if words.size() >= 4:
                author = words[3]
            continue
        if _is_section(line):
            break
    handle.close()
    if title.is_empty():
        return {"title": path.get_file().get_basename(), "author": "", "error":
            "%s states no name" % path.get_file()}
    return {"title": title, "author": author, "error": ""}


## How far into a file to look for a title and an author before giving up.
const HEAD_LINES: int = 60
## The sections a vehicle file starts with once its header is over. Not a complete list and does
## not need to be: it only has to stop the search before the file turns into numbers.
const HEAD_SECTIONS: PackedStringArray = [
    "nodes", "beams", "globals", "engine", "fileinfo", "description", "wheels", "cinecam",
]


static func _is_section(line: String) -> bool:
    return HEAD_SECTIONS.has(line.to_lower().strip_edges())


## The actor definition files directly inside one directory.
static func _actor_files_in(directory: String) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    for file: String in DirAccess.get_files_at(directory):
        if ACTOR_EXTENSIONS.has(file.get_extension().to_lower()):
            out.append(file)
    out.sort()
    return out
