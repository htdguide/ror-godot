extends SceneTree
## Reads one OGRE mesh many times in one process, churning the heap in between, and hashes what
## the reader returns each time. A reader that reads memory it never wrote returns different
## geometry depending on what ran before it — which is how an order-dependent gate looks.
##
##   godot --path . --headless --script res://harness/dev/reader_repeat_probe.gd -- <mesh path>

const READS: int = 12


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    var path: String = argv[0] if argv.size() > 0 else "assets/terrains/Starling-Island/a1da0UID-tunapicker.mesh"
    path = SourceScan.repo_root().path_join(path)
    var digests: Dictionary = {}
    for i: int in READS:
        # Churn: allocate and free buffers of varied sizes, filled with a pattern that changes per
        # iteration, so freed memory the reader might pick up differs between reads.
        var junk: Array = []
        for k: int in 200:
            var bytes: PackedByteArray = PackedByteArray()
            bytes.resize(64 + ((k * 7919 + i * 104729) % 65536))
            bytes.fill((i * 37 + k) % 256)
            junk.append(bytes)
        junk.clear()
        var reader: RefCounted = ClassDB.instantiate("OgreMeshReader") as RefCounted
        var read: Dictionary = reader.read_file(path)
        var hash: HashingContext = HashingContext.new()
        hash.start(HashingContext.HASH_MD5)
        var summary: PackedStringArray = PackedStringArray()
        for submesh: Dictionary in read.get("submeshes", []) as Array:
            for key: String in submesh.keys():
                var value: Variant = submesh[key]
                hash.update(var_to_bytes(value))
            summary.append("%s:%d" % [submesh.get("material", "?"), (submesh.get("indices", PackedInt32Array()) as PackedInt32Array).size()])
        var digest: String = hash.finish().hex_encode()
        digests[digest] = (digests.get(digest, 0) as int) + 1
        print("read %2d  %s  %s" % [i, digest.substr(0, 12), " ".join(summary).substr(0, 140)])
    print("%d distinct results over %d reads" % [digests.size(), READS])
    quit(0)
