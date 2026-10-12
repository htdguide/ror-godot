extends GateBase
## What a file states for traction control and ABS reaches the solver's wheel step, the toggle keys
## respect NOTOGGLE, and the direction the aids measure the vehicle's speed along is upstream's
## `getDirection`: from the main camera's `dir` node to its `pos` node.
##
## `the_wheel_pass_is_upstreams` holds the aids' arithmetic; this holds the path to it, which is
## where the library lost its brakes (`a_line_keyword_is_not_a_row_of_the_section_above`).
##
## The Accord states both aids ON & NOTOGGLE; the Gavril Zeta X states both ON and toggleable; the
## hero states neither. Each car is spawned and its forward compared with its camera nodes'.

const LIBRARY: String = "assets/mods"


static func meta() -> Dictionary:
    return {
        "name": "a_cars_driving_aids_reach_its_wheels",
        "proves": "a file's AntiLockBrakes and TractionControl reach the wheel step as stated, NOTOGGLE holds against the keys, and the aids' direction is the camera nodes'",
        "builds_on": ["the_wheel_pass_is_upstreams"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "Accord: both on, keys change nothing; Zeta X: both on, keys turn them off; hero: neither; direction within 1e-6 of the camera nodes'",
        "why": "traction control and ABS were read nowhere, and a car's file decides whether a driver may switch them off.",
        "budget_s": 30.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var root: String = SourceScan.repo_root().path_join(LIBRARY)
    var cases: Array[Array] = [
        ["accord23", "accord.truck", true, false],
        ["gavrilzeta", "gavrilzetax.truck", true, true],
        ["ChevyS1023", "S10offroad.truck", false, false],
    ]
    var report: PackedStringArray = PackedStringArray()
    for case: Array in cases:
        var mod_dir: String = root.path_join(case[0])
        if not DirAccess.dir_exists_absolute(mod_dir):
            return ok("skipped: %s not present" % case[0], 0)
        var rig: Dictionary = RigBuilder.from_file(mod_dir, case[1], 0.0)
        if (rig["error"] as String) != "":
            return fail("%s: %s" % [case[1], rig["error"]])
        var solver: RefCounted = rig["solver"] as RefCounted
        var truck: TruckParser = rig["truck"] as TruckParser
        for kind: String in ["abs", "tc"]:
            if solver.drive_aid_on(kind) != bool(case[2]):
                return fail("%s: %s is %s, the file says %s" % [case[1], kind, solver.drive_aid_on(kind), case[2]])
            if bool(case[2]):
                var after: bool = solver.toggle_drive_aid(kind)
                if after != (not bool(case[3])):
                    return fail("%s: the %s key left it %s; the file %s toggling" % [case[1], kind, after,
                            "allows" if case[3] else "forbids"])
        var positions: PackedVector3Array = solver.get_positions()
        var want: Vector3 = (positions[truck.camera_nodes["centre"] as int] - positions[truck.camera_nodes["dir"] as int]).normalized()
        var got: Vector3 = solver.direction()
        if got.distance_to(want) > 1e-6:
            return fail("%s: the aids' direction is %s, the camera nodes say %s" % [case[1], got, want])
        report.append("%s aids %s%s" % [case[1], "on" if case[2] else "none", (", toggle " + ("yes" if case[3] else "no")) if case[2] else ""])
    return ok("; ".join(report) + "; directions the camera nodes'", 0)
