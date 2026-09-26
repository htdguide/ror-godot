extends GateBase
## The vehicle settles onto its suspension, rather than standing on a welded axle.
##
## A Rigs of Rods suspension springs on its shocks and is *located* by ordinary beams, which
## form a linkage the axle can rise and fall through without any of them changing length. Two
## things have to be read from the file for that to work, and missing either produces a rig
## that looks completely normal parked and is rigid the moment it moves:
##
## The `beams` section's options. `r` makes a beam a rope, which carries tension and cannot
## push. On the hero truck the rear axle hangs on two `ir` limiter straps; read as plain beams
## they became 5 MN/m struts resisting in both directions, 225 kN each, and the axle travelled
## 6 mm. And the shocks' own travel bounds, without which there is nothing soft in the path at
## all.
##
## This is measured as ride height: how far the frame drops onto each wheel between being
## placed and coming to rest. It is the number a person means when they say the suspension
## does not work, and no gate here could see it — the rig settled, stayed attached, drove and
## steered, all with a solid axle.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const SUBSTEP_HZ: float = 2000.0
const SETTLE_SECONDS: float = 3.0
## A vehicle settling onto its springs under its own weight. Below this the suspension is not
## carrying the vehicle; above it, it is not holding it up.
const MIN_TRAVEL_M: float = 0.02
const MAX_TRAVEL_M: float = 0.20
## Left and right of an axle carry the same load on flat ground, so they must settle together.
## A difference means one side is bound up.
const MAX_ASYMMETRY_M: float = 0.02


static func meta() -> Dictionary:
    return {
        "name": "suspension_travels",
        "proves": "the frame settles onto its suspension under its own weight, by a realistic amount, evenly across each axle",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "every wheel settles %.0f to %.0f mm; left and right of an axle within %.0f mm"
            % [MIN_TRAVEL_M * 1000.0, MAX_TRAVEL_M * 1000.0, MAX_ASYMMETRY_M * 1000.0]
        ),
        "why": (
            "a rig with a welded axle settles, stays attached, drives and steers, so every"
            + " other gate here passes on it. The first human session reported it in one"
            + " sentence. Ride height under the vehicle's own weight is what that sentence"
            + " means as a number, and it separates a suspension that exists from one whose"
            + " linkage has been read as rigid."
        ),
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.02)
    if (rig["error"] as String) != "":
        return fail(rig["error"] as String)
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    if truck.wheels.size() < 4:
        return fail("%s has %d wheels, expected 4" % [TRUCK, truck.wheels.size()])
    solver.set_ground(0.0, true)

    var before: PackedFloat32Array = _ride_heights(solver, truck)
    for _i: int in int(SETTLE_SECONDS * 60.0):
        solver.step(1.0 / SUBSTEP_HZ, int(SUBSTEP_HZ / 60.0))
    if not is_finite(solver.get_node_position(0).length()):
        return fail("the rig went non-finite while settling")
    var after: PackedFloat32Array = _ride_heights(solver, truck)

    var travel: PackedFloat32Array = PackedFloat32Array()
    var report: PackedStringArray = PackedStringArray()
    for i: int in before.size():
        travel.append(before[i] - after[i])
        report.append("%s %.0f mm" % [truck.wheels[i]["side"], travel[i] * 1000.0])
    for i: int in travel.size():
        if travel[i] < MIN_TRAVEL_M:
            return fail(
                "wheel %d settled only %.0f mm: the axle is not moving on its suspension (%s)"
                % [i, travel[i] * 1000.0, ", ".join(report)],
                travel[i]
            )
        if travel[i] > MAX_TRAVEL_M:
            return fail(
                "wheel %d settled %.0f mm: the suspension is not holding the vehicle up (%s)"
                % [i, travel[i] * 1000.0, ", ".join(report)],
                travel[i]
            )
    # Wheels come in file order, front pair then rear pair.
    for axle: int in 2:
        var difference: float = absf(travel[axle * 2] - travel[axle * 2 + 1])
        if difference > MAX_ASYMMETRY_M:
            return fail(
                "the %s axle settled %.0f mm on one side and %.0f mm on the other: one side"
                % [
                    "front" if axle == 0 else "rear",
                    travel[axle * 2] * 1000.0, travel[axle * 2 + 1] * 1000.0,
                ]
                + " is bound up",
                difference
            )
    return ok("the frame settled onto its springs: %s" % ", ".join(report), travel[0])


## Height of the frame above each axle, which is what the suspension carries.
func _ride_heights(solver: RefCounted, truck: TruckParser) -> PackedFloat32Array:
    var out: PackedFloat32Array = PackedFloat32Array()
    var frame: Vector3 = ActorFrame.of(solver.get_positions(), truck.camera_nodes).origin
    for wheel: Dictionary in truck.wheels:
        var axle: Vector3 = (
            solver.get_node_position(wheel["node1"] as int)
            + solver.get_node_position(wheel["node2"] as int)
        ) * 0.5
        out.append(frame.y - axle.y)
    return out
