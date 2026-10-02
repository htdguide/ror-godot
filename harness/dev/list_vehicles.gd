extends SceneTree
func _initialize() -> void:
    var all: Array[Dictionary] = RorVehicleLibrary.summaries()
    print("%-34s %-28s %-9s %s" % ["NAME", "TITLE", "KIND", "PACK"])
    for v: Dictionary in all:
        print("%-34s %-28s %-9s %s%s" % [
            v["name"], (v["title"] as String).substr(0, 28), v["kind"],
            (v["directory"] as String).get_file(),
            "" if (v["error"] as String) == "" else "  ERROR: " + (v["error"] as String),
        ])
    print("%d vehicles" % all.size())
    quit()
