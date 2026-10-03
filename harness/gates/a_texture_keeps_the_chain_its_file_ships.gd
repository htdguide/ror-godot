extends GateBase
## A DDS that ships a mip chain is read with its mip chain.
##
## **The oracle is the file's own header.** `dwMipMapCount` sits at byte 28 of a DDS and says how
## many levels the author stored. This gate reads that number itself, with four bytes and no
## help from the reader under test, and requires an image built from the file to carry them.
##
## **Why it matters, and why it looked like something else.** A block-compressed image cannot have
## its mipmaps regenerated — Godot's `generate_mipmaps` fails on one, with "Cannot generate mipmaps
## from compressed image formats" — so a reader that hands back the top level alone leaves every
## DXT texture in the project with exactly one level, and no filter makes a single 256×256 level
## look right on a wall 500 m away. Starling Island's distant brickwork aliased into speckle and
## its roofs dissolved into the sky. That reads as a transparency fault: the first guesses were
## alpha scissor, a bad alpha channel, a material wrongly marked transparent. It is a sampling
## fault, and the levels that would have fixed it were in the files all along — 217 of that
## terrain's 248 DDS files carry a full chain, and the reader was throwing 22 KB of every 87 KB
## file away.
##
## **Only block-compressed files are held to it.** An uncompressed image can have its mipmaps
## generated, so what its header claims does not matter — and several claim a chain they do not
## contain: the hero truck's `S1024.dds` says eleven levels in a file exactly one level long.
##
## A file whose chain stops early is **not** a failure here. Godot's `create_from_data` expects a
## chain all the way down and lays it out its own way, so a short chain would be read as garbage;
## those are reported and fall back to the top level, which is what every file had before.

## Below this there is nothing to judge: a fresh clone with no downloaded packs.
const MIN_FILES: int = 20
## How many files to name when something is wrong.
const LISTED: int = 8


## **It builds on nothing.** `builds_on` means "running this exercises that, at least as
## hard", and the graph stops running what it implies — so an edge that only records which
## gate came first is an edge that silently retires a gate. This one reads DDS headers and draws no ground.


static func meta() -> Dictionary:
    return {
        "name": "a_texture_keeps_the_chain_its_file_ships",
        "proves": "every block-compressed DDS whose own header declares a full mip chain is built into an image that has one",
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "every block-compressed file whose dwMipMapCount is over 1, and whose chain is complete, builds an image with mipmaps",
        "why": (
            "a compressed image cannot have its mipmaps regenerated, so the top level alone is"
            + " all a texture ever gets. Distant brickwork aliases into speckle and roofs"
            + " dissolve into the sky, which reads as a transparency fault and is a sampling one."
        ),
        "budget_s": 180.0,
        "needs_gpu": false,
        "milestone": "C2",
    }


func run(_harness: Node) -> Dictionary:
    var reader: RefCounted = ClassDB.instantiate("DdsReader") as RefCounted
    if reader == null:
        return fail("DdsReader is not registered: build the GDExtension first")
    var files: int = 0
    var declared: int = 0
    var chained: int = 0
    var short_chains: int = 0
    var unreadable: int = 0
    var problems: PackedStringArray = PackedStringArray()
    for directory: String in _texture_directories():
        for file: String in DirAccess.get_files_at(directory):
            if file.get_extension().to_lower() != "dds":
                continue
            var path: String = directory.path_join(file)
            var levels: int = _declared_levels(path)
            if levels < 0:
                continue
            files += 1
            var image: Image = DdsImage.read(path, reader)
            if image == null:
                # Upstream ships volume textures for shaders this project does not run, and they
                # have always read as nothing. Reported rather than failed: not reading a format
                # nothing asks for is a gap, not a regression.
                unreadable += 1
                continue
            if levels <= 1 or not image.is_compressed():
                continue
            declared += 1
            if image.has_mipmaps():
                chained += 1
                continue
            # A chain Godot's layout cannot take is reported rather than failed: the file stops
            # short of 1x1 and there is nothing to be done with the levels it does have.
            if levels < _full_chain_levels(image.get_width(), image.get_height()):
                short_chains += 1
                continue
            problems.append("%s declares %d levels and built none" % [file, levels])

    if files < MIN_FILES:
        return ok("skipped: %d DDS files in this checkout" % files, files)
    if problems.size() > 0:
        return fail(
            "%d of %d DDS files lost the mip chain their own header declares: %s"
            % [problems.size(), declared, "; ".join(problems.slice(0, LISTED))],
            problems.size()
        )
    return ok(
        "%d DDS files, %d compressed ones declare a mip chain and %d build one%s%s"
        % [files, declared, chained,
           "" if short_chains == 0 else
           "; %d stop short of 1x1 and keep their top level" % short_chains,
           "" if unreadable == 0 else
           "; %d in formats this reader has no case for" % unreadable],
        chained
    )


## How many levels a file says it has, read straight out of its header. -1 when it is not a DDS.
##
## Four bytes, read here rather than asked of the reader: a gate that asks the thing under test
## how many levels it found can only ever agree with it.
func _declared_levels(path: String) -> int:
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        return -1
    var head: PackedByteArray = file.get_buffer(32)
    file.close()
    if head.size() < 32 or head.slice(0, 4).get_string_from_ascii() != "DDS ":
        return -1
    return head.decode_u32(28)


## How many levels a complete chain has for an image of this size: one per halving, down to 1x1.
func _full_chain_levels(width: int, height: int) -> int:
    var levels: int = 1
    var size: int = maxi(width, height)
    while size > 1:
        size >>= 1
        levels += 1
    return levels


## Every directory a texture may live in: the base resources and every pack on the disk.
func _texture_directories() -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    var base: String = SourceScan.repo_root().path_join(RorContentPath.BASE_ROOT)
    for directory: String in RorContentPath.BASE_DIRECTORIES:
        out.append(base.path_join(directory))
    for root: String in RorVehicleLibrary.CONTENT_ROOTS:
        var path: String = SourceScan.repo_root().path_join(root)
        for pack: String in DirAccess.get_directories_at(path):
            out.append(path.path_join(pack))
    return out
