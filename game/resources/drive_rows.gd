class_name DriveRows
extends RefCounted
## Parses the sections that describe a drivetrain: `globals`, `engine`, `engoption`,
## `brakes`, `torquecurve` and `fusedrag`.
##
## Read together they are a complete specification of how a rig accelerates and stops. The
## hero truck states a 450 Nm V8 with a 4.12 differential, six forward gears from 6.25 to
## 0.75, a 0.12 kg m2 flywheel, a 1050 N clutch and 5500 N of brakes — so the way it drives
## is data, and nothing here needs a figure chosen by hand.
##
## Field orders follow upstream's parser, which is not always the order a file's comment
## claims: `engoption` is "inertia, type, clutch force, shift time, clutch time, post-shift
## time, stall rpm, idle rpm, ...", with the two times in the opposite order to how the
## engine's own setter takes them.

const SECTIONS: Array[String] = [
    "globals", "engine", "engoption", "brakes", "torquecurve", "fusedrag",
]
## Upstream's SimConstants defaults for anything a file leaves out. A negative clutch force
## means "pick by engine type", which the drivetrain does.
const UNSET: float = -1.0


static func handles(section: String) -> bool:
    return SECTIONS.has(section)


## The drivetrain as parsed so far. One dictionary per rig, filled in by `read`.
static func empty() -> Dictionary:
    return {
        "has_engine": false,
        "dry_mass_kg": 0.0,
        "cargo_mass_kg": 0.0,
        "min_rpm": 0.0,
        "max_rpm": 0.0,
        "torque_nm": 0.0,
        "diff_ratio": 1.0,
        "reverse_gear": 1.0,
        "neutral_gear": 1.0,
        "gears": PackedFloat32Array(),
        "inertia": 10.0,
        "type": "t",
        "clutch_force": UNSET,
        "clutch_time": UNSET,
        "shift_time": UNSET,
        "post_shift_time": UNSET,
        "idle_rpm": UNSET,
        "stall_rpm": UNSET,
        "braking_torque": UNSET,
        "brake_force": 0.0,
        "parking_brake_force": 0.0,
        # The named torque model, or "" when the rig states samples or nothing.
        "torque_model": "",
        "torque_rpm": PackedFloat32Array(),
        "torque_ratio": PackedFloat32Array(),
        # The fuselage a rig declares for its aerodynamics. A rig that declares one is dragged
        # as a body by upstream rather than node by node, and the difference decides its top
        # speed: the hero truck states a 0.1 m fuselage and tops out at 63 km/h without it.
        "fuse_front": "",
        "fuse_width": 0.0,
        "fuse_area_coefficient": 0.0,
        "fuse_autocalc": false,
    }


## Reads one row into `drive`. Returns an error string, empty when the row was understood.
static func read(section: String, fields: PackedStringArray, drive: Dictionary) -> String:
    match section:
        "globals":
            return _globals(fields, drive)
        "engine":
            return _engine(fields, drive)
        "engoption":
            return _engoption(fields, drive)
        "brakes":
            return _brakes(fields, drive)
        "torquecurve":
            return _torque_curve(fields, drive)
        "fusedrag":
            return _fusedrag(fields, drive)
    return "unknown drivetrain section '%s'" % section


## "dry_mass, cargo_mass [, material]". The dry mass is what the rig's own structure
## weighs and is spread over the nodes that state no weight of their own.
static func _globals(fields: PackedStringArray, drive: Dictionary) -> String:
    if fields.size() < 2:
        return "globals row has %d fields, expected at least 2" % fields.size()
    drive["dry_mass_kg"] = fields[0].to_float()
    drive["cargo_mass_kg"] = fields[1].to_float()
    return ""


