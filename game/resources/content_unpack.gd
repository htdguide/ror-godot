class_name ContentUnpack
extends RefCounted
## A zip dropped in a content folder is content: it is unpacked beside itself, once, into a
## folder of its own name, and the library lists that folder.
##
## The Rigs of Rods repository hands out zips, and "unpack it first" is a step a person should
## not have to know. The zip stays where it was put — it is theirs — and is not unpacked again
## while its folder exists, so a pack a person edited in place keeps the edits. A zip whose every
## entry sits under one top folder is unpacked without that folder, so the library finds the
## actor or `.terrn2` where it looks: one level down from the content root.
##
## Nothing here trusts the archive: an entry whose path climbs out of the folder is refused and
## the zip is left alone, named in the return so the browser can say so.

const ZIP: String = "zip"


## Unpacks every zip directly under `root` that has no folder of its name yet. Returns the names
## unpacked and, under "refused", the zips that would not stay inside their folder.
static func unpack_all(root: String) -> Dictionary:
    var done: PackedStringArray = PackedStringArray()
    var refused: PackedStringArray = PackedStringArray()
    if not DirAccess.dir_exists_absolute(root):
        return {"unpacked": done, "refused": refused}
    for file: String in DirAccess.get_files_at(root):
        if file.get_extension().to_lower() != ZIP:
            continue
        var folder: String = root.path_join(file.get_basename())
        if DirAccess.dir_exists_absolute(folder):
            continue
        match unpack(root.path_join(file), folder):
            OK:
                done.append(file.get_basename())
            _:
                refused.append(file)
    return {"unpacked": done, "refused": refused}


## Unpacks one zip into `folder`. ERR_INVALID_DATA for an entry that climbs out; the folder is
## then removed so that a half-unpacked pack is not listed as one.
static func unpack(zip_path: String, folder: String) -> Error:
    var reader: ZIPReader = ZIPReader.new()
    var opened: Error = reader.open(zip_path)
    if opened != OK:
        return opened
    var entries: PackedStringArray = reader.get_files()
    var strip: String = _common_top_folder(entries)
    for entry: String in entries:
        var relative: String = entry.trim_prefix(strip)
        if relative.is_empty():
            continue
        if not _stays_inside(relative):
            reader.close()
            _remove_tree(folder)
            return ERR_INVALID_DATA
        var target: String = folder.path_join(relative)
        if entry.ends_with("/"):
            DirAccess.make_dir_recursive_absolute(target)
            continue
        DirAccess.make_dir_recursive_absolute(target.get_base_dir())
        var out: FileAccess = FileAccess.open(target, FileAccess.WRITE)
        if out == null:
            reader.close()
            _remove_tree(folder)
            return FileAccess.get_open_error()
        out.store_buffer(reader.read_file(entry))
        out.close()
    reader.close()
    return OK


## The one folder every entry sits under, with its slash, or "" when there is none.
static func _common_top_folder(entries: PackedStringArray) -> String:
    var top: String = ""
    for entry: String in entries:
        var slash: int = entry.find("/")
        if slash < 0:
            return ""
        var first: String = entry.substr(0, slash + 1)
        if top == "":
            top = first
        elif first != top:
            return ""
    return top


## No absolute paths, no `..` segments, nothing that resolves above the folder.
static func _stays_inside(relative: String) -> bool:
    if relative.begins_with("/") or relative.contains(":") or relative.begins_with("\\\\"):
        return false
    for part: String in relative.replace("\\\\", "/").split("/"):
        if part == "..":
            return false
    return true


static func _remove_tree(folder: String) -> void:
    if not DirAccess.dir_exists_absolute(folder):
        return
    for file: String in DirAccess.get_files_at(folder):
        DirAccess.remove_absolute(folder.path_join(file))
    for sub: String in DirAccess.get_directories_at(folder):
        _remove_tree(folder.path_join(sub))
    DirAccess.remove_absolute(folder)
