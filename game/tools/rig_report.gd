extends SceneTree
## Reports what a vehicle file actually says about its own drivetrain, mass and wheels.
##
## Run it before believing anything about how a rig should drive:
##   godot --path game --headless --script tools/rig_report.gd -- <path to .truck>


func _initialize() -> void:
    var argv: PackedStringArray = OS.get_cmdline_user_args()
    if argv.is_empty():
        printerr("usage: rig_report.gd -- <path to .truck>")
        quit(2)
        return
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_file(argv[0])
    if error != "":
        printerr(error)
        quit(1)
        return

    var drive: Dictionary = truck.drivetrain
    print("'%s': %d nodes (%d generated), %d beams, %d wheels, %d hydros" % [
        truck.name, truck.nodes.size(), truck.nodes.size() - truck.generated_from,
        truck.beams.size() / 2, truck.wheels.size(), truck.hydros.size()])
    print("globals: dry %.1f kg, cargo %.1f kg, minimass %.2f kg, axles %s" % [
        drive["dry_mass_kg"], drive["cargo_mass_kg"], truck.minimass_kg,
        "yes" if truck.has_axles else "no"])
    if bool(drive["has_engine"]):
        print("engine: %.0f-%.0f rpm, %.0f Nm, diff %.2f, %d gears %s, curve '%s'" % [
            drive["min_rpm"], drive["max_rpm"], drive["torque_nm"], drive["diff_ratio"],
            (drive["gears"] as PackedFloat32Array).size(), drive["gears"],
            drive["torque_model"]])
        print("engoption: inertia %.2f, type %s, clutch %.0f, shift %.2f s, clutch %.2f s" % [
            drive["inertia"], drive["type"], drive["clutch_force"], drive["shift_time"],
            drive["clutch_time"]])
        print("brakes: %.0f foot, %.0f parking" % [
            drive["brake_force"], drive["parking_brake_force"]])
    else:
        print("engine: none declared")
    for wheel: Dictionary in truck.wheels:
        print("wheel %s: r %.3f m, %d rays, axle %d/%d, tread %d..%d, drive %d, brake %d,"
            % [wheel["side"], wheel["tire_radius"], wheel["rays"], wheel["node1"],
               wheel["node2"], wheel["first_tread"],
               (wheel["first_tread"] as int) + (wheel["tread_count"] as int) - 1,
               wheel["propulsed"], wheel["braked"]]
            + " arm %d, mass %.1f kg, friction %.2f"
            % [wheel["arm_node"], wheel["mass"], wheel["friction"]])
    for hydro: Dictionary in truck.hydros:
        var beam: int = hydro["beam"] as int
        print("hydro: beam %d (%d-%d), factor %+.3f" % [
            beam, truck.beams[beam * 2], truck.beams[beam * 2 + 1], hydro["factor"]])

    var masses: PackedFloat32Array = NodeMasses.distribute(truck)
    var total: float = 0.0
    var heaviest: int = 0
    var lightest: int = 0
    for i: int in masses.size():
        total += masses[i]
        if masses[i] > masses[heaviest]:
            heaviest = i
        if masses[i] < masses[lightest]:
            lightest = i
    print("mass: %.1f kg total over %d nodes; heaviest node %d at %.1f kg, lightest %d at %.2f kg"
        % [total, masses.size(), heaviest, masses[heaviest], lightest, masses[lightest]])
    print("unparsed sections: %s" % _unparsed(truck))
    quit(0)


func _unparsed(truck: TruckParser) -> String:
    var out: PackedStringArray = PackedStringArray()
    for key: String in truck.sections_seen.keys():
        var seen: int = int(truck.sections_seen[key])
        var parsed: int = int(truck.sections_parsed.get(key, 0))
        if parsed < seen:
            out.append("%s (%d of %d)" % [key, parsed, seen])
    return ", ".join(out) if out.size() > 0 else "none"