## "min_rpm, max_rpm, torque, diff_ratio, reverse, neutral, gear1..gearN [, -1]".
## A negative ratio terminates the gear list rather than being a gear.
static func _engine(fields: PackedStringArray, drive: Dictionary) -> String:
    if fields.size() < 7:
        return "engine row has %d fields, expected at least 7" % fields.size()
    drive["min_rpm"] = fields[0].to_float()
    drive["max_rpm"] = fields[1].to_float()
    drive["torque_nm"] = fields[2].to_float()
    drive["diff_ratio"] = fields[3].to_float()
    drive["reverse_gear"] = fields[4].to_float()
    drive["neutral_gear"] = fields[5].to_float()
    var gears: PackedFloat32Array = PackedFloat32Array()
    for i: int in range(6, fields.size()):
        var ratio: float = fields[i].to_float()
        if ratio < 0.0:
            break
        gears.append(ratio)
    if gears.is_empty():
        return "engine row states no forward gear"
    drive["gears"] = gears
    drive["has_engine"] = true
    return ""


static func _engoption(fields: PackedStringArray, drive: Dictionary) -> String:
    if fields.size() < 1:
        return "engoption row is empty"
    drive["inertia"] = fields[0].to_float()
    if fields.size() > 1:
        drive["type"] = fields[1].to_lower()
    if fields.size() > 2:
        drive["clutch_force"] = fields[2].to_float()
    if fields.size() > 3:
        drive["shift_time"] = fields[3].to_float()
    if fields.size() > 4:
        drive["clutch_time"] = fields[4].to_float()
    if fields.size() > 5:
        drive["post_shift_time"] = fields[5].to_float()
    if fields.size() > 6:
        drive["stall_rpm"] = fields[6].to_float()
    if fields.size() > 7:
        drive["idle_rpm"] = fields[7].to_float()
    if fields.size() > 10:
        drive["braking_torque"] = fields[10].to_float()
    return ""


## "braking_force [, parking_brake_force]". Upstream's parking brake defaults to twice the
## footbrake when a rig states none.
static func _brakes(fields: PackedStringArray, drive: Dictionary) -> String:
    if fields.size() < 1:
        return "brakes row is empty"
    drive["brake_force"] = fields[0].to_float()
    if fields.size() > 1:
        drive["parking_brake_force"] = fields[1].to_float()
    return ""


## Either a single model name, or an "rpm, fraction" sample.
static func _torque_curve(fields: PackedStringArray, drive: Dictionary) -> String:
    if fields.size() == 1:
        if not TorqueCurves.has(fields[0]):
            return "torquecurve names unknown model '%s'" % fields[0]
        drive["torque_model"] = fields[0].to_lower()
        return ""
    if fields.size() < 2:
        return "torquecurve row is empty"
    (drive["torque_rpm"] as PackedFloat32Array).append(fields[0].to_float())
    (drive["torque_ratio"] as PackedFloat32Array).append(fields[1].to_float())
    return ""


## The curve to hand the engine: the rig's own samples if it stated any, else the model it
## named, else upstream's flat default.
static func curve_of(drive: Dictionary) -> Dictionary:
    if not (drive["torque_rpm"] as PackedFloat32Array).is_empty():
        return {"rpm": drive["torque_rpm"], "ratio": drive["torque_ratio"]}
    var model: String = drive["torque_model"] as String
    return TorqueCurves.samples(model if model != "" else "default")


## "front_node, rear_node, approximate_width, airfoil" — or, in its other form,
## "autocalc, front_node, rear_node, area_coefficient, airfoil", where the width is worked out
## from the rig's own size when it is built.
##
## The rear node is read and not kept, because upstream does not keep it either: its spawner
## sets the fuselage's back node to its front node, with a comment saying that is probably a bug
## and has been since v0.38. With the two the same the airfoil's own axis is zero length and the
## airfoil term drops out of the drag entirely, so a faithful port keeps the bug.
##
## A file may state several rows; upstream applies each over the last, so the last one wins.
static func _fusedrag(fields: PackedStringArray, drive: Dictionary) -> String:
    if fields.size() < 3:
        return "fusedrag row has %d fields, expected at least 3" % fields.size()
    if fields[0].to_lower() == "autocalc":
        if fields.size() < 4:
            return "fusedrag autocalc row has %d fields, expected at least 4" % fields.size()
        drive["fuse_autocalc"] = true
        drive["fuse_front"] = fields[1]
        drive["fuse_area_coefficient"] = fields[3].to_float()
        drive["fuse_width"] = 0.0
        return ""
    drive["fuse_autocalc"] = false
    drive["fuse_front"] = fields[0]
    drive["fuse_width"] = fields[2].to_float()
    return ""
