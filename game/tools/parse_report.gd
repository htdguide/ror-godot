extends SceneTree
func _initialize() -> void:
    var a: PackedStringArray = OS.get_cmdline_user_args()
    var truck: TruckParser = TruckParser.new()
    truck.parse_file(a[0].path_join(a[1]))
    print("errors: %d" % truck.errors.size())
    for i: int in mini(truck.errors.size(), 12):
        print("  %s" % truck.errors[i])
    var unread: PackedStringArray = PackedStringArray()
    for key: String in truck.sections_seen.keys():
        unread.append("%s(%d)" % [key, int(truck.sections_seen[key])])
    print("sections: %s" % ", ".join(unread))
    quit(0)
