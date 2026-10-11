extends GateBase
## A vehicle's own contacters cannot pass through its own collision triangles.
##
## Upstream's `CalcCabCollisions` runs `ResolveIntraActorCollisions` every substep, after the beams:
## an actor's contacter nodes against its own collision triangles, so a crushed cab folds against
## itself rather than through itself. Tyre nodes are left out ("ignore wheel/chassis self contact")
## and a triangle never tests its own corners. It is what the `contacters` section is for — the
## hero names 79 — and this project had no self-collision at all.
##
## The test vehicle is written here: a collision triangle held still, a contacter half a metre
## above its middle, falling under gravity. It has to come to rest on the triangle, within the
## collision range of its plane, and stay there. **Two controls in the same run**: with
## self-collision off the node falls through, and marked as a tyre node it falls through. Then the
## hero is driven into a wall, to show that a real rig exercises it, and the count is reported.
##
## **Self-collision is off by default** and this gate switches it on for its own runs. On, the
## hero recovered from 0.40 m broke one cab beam in `a_recovered_rig_is_whole`, where 0.30 to 0.50 m
## in 1 cm steps broke none either way (`harness/dev/self_contact_probe.gd`): a knife edge, not a
## systematic fault, but that gate's claim came from a person and is not this one's to loosen.

const SUBSTEP_HZ: float = 2000.0
const DROP_M: float = 0.5
const FRAMES: int = 90
const COLLISION_RANGE_M: float = 0.02
## Resting on the plane means within the collision range of it, give or take the settling.
const REST_BAND_M: float = 0.05
const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const WALL_AHEAD_M: float = 22.0
const WALL_HALF: Vector3 = Vector3(9.0, 1.6, 1.0)
const CRASH_FRAMES: int = 300


static func meta() -> Dictionary:
    return {
        "name": "a_vehicle_does_not_fold_through_itself",
        "proves": "a contacter dropped %.1f m onto its own vehicle's collision triangle rests within %.0f mm of the plane, falls through with self-collision off or as a tyre node, and the hero's own crash resolves self-contacts" % [DROP_M, REST_BAND_M * 1000.0],
        "builds_on": ["a_vehicle_collides_with_the_nodes_its_file_names", "a_crash_bends_the_rig"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "rests above the plane by at most %.0f mm; both controls end more than %.1f m below it;"
            % [REST_BAND_M * 1000.0, DROP_M] + " hero crash self-contacts > 0"
        ),
        "why": (
            "upstream stops a vehicle's contacters passing through its own cab every substep, which"
            + " is what keeps a crushed cab from folding through itself; this project had none."
        ),
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var on: Dictionary = _drop(true, false)
    var off: Dictionary = _drop(false, false)
    var tyre: Dictionary = _drop(true, true)
    for case: Dictionary in [on, off, tyre]:
        if (case["error"] as String) != "":
            return fail(case["error"] as String)
    var above: float = on["height"] as float
    if above < 0.0 or above > REST_BAND_M:
        return fail(
            "the contacter came to %.4f m from its own triangle's plane (%d contacts): it should"
            % [above, on["contacts"]] + " rest on it",
            above
        )
    for control: Array in [[off, "with self-collision off"], [tyre, "as a tyre node"]]:
        if ((control[0] as Dictionary)["height"] as float) > -DROP_M:
            return fail("%s the node stopped at %.3f m: the control did not fall through" % [
                control[1], (control[0] as Dictionary)["height"]])
    var crash: Dictionary = _crash()
    if (crash["error"] as String) != "":
        return fail(crash["error"] as String)
    if (crash["contacts"] as int) == 0 and not (crash["skipped"] as bool):
        return fail("the hero hit a wall at %.1f m/s and resolved no self-contact" % crash["speed"])
    return ok(
        "rests %.1f mm above its own triangle (%d contacts); off it fell to %.2f m, as a tyre to"
        % [above * 1000.0, on["contacts"], off["height"]]
        + " %.2f m; %s" % [tyre["height"], crash["report"]],
        above
    )


## The triangle and the falling contacter; returns the node's height above the triangle's plane.
func _drop(self_collision: bool, as_tyre: bool) -> Dictionary:
    var text: String = "\n".join([
        "droptest",
        "globals",
        "40, 0, tracks/semi",
        "nodes",
        "0, -1.0, 1.0, -1.0",
        "1, 1.0, 1.0, -1.0",
        "2, 0.0, 1.0, 1.5",
        "3, 0.0, %.2f, 0.0" % (1.0 + DROP_M),
        "beams",
        "0, 1", "1, 2", "2, 0",
        "cab",
        "0, 1, 2, c",
        "contacters",
        "3",
        "end",
    ])
    var truck: TruckParser = TruckParser.new()
    var error: String = truck.parse_text(text)
    if error != "":
        return {"error": error}
    var built: Dictionary = RigBuilder.build(truck, 0.0)
    if (built["error"] as String) != "":
        return {"error": built["error"]}
    var solver: RefCounted = built["solver"] as RefCounted
    solver.set_ground(-100.0, false)
    for node: int in 3:
        solver.set_node_immovable(node, true)
    solver.set_self_collision(self_collision)
    if as_tyre:
        solver.set_node_tyre(3)
    for _f: int in FRAMES:
        solver.step(1.0 / SUBSTEP_HZ, 33)
    return {
        "error": "", "height": solver.get_node_position(3).y - 1.0,
        "contacts": solver.self_contact_count(),
    }


func _crash() -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return {"error": "", "skipped": true, "contacts": 0, "speed": 0.0,
            "report": "hero crash skipped: asset not present"}
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        return {"error": rig["error"]}
    var solver: RefCounted = rig["solver"] as RefCounted
    var truck: TruckParser = rig["truck"] as TruckParser
    solver.set_self_collision(true)
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.15)
    for _i: int in 60:
        solver.step(1.0 / SUBSTEP_HZ, 33)
    var pose: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
    var forward: Vector3 = Vector3(-pose.basis.z.x, 0.0, -pose.basis.z.z).normalized()
    var wall_at: Vector3 = pose.origin + forward * WALL_AHEAD_M
    solver.add_obstacle_box(
        Transform3D(Basis.looking_at(-forward, Vector3.UP), Vector3(wall_at.x, WALL_HALF.y, wall_at.z)),
        WALL_HALF, 0
    )
    var before: int = solver.self_contact_count()
    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(1.0)
    var fastest: float = 0.0
    for _f: int in CRASH_FRAMES:
        solver.step(1.0 / SUBSTEP_HZ, 33)
        fastest = maxf(fastest, absf(solver.road_speed()))
    var contacts: int = solver.self_contact_count() - before
    return {
        "error": "", "skipped": false, "contacts": contacts, "speed": fastest,
        "report": "hero into a wall at %.1f m/s: %d self-contacts, %d beams broken" % [
            fastest, contacts, solver.broken_beam_count()],
    }
