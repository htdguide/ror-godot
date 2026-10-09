extends GateBase
## A zip dropped in a content folder is unpacked beside itself, once, and a hostile one is not.
##
## The repository hands out zips, and "unpack it first" is a step a person should not have to
## know. Two zips are written here with Godot's own packer — one flat, one with everything under
## a single top folder, as packs come both ways — and dropped in a folder of this gate's own;
## after one library-style pass each has a folder of its name with the actor file where the
## library looks, the zips are still there, and a second pass unpacks nothing. A third zip with
## an entry that climbs out of its folder is refused and leaves no folder behind.

const ROOT: String = "user://unpack_gate"


static func meta() -> Dictionary:
    return {
        "name": "a_zip_dropped_in_the_folder_is_content",
        "proves": "a zip in a content folder is unpacked once into a folder of its name with a single top folder stripped, the zip is kept, a second pass does nothing, and a zip that climbs out of its folder is refused whole",
        "builds_on": ["an_empty_library_says_where_to_get_content"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "2 of 2 zips unpacked with the actor at the top of its folder, 0 on the second pass, 1 hostile zip refused with no folder left",
        "why": (
            "a pack handed out as a zip and ignored as one is a user's first failure, and a zip"
            + " that writes outside its folder is somebody else's first success."
        ),
        "budget_s": 10.0,
        "needs_gpu": false,
        "milestone": "M2",
    }


func run(_harness: Node) -> Dictionary:
    var root: String = ProjectSettings.globalize_path(ROOT)
    ContentUnpack._remove_tree(root)
    DirAccess.make_dir_recursive_absolute(root)
    _write_zip(root.path_join("flat.zip"), {"flat.truck": "truck", "flat.dds": "tex"})
    _write_zip(root.path_join("nested.zip"), {"Nested Pack/nested.truck": "truck", "Nested Pack/skins/a.dds": "tex"})
    _write_zip(root.path_join("hostile.zip"), {"ok.truck": "truck", "../escaped.txt": "no"})
    var first: Dictionary = ContentUnpack.unpack_all(root)
    var second: Dictionary = ContentUnpack.unpack_all(root)
    var problems: PackedStringArray = PackedStringArray()
    var unpacked: PackedStringArray = first["unpacked"] as PackedStringArray
    if unpacked.size() != 2 or not unpacked.has("flat") or not unpacked.has("nested"):
        problems.append("first pass unpacked %s" % ",".join(unpacked))
    if not FileAccess.file_exists(root.path_join("flat/flat.truck")):
        problems.append("flat.zip did not land as flat/flat.truck")
    if not FileAccess.file_exists(root.path_join("nested/nested.truck")) or not FileAccess.file_exists(root.path_join("nested/skins/a.dds")):
        problems.append("nested.zip did not have its top folder stripped")
    if not FileAccess.file_exists(root.path_join("flat.zip")):
        problems.append("the zip was removed")
    if not (first["refused"] as PackedStringArray).has("hostile.zip"):
        problems.append("hostile.zip was not refused: %s" % ",".join(first["refused"]))
    if DirAccess.dir_exists_absolute(root.path_join("hostile")):
        problems.append("hostile.zip left a folder behind")
    if FileAccess.file_exists(root.path_join("escaped.txt")) or FileAccess.file_exists(root.get_base_dir().path_join("escaped.txt")):
        problems.append("hostile.zip wrote outside its folder")
    if (second["unpacked"] as PackedStringArray).size() != 0:
        problems.append("second pass unpacked %s again" % ",".join(second["unpacked"]))
    ContentUnpack._remove_tree(root)
    if not problems.is_empty():
        return fail("; ".join(problems), problems.size())
    return ok("flat and nested zips unpacked once with the actor at the top of its folder, zips kept, second pass idle, hostile zip refused whole", 2)


static func _write_zip(path: String, files: Dictionary) -> void:
    var packer: ZIPPacker = ZIPPacker.new()
    packer.open(path)
    for name: String in files:
        packer.start_file(name)
        packer.write_file((files[name] as String).to_utf8_buffer())
        packer.close_file()
    packer.close()
