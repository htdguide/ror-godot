extends GateBase
## Every submesh an OGRE `.mesh` declares comes back from the reader, with every index it says
## it has.
##
## **The oracle is the file's own chunk headers, walked here.** A `.mesh` is a tree of chunks —
## a `uint16` id and a `uint32` length that includes the six header bytes — and `M_SUBMESH`
## (0x4000) carries its material name, a `useSharedVertices` flag and an index count before any
## of its geometry. Twenty lines of byte handling read that without asking the reader anything,
## which is the only way the answer is not the reader's own opinion.
##
## **Strings end with a newline, not a null.** Two earlier attempts at this check looked for a
## null terminator, ran off the end of the material name, found no submesh chunk in any file,
## compared nothing and reported no problems — twice, and both times the result was quoted as
## evidence that the reader was complete. A walker that finds nothing must say so, so a file
## whose header cannot be parsed is counted and reported rather than skipped in silence.
##
## **More than the walk finds is not a fault.** A chunk length in this library is a hint: every
## fir on Russia declares a first submesh of 4091 bytes that really ends at 3835, so a walk by
## declared length steps straight over the foliage and reads one bare trunk. The reader
## resynchronises on a submesh's own shape when a length lands on something that is not a chunk,
## and recovers geometry this walk cannot reach — 8 submeshes in Russia's hall where the lengths
## lead to 1, 28 in `a1da0UID-nedlloyd.mesh`. So what is required is that nothing the file's own
## headers *lead to* is lost. The surplus is counted and reported, because a resynchroniser that
## started inventing submeshes would show up here first as a number that climbed.
##
## **What it caught.** `a1da0UID-kwhale.mesh` declares one submesh of 1482 indices and the
## reader returned none: the submesh was read correctly and then thrown away because the chunk
## *after* it had a nonsense length. The file's own mesh chunk claims 110,924 bytes in a
## 106,944-byte file. A whale on North St Helens drew nothing at all.

## Below this there is nothing to judge: a fresh clone with no downloaded packs.
const MIN_MESHES: int = 20
## How many to name when something is wrong.
const LISTED: int = 8
## Chunk ids, from OGRE's `MeshFileFormat.h`.
const M_HEADER: int = 0x1000
const M_MESH: int = 0x3000
const M_SUBMESH: int = 0x4000
const CHUNK_HEADER: int = 6


static func meta() -> Dictionary:
    return {
        "name": "a_mesh_keeps_every_triangle_its_file_declares",
        "proves": (
            "every submesh an OGRE mesh file declares is returned by the reader, with the"
            + " number of indices the file states for it"
        ),
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "no file returns fewer submeshes than its own chunk lengths lead to, and every one"
            + " of those carries the index count the file states"
        ),
        "why": (
            "a submesh read correctly and then dropped is geometry that is simply absent from"
            + " the world, and absent geometry looks exactly like content the author never"
            + " shipped. One whale was being discarded because the bytes after it did not parse."
        ),
        "budget_s": 240.0,
        "needs_gpu": false,
        "milestone": "C2",
    }


func run(_harness: Node) -> Dictionary:
    var reader: RefCounted = ClassDB.instantiate("OgreMeshReader") as RefCounted
    if reader == null:
        return fail("OgreMeshReader is not registered: build the GDExtension first")
    var checked: int = 0
    var submeshes: int = 0
    var recovered: int = 0
    var unreadable: PackedStringArray = PackedStringArray()
    var problems: PackedStringArray = PackedStringArray()
    for path: String in _mesh_files():
        var declared: Array = _declared(path)
        if declared.is_empty():
            # Either the header is not one this walker understands or the file holds no
            # submesh at all. Reported, because a walker that silently finds nothing is a
            # walker that passes everything — which is exactly how this check failed twice.
            unreadable.append(path.get_file())
            continue
        var read: Dictionary = reader.read_file(path)
        if (read.get("error", "") as String) != "":
            problems.append("%s: %s" % [path.get_file(), read["error"]])
            continue
        checked += 1
        var got: Array = read["submeshes"] as Array
        submeshes += got.size()
        if got.size() < declared.size():
            problems.append("%s declares %d submeshes and the reader returned %d"
                % [path.get_file(), declared.size(), got.size()])
            continue
        recovered += got.size() - declared.size()
        # Every submesh the declared lengths lead to must come back with all of its indices.
        # The reader may hand back more; those are the ones a length stepped over.
        for at: int in declared.size():
            var want: int = (declared[at] as Dictionary)["indices"] as int
            var have: int = ((got[at] as Dictionary)["indices"] as PackedInt32Array).size()
            if want != have:
                problems.append("%s submesh %d declares %d indices and the reader gave %d"
                    % [path.get_file(), at, want, have])
                break

    if checked < MIN_MESHES:
        return ok("skipped: %d readable mesh files in this checkout" % checked, checked)
    if problems.size() > 0:
        return fail(
            "%d of %d mesh files lose geometry their own headers declare: %s"
            % [problems.size(), checked, "; ".join(problems.slice(0, LISTED))],
            problems.size()
        )
    return ok(
        "%d mesh files, %d submeshes, every index the files declare; %d more recovered past a"
        % [checked, submeshes, recovered] + " chunk length that lies%s"
        % [
           "" if unreadable.is_empty() else
           "; %d with no header this walker reads (%s)"
           % [unreadable.size(), ", ".join(unreadable.slice(0, LISTED))]],
        checked
    )


## What a file's own chunk headers say its submeshes are, as `[{"material", "indices"}]`.
func _declared(path: String) -> Array:
    var out: Array = []
    var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
    if bytes.size() < 8 or bytes.decode_u16(0) != M_HEADER:
        return out
    # OGRE terminates the header's version string with a newline.
    var at: int = _after_line(bytes, 2)
    if at < 0 or at + CHUNK_HEADER > bytes.size() or bytes.decode_u16(at) != M_MESH:
        return out
    # The mesh chunk's own header, then its `skeletallyAnimated` flag.
    at += CHUNK_HEADER + 1
    while at + CHUNK_HEADER <= bytes.size():
        var id: int = bytes.decode_u16(at)
        var length: int = bytes.decode_u32(at + 2)
        if length < CHUNK_HEADER or at + length > bytes.size():
            break
        if id == M_SUBMESH:
            var name_end: int = _after_line(bytes, at + CHUNK_HEADER)
            # The material name, then `useSharedVertices`, then the index count.
            if name_end > 0 and name_end + 5 <= bytes.size():
                out.append({
                    "material": bytes.slice(at + CHUNK_HEADER, name_end - 1)
                        .get_string_from_ascii(),
                    "indices": bytes.decode_u32(name_end + 1),
                })
        at += length
    return out


## One past the next newline at or after `from`, or -1 when there is none.
func _after_line(bytes: PackedByteArray, from: int) -> int:
    for at: int in range(from, bytes.size()):
        if bytes[at] == 10:
            return at + 1
    return -1


## Every `.mesh` in the checkout: terrain packs, vehicle mods and the base resources alike.
func _mesh_files() -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    var roots: PackedStringArray = PackedStringArray(["assets", "resources"])
    for root: String in roots:
        _collect(SourceScan.repo_root().path_join(root), out)
    return out


func _collect(directory: String, into: PackedStringArray) -> void:
    for file: String in DirAccess.get_files_at(directory):
        if file.get_extension().to_lower() == "mesh":
            into.append(directory.path_join(file))
    for child: String in DirAccess.get_directories_at(directory):
        _collect(directory.path_join(child), into)
