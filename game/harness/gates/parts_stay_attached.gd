extends GateBase
## Checks that no part of the vehicle comes off when it is set down.
##
## Motion is measured in the vehicle's own frame, so what is left after the rig lands is
## the part moving against the vehicle rather than the vehicle moving against the world.
##
## The fault this exists for: the hero truck's doors are held on entirely by four
## `commands2` rams and four `shocks` dampers, and neither section was parsed. The doors
## therefore had no beam to the body at all, and swung a metre off their hinges the moment
## the truck settled — with every beam that did exist sitting at its rest length, because
## nothing was being stretched. A whole sub-assembly was simply not attached.
##
## The oracle is the rig's own geometry. A part bolted to a vehicle stays where it is
## bolted; what a beam is called in the file does not change that it is one.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const SUBSTEP_HZ: float = 10000.0
const SETTLE_SECONDS: float = 2.0
const DROP_HEIGHT_M: float = 0.3
## Suspension travel is real movement of real parts: the hero truck's axle and leaf
## springs move 142 mm settling onto their own weight, and must not be called a fault. The
## detached door moved 1068 mm, so there is most of an order of magnitude between the two
## and no need to place the bound precisely.
const MAX_TRAVEL_M: float = 0.25
const MIN_PARTS: int = 8


static func meta() -> Dictionary:
    return {
        "name": "parts_stay_attached",
        "proves": "every flexbody stays with the vehicle when it settles under its own weight",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "no part's nodes move over %.2f m in the vehicle's frame" % MAX_TRAVEL_M,
        "why": (
            "a part held on by a section the parser skips has no beam to the body and"
            + " leaves, while every beam that does exist sits at its rest length and every"
            + " energy and stability check stays green. Nothing already here looks at"
            + " whether a part is still where it was bolted."
        ),
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_file(mod_dir.path_join(TRUCK))
    if error != "":
        return fail(error)
    if truck.flexbodies.size() < MIN_PARTS:
        return fail("%d flexbodies, expected at least %d" % [truck.flexbodies.size(), MIN_PARTS])

    var settled: PackedVector3Array = _settle(truck)
    if settled.is_empty():
        return fail("RorSolver is not registered: the GDExtension did not load")
    for position: Vector3 in settled:
        if not (is_finite(position.x) and is_finite(position.y) and is_finite(position.z)):
            return fail("the rig did not survive settling: a node position is not finite")

    # Take the vehicle's own frame out of both poses. Landing moves the whole rig, and
    # that is not a part coming loose.
    var rest_to_actor: Transform3D = ActorFrame.of(
        truck.nodes, truck.camera_nodes
    ).affine_inverse()
    var settled_to_actor: Transform3D = ActorFrame.of(
        settled, truck.camera_nodes
    ).affine_inverse()

    var worst_part: String = ""
    var worst: float = 0.0
    for entry: Dictionary in truck.flexbodies:
        for id: int in entry["forset"] as PackedInt32Array:
            var moved: float = (
                (settled_to_actor * settled[id]) - (rest_to_actor * truck.nodes[id])
            ).length()
            if moved > worst:
                worst = moved
                worst_part = entry["mesh"] as String
    if worst > MAX_TRAVEL_M:
        return fail(
            "%s moved %.3f m in the vehicle's own frame, over the %.2f m bound: it is"
            % [worst_part, worst, MAX_TRAVEL_M]
            + " not attached to the rig it is drawn on",
            worst
        )
    return ok(
        "%d parts stayed attached settling from %.1f m; the furthest, %s, moved %.0f mm"
        % [truck.flexbodies.size(), DROP_HEIGHT_M, worst_part, worst * 1000.0],
        worst
    )


func _settle(truck: TruckParser) -> PackedVector3Array:
    var solver: RefCounted = ClassDB.instantiate("RorSolver") as RefCounted
    if solver == null:
        return PackedVector3Array()
    var mass: float = maxf(truck.minimass_kg, 1.0)
    var lowest: float = INF
    for node: Vector3 in truck.nodes:
        lowest = minf(lowest, node.y)
    for node: Vector3 in truck.nodes:
        solver.add_node(node + Vector3(0.0, DROP_HEIGHT_M - lowest, 0.0), mass)
    for i: int in range(0, truck.beams.size(), 2):
        var beam: int = i / 2
        solver.add_beam(
            truck.beams[i], truck.beams[i + 1], 0.0,
            truck.beam_spring[beam], truck.beam_damp[beam]
        )
    solver.set_gravity(Vector3(0.0, -9.81, 0.0))
    solver.set_ground(0.0, true)
    solver.step(1.0 / SUBSTEP_HZ, int(SETTLE_SECONDS * SUBSTEP_HZ))
    var out: PackedVector3Array = PackedVector3Array()
    for n: int in solver.node_count():
        out.append(solver.get_node_position(n))
    return out
