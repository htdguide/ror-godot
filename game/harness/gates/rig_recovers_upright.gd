extends GateBase
## A rolled vehicle can be set back on its wheels where it lies.
##
## Asked for in a human session, and the reason is the session itself: a truck on its roof
## ends the test, and having to drive back from the spawn point to where the interesting
## ground was makes people stop testing the interesting ground.
##
## Recovery is not a rotation. A soft-body vehicle that has rolled is bent, and turning the
## wreck the right way up leaves it a wreck — so the rig is rebuilt from its rest shape at the
## position and heading it had, which is what upstream's own reset does. This checks all three
## parts: it ends up upright, it ends up where it was rather than back at the start, and it
## ends up undeformed.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const SUBSTEP_HZ: float = 2000.0
## Where the rig is put before being rolled, so that "it stayed where it was" is a statement
## about somewhere other than the origin.
const AWAY: Vector3 = Vector3(40.0, 0.0, -25.0)
const HEADING_RAD: float = 0.9
## Upright means the vehicle's own up axis points up. A settled rig on a slope is not exactly
## vertical, so this is generous; a rig on its roof reads -1.
const MIN_UPRIGHT: float = 0.9
## How far the recovered rig may be from where it rolled.
const MAX_DRIFT_M: float = 3.0
## Deformation left after recovery, as the worst structural node's distance from where the
## *same rig settles normally*.
##
## Two things had to be taken out of this before it measured deformation at all. It is against
## a settled rig rather than the rest shape, because a vehicle at rest sits 90 to 100 mm down
## on its suspension and measuring against the unsprung shape counts the suspension working as
## damage — that read 152 mm on a perfectly good recovery. And it excludes the tread, because
## tread nodes rotate with the wheel: a tyre is a ring, so a wheel stopped at a different
## angle is the same shape, and comparing individual tread nodes across two rigs measures
## nothing but which way the wheels happen to be pointing. That read 174 mm.
const MAX_DEFORMATION_M: float = 0.05
const SETTLE_SECONDS: float = 3.0
## The height a recovery sets the rig down from. The reference pose is placed from the same
## height by the same call, so the only difference between the two is whether the rig had been
## rolled first — otherwise the comparison measures two different drops.
const RECOVER_CLEARANCE_M: float = 0.4


static func meta() -> Dictionary:
    return {
        "name": "rig_recovers_upright",
        "proves": "a rolled vehicle can be recovered onto its wheels where it lies, undeformed and facing the way it was",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "after recovery the vehicle's up axis is within %.2f of vertical, it is within"
            % MIN_UPRIGHT
            + " %.0f m of where it rolled, and no node is more than %.0f mm from its rest"
            % [MAX_DRIFT_M, MAX_DEFORMATION_M * 1000.0]
            + " shape"
        ),
        "why": (
            "a recovery that teleports the vehicle home, or that rights a bent rig without"
            + " straightening it, is worse than none: the first ends the test and the second"
            + " leaves a vehicle that handles wrongly for reasons nobody can see. Each of the"
            + " three is checked separately so a failure says which."
        ),
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        return fail(rig["error"] as String)
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_ground(0.0, true)

    # What this rig looks like when it has simply been parked: the shape a recovery should
    # produce, suspension sag and all.
    RigBuilder.place(solver, truck, AWAY, HEADING_RAD, RECOVER_CLEARANCE_M)
    for _i: int in int(SETTLE_SECONDS * 60.0):
        solver.step(1.0 / SUBSTEP_HZ, int(SUBSTEP_HZ / 60.0))
    var reference: PackedVector3Array = solver.get_positions().duplicate()
    var reference_frame: Transform3D = ActorFrame.of(reference, truck.camera_nodes)

    # Put it on its roof, away from the origin and at an angle, then let it settle there.
    _roll(solver, truck)
    for _i: int in int(SETTLE_SECONDS * 60.0):
        solver.step(1.0 / SUBSTEP_HZ, int(SUBSTEP_HZ / 60.0))
    var rolled: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
    if rolled.basis.y.y > 0.0:
        return fail(
            "the vehicle did not end up on its roof (its up axis is %.2f): the test did not"
            % rolled.basis.y.y
            + " set up the situation it is checking"
        )

    RigBuilder.place(
        solver,
        truck,
        rolled.origin,
        RigBuilder.heading_of(solver.get_positions(), truck.camera_nodes),
        RECOVER_CLEARANCE_M
    )
    for _i: int in int(SETTLE_SECONDS * 60.0):
        solver.step(1.0 / SUBSTEP_HZ, int(SUBSTEP_HZ / 60.0))
    var positions: PackedVector3Array = solver.get_positions()
    if not is_finite(positions[0].length()):
        return fail("the rig went non-finite after being recovered")
    var recovered: Transform3D = ActorFrame.of(positions, truck.camera_nodes)

    if recovered.basis.y.y < MIN_UPRIGHT:
        return fail(
            "after recovery the vehicle's up axis is %.2f, not upright" % recovered.basis.y.y,
            recovered.basis.y.y
        )
    var drift: float = Vector3(
        recovered.origin.x - rolled.origin.x, 0.0, recovered.origin.z - rolled.origin.z
    ).length()
    if drift > MAX_DRIFT_M:
        return fail(
            "the recovered vehicle is %.1f m from where it rolled: recovery is sending it"
            % drift
            + " somewhere else",
            drift
        )
    var deformation: float = _worst_deformation(
        positions, recovered, reference, reference_frame, truck.generated_from
    )
    if deformation > MAX_DEFORMATION_M:
        return fail(
            "the recovered vehicle is still bent: its worst node is %.0f mm from where the"
            % (deformation * 1000.0)
            + " same rig settles when simply parked (node %d)" % _worst_node,
            deformation
        )
    return ok(
        "rolled to an up axis of %.2f, recovered to %.2f, %.1f m from where it lay, worst"
        % [rolled.basis.y.y, recovered.basis.y.y, drift]
        + " node %.0f mm from where the same rig parks normally" % (deformation * 1000.0),
        deformation
    )


## Puts the rig upside down and drops it, so that it settles on its roof.
func _roll(solver: RefCounted, truck: TruckParser) -> void:
    var over: Basis = Basis(Vector3.FORWARD, PI).rotated(Vector3.UP, HEADING_RAD)
    var lowest: float = INF
    for node: Vector3 in truck.nodes:
        lowest = minf(lowest, (over * node).y)
    for i: int in truck.nodes.size():
        var placed: Vector3 = over * truck.nodes[i]
        solver.set_node_position(
            i, Vector3(AWAY.x + placed.x, 0.1 + placed.y - lowest, AWAY.z + placed.z)
        )
        solver.set_node_velocity(i, Vector3.ZERO)


## The worst node's distance between two poses, each taken in its own vehicle frame — so
## where the vehicle is and which way it faces do not count as deformation.
func _worst_deformation(
    positions: PackedVector3Array,
    frame: Transform3D,
    reference: PackedVector3Array,
    reference_frame: Transform3D,
    structural_nodes: int
) -> float:
    var to_local: Transform3D = frame.affine_inverse()
    var reference_to_local: Transform3D = reference_frame.affine_inverse()
    var worst: float = 0.0
    for i: int in mini(structural_nodes, mini(positions.size(), reference.size())):
        var difference: float = (to_local * positions[i]).distance_to(
            reference_to_local * reference[i]
        )
        if difference > worst:
            worst = difference
            _worst_node = i
    return worst


var _worst_node: int = -1
