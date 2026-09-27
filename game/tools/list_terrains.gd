extends SceneTree
## Prints the terrains this checkout holds, as each one describes itself.
##
##   godot --path game --headless --script res://tools/list_terrains.gd


func _initialize() -> void:
    var summaries: Array[Dictionary] = RorTerrainLibrary.summaries()
    if summaries.is_empty():
        print("No terrains. Put one under assets/terrains/<name>/ with its .terrn2, or run")
        print("  tools/import_terrain.sh <zip>")
        quit()
        return
    print("%-20s %-24s %9s  %s" % ["DIRECTORY", "NAME", "SIZE", "SPAWN"])
    for summary: Dictionary in summaries:
        if (summary["error"] as String) != "":
            print("%-20s %s" % [summary["directory"], summary["error"]])
            continue
        print("%-20s %-24s %7.0f m  %s" % [
            summary["directory"],
            summary["name"],
            summary["size_m"],
            str(summary["start"]),
        ])
    print("")
    print("Play one:  tools/play.sh --truck --map <directory>")
    quit()
