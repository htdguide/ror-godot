extends SceneTree
## Parses every vehicle this checkout holds and reports what the reader could not read.
##
## The library is the corpus: whatever is unpacked under `assets/mods/` and `assets/terrains/`
## plus upstream's own shipped content. One engine for all of them, because the point is the
## distribution of faults across a pack rather than any one file.
##
##   godot --path . --headless --script res://harness/dev/corpus_report.gd
##   godot --path . --headless --script res://harness/dev/corpus_report.gd -- <name substring>
##
## Prints one line per actor and then the faults gathered by their first six words, which is
## what makes a pack's single systemic problem visible among its hundred symptoms.


func _initialize() -> void:
    var filter: String = ""
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    if not argv.is_empty():
        filter = argv[0]
    var kinds: Dictionary = {}
    var worst: Array[Dictionary] = []
    var total_errors: int = 0
    var clean: int = 0
    var counted: int = 0
    for entry: Dictionary in RorVehicleLibrary.entries():
        var name: String = entry["name"] as String
        if filter != "" and not name.containsn(filter):
            continue
        var path: String = (entry["directory"] as String).path_join(entry["file"] as String)
        var truck: TruckParser = TruckParser.new()
        var failed: String = truck.parse_file(path)
        counted += 1
        if failed != "":
            print("%-28s REFUSED  %s" % [name, failed])
            total_errors += 1
            continue
        total_errors += truck.errors.size()
        if truck.errors.is_empty():
            clean += 1
        else:
            worst.append({"name": name, "count": truck.errors.size()})
        for message: String in truck.errors:
            var key: String = _kind(message)
            kinds[key] = int(kinds.get(key, 0)) + 1
        print("%-28s %4d nodes %5d beams %2d wheels  %3d errors  coverage %3.0f%%  %s" % [
            name, truck.nodes.size(), truck.beams.size() / 2, truck.wheels.size(),
            truck.errors.size(), truck.coverage() * 100.0, _drawn(entry, truck)])
    print("")
    print("%d actors, %d clean, %d errors in total" % [counted, clean, total_errors])
    var keys: Array = kinds.keys()
    keys.sort_custom(func(a: String, b: String) -> bool:
        return int(kinds[a]) > int(kinds[b])
    )
    for key: String in keys:
        print("  %5d  %s" % [int(kinds[key]), key])
    worst.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return int(a["count"]) > int(b["count"])
    )
    for index: int in mini(worst.size(), 8):
        print("  worst: %-26s %d" % [worst[index]["name"], int(worst[index]["count"])])
    quit(0)


## A fault's family: its words up to the colon that separates the complaint from the line that
## caused it, with any numbers taken out so two rows with different node ids group together.
func _kind(message: String) -> String:
    var head: String = message.split(":")[0]
    var out: PackedStringArray = PackedStringArray()
    for word: String in head.split(" ", false):
        out.append("<n>" if word.is_valid_int() or word.is_valid_float() else word)
    return " ".join(out)


## What a vehicle actually draws, against what its file asks for.
##
## The parse report says the rows were read; this says they reached geometry. A row that names a
## mesh file the pack does not ship, or a mesh this project's reader cannot open, is read cleanly
## and draws nothing.
static func _drawn(entry: Dictionary, truck: TruckParser) -> String:
    var directory: String = entry["directory"] as String
    var built: Dictionary = VehicleBuilder.build(directory, entry["file"] as String)
    if (built.get("error", "") as String) != "":
        return "REFUSED %s" % built["error"]
    var root: Node3D = built["root"] as Node3D
    var drawn: int = 0
    for node: Node in _all(root):
        if node is MeshInstance3D:
            drawn += 1
    root.queue_free()
    return "%3d drawn of %d props + %d flexbodies + %d submeshes" % [
        drawn, truck.props.size(), truck.flexbodies.size(), truck.submeshes.drawable()]


static func _all(node: Node) -> Array[Node]:
    var out: Array[Node] = [node]
    for child: Node in node.get_children():
        out.append_array(_all(child))
    return out
