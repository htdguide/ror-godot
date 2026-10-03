extends GateBase
## Every mesh an object definition names is a file that is actually there.
##
## All three lists are checked: the mesh the object draws, the distance meshes its `beginlodmesh`
## block names, and the collision hulls its `beginmesh` blocks name — because a misread header
## shifts every line after it too.
##
## **The content is the oracle.** An `.odef` is a terrain author's statement about which meshes an
## object is made of, and a reader that gets the format right lands on files that exist. One that
## gets it wrong lands on names nothing on the disk answers to — which is exactly what happened,
## and it was invisible: a mesh that cannot be opened is skipped with a warning and the object
## draws whatever else it had.
##
## **The fault this catches.** The format's header is a name, then a mesh, then a scale, and a
## bare `LOD` line may come before all three. Upstream reads that line and throws it away —
## `source/main/resources/odef_fileformat/ODefFileFormat.cpp`:
##
##     if (strcmp(m_cur_line, "LOD") == 0) // Clone of old parser logic.
##     {
##         return true; // 'LOD line' = obsolete
##     }
##
## This project took the first line it saw as the mesh name, so for those files the mesh was
## `LOD`, and the real mesh on the next line was consumed by the scale slot and dropped. Seven
## objects on Starling Island are written that way — its firehouse, police department, store,
## warehouse, office block, bus stop and a road sign — and every one of them drew only its
## collision box: a bare untextured shape standing where a building should be.
##
## Counting named meshes against the disk catches that without knowing anything about `LOD`, which
## is the point: the next format detail this reader gets wrong will present the same way.

## A mesh name the format uses for "this block adds nothing"; `Odef` already drops it.
const MIN_MESHES: int = 50


## **It builds on nothing.** `builds_on` means "running this exercises that, at least as
## hard", and the graph stops running what it implies — so an edge that only records which
## gate came first is an edge that silently retires a gate. This one reads every `.odef` in the checkout and places nothing.


static func meta() -> Dictionary:
    return {
        "name": "an_object_definition_names_a_real_mesh",
        "proves": "every mesh named by every .odef in this checkout resolves to a file that exists",
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "every named mesh resolves; one that does not is a misread header",
        "why": (
            "a mesh that cannot be opened is skipped with a warning and the object draws whatever"
            + " else it had. Reading the header one line early made the mesh name `LOD` and"
            + " dropped the real mesh, and seven Starling Island buildings drew only their"
            + " collision box — a bare shape where a building should be, with nothing logged"
            + " that said so."
        ),
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "C2",
    }


func run(_harness: Node) -> Dictionary:
    var named: int = 0
    var files: int = 0
    var problems: PackedStringArray = PackedStringArray()
    for directory: String in _definition_directories():
        for file: String in DirAccess.get_files_at(directory):
            if file.get_extension().to_lower() != "odef":
                continue
            files += 1
            var read: Dictionary = Odef.read(directory.path_join(file))
            if (read["error"] as String) != "":
                problems.append("%s: %s" % [file, read["error"]])
                continue
            var both: PackedStringArray = read["meshes"] as PackedStringArray
            both.append_array(read["collision_meshes"] as PackedStringArray)
            for level: Dictionary in read["lods"] as Array[Dictionary]:
                both.append(level["mesh"] as String)
            for mesh: String in both:
                named += 1
                if not RorContentPath.has(mesh, directory):
                    problems.append("%s names %s, which is nowhere a mod may name it from"
                        % [file, mesh])

    if named < MIN_MESHES:
        return ok("skipped: %d meshes named across %d definitions" % [named, files], named)
    if problems.size() > 0:
        return fail(
            "%d of %d meshes named across %d definitions are not there: %s"
            % [problems.size(), named, files, "; ".join(problems)],
            problems.size()
        )
    return ok(
        "%d meshes named across %d object definitions, every one of them on the disk"
        % [named, files],
        named
    )


## Every directory an `.odef` may live in: the base resources and every pack on the disk.
func _definition_directories() -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    var base: String = SourceScan.repo_root().path_join(RorContentPath.BASE_ROOT)
    for directory: String in RorContentPath.BASE_DIRECTORIES:
        out.append(base.path_join(directory))
    for root: String in RorVehicleLibrary.CONTENT_ROOTS:
        var path: String = SourceScan.repo_root().path_join(root)
        for pack: String in DirAccess.get_directories_at(path):
            out.append(path.path_join(pack))
    return out
