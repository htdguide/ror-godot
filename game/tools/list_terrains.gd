extends SceneTree
## Prints the terrains this checkout holds, as each one describes itself.
##
##   godot --path game --headless --script res://tools/list_terrains.gd


func _initialize() -> void:
    var summaries: Array[Dictionary] = RorTerrainLibrary.summaries()
    if summaries.is_empty():
        print("No terrains. Rigs of Rods' own shipped map should be here — check that the")
        print("vendor/rigs-of-rods submodule and its content submodule are checked out:")
        print("  git submodule update --init --recursive")
        print("A downloaded terrain goes in with  tools/import_terrain.sh <zip>")
        quit()
        return
    print("%-16s %-28s %9s  %s" % ["NAME", "TITLE", "SIZE", "SPAWN"])
    for summary: Dictionary in summaries:
        if (summary["error"] as String) != "":
            print("%-16s %s" % [summary["name"], summary["error"]])
            continue
        print("%-16s %-28s %7.0f m  %s" % [
            summary["name"],
            summary["title"],
            summary["size_m"],
            str(summary["start"]),
        ])
    print("")
    print("Play one:  tools/play.sh --truck --map <name>")
    quit()
