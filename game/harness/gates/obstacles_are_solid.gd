extends GateBase
## The static boxes the park is built from are solid: a rig rests on one and cannot drive through
## one.
##
## A heightfield can only describe ground that is a function of x and z, so everything a test park
## is actually made of — a ramp with a face, a wall, a kerb, a rock — is a box instead, contacted
## with the same law upstream uses for the ground. That law was written for a surface underfoot,
## and the two ways it can be wrong here are opposite: a box that does not stop a node lets the rig
## sink through a ramp, and a box that stops it too hard throws the rig off a kerb.
##
## Both are measured against arithmetic rather than a golden: a rig resting on a plinth is at the
## plinth's own height, and a rig driven into a wall ends up on the near side of it.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const SUBSTEP_HZ: float = 2000.0
const SETTLE_SECONDS: float = 2.5
const DRIVE_SECONDS: float = 6.0

## The plinth: wide enough to hold the whole rig, high enough that resting on it and resting on the
## ground are different answers by more than a tyre's deflection.
const PLINTH_TOP_M: float = 1.2
const PLINTH_HALF: Vector3 = Vector3(6.0, 0.6, 6.0)
## How close to the plinth's top face the rig's lowest contact node has to settle. A tyre squashes,
## so this is the tyre's deflection and not zero.
const REST_TOLERANCE_M: float = 0.12
## The wall, and how far past its near face any node may end up: a node beyond this is inside or
## through the wall.
const WALL_THICKNESS_M: float = 1.0
const WALL_HEIGHT_M: float = 2.5
const THROUGH_TOLERANCE_M: float = 0.25
## Where the wall stands, ahead of a rig driving down its own forward axis.
const WALL_AT_M: float = 14.0


static func meta() -> Dictionary:
    return {
        "name": "obstacles_are_solid",
        "proves": "a rig rests on a static box at the box's own height and is stopped by one it drives into, rather than passing through either",
        # standing a rig up and driving it are what rig_drives_forward proves; this adds the boxes.
        "builds_on": ["rig_drives_forward"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "the rig rests within %.2f m of the plinth's top face and no node ends up more than"
            % REST_TOLERANCE_M
            + " %.2f m past the wall's near face" % THROUGH_TOLERANCE_M
        ),
        "why": (
            "everything a test park is made of that a heightfield cannot describe is a box:"
            + " ramps with faces, walls, kerbs, rocks. A box that does not stop a node lets the"
            + " rig sink through a ramp, and one that stops it too hard throws the rig off a"
            + " kerb. Neither shows on flat ground, which is where the ground law was written."
        ),
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)

    var resting: Dictionary = _rest_on_plinth(mod_dir)
    if (resting["error"] as String) != "":
        return fail(resting["error"] as String)
    var rest_error: float = absf((resting["lowest"] as float) - PLINTH_TOP_M)
    if rest_error > REST_TOLERANCE_M:
        return fail(
            "the rig settled with its lowest node at %.3f m on a plinth whose top is %.3f m,"
            % [resting["lowest"] as float, PLINTH_TOP_M]
            + " %.3f m out: it is %s the box"
            % [rest_error,
               "inside" if (resting["lowest"] as float) < PLINTH_TOP_M else "hovering over"],
            rest_error
        )

    var stopped: Dictionary = _drive_into_wall(mod_dir)
    if (stopped["error"] as String) != "":
        return fail(stopped["error"] as String)
    if (stopped["past"] as float) > THROUGH_TOLERANCE_M:
        return fail(
            "a node ended up %.2f m past the wall's near face after driving into it: the wall is"
            % [stopped["past"] as float]
            + " not solid",
            stopped["past"]
        )
    if (stopped["travel"] as float) < 1.0:
        return fail(
            "the rig moved %.2f m before the wall: it never reached it, so nothing was tested"
            % (stopped["travel"] as float),
            stopped["travel"]
        )
    return ok(
        "rested at %.3f m on a plinth topped at %.2f m (%.0f mm out), and stopped %.2f m short"
        % [resting["lowest"] as float, PLINTH_TOP_M, rest_error * 1000.0,
           -(stopped["past"] as float)]
        + " of a wall after %.1f m of approach" % (stopped["travel"] as float),
        rest_error
    )


## Stands the rig over a plinth and lets it settle onto it.
func _rest_on_plinth(mod_dir: String) -> Dictionary:
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        return {"error": rig["error"] as String, "lowest": 0.0}
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    # The world's ground stays at zero and the plinth stands on it: resting on the box and
    # falling to the ground are then 1.2 m apart, which is a difference this can read. Putting
    # the ground far below instead does not work — `RigBuilder.place` stands the rig relative to
    # the ground it is told about, so it spawns under the box and falls through from inside it.
    solver.set_ground(0.0, true)
    solver.add_obstacle_box(
        Transform3D(Basis(), Vector3(0.0, PLINTH_TOP_M - PLINTH_HALF.y, 0.0)), PLINTH_HALF, 0
    )
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, PLINTH_TOP_M + 0.4)

    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    for frame: int in int(SETTLE_SECONDS * 60.0):
        solver.step(dt, chunk)
        if not is_finite(solver.get_node_position(0).length()):
            return {
                "error": "the rig went non-finite %.2f s into settling on the box" % (
                    float(frame) / 60.0),
                "lowest": 0.0,
            }
    var lowest: float = INF
    for position: Vector3 in solver.get_positions():
        lowest = minf(lowest, position.y)
    return {"error": "", "lowest": lowest}


## Drives the rig at a wall and reports how far past its near face anything got.
##
## The wall is placed along the rig's own forward axis after it has settled, rather than at a
## fixed point of the world: which way `RigBuilder.place` points a rig is its own business, and a
## wall put where the rig was assumed to be going is a wall it drives past.
func _drive_into_wall(mod_dir: String) -> Dictionary:
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        return {"error": rig["error"] as String, "past": 0.0, "travel": 0.0}
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3.ZERO, 0.0, 0.15)

    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    for _i: int in int(1.0 * 60.0):
        solver.step(dt, chunk)

    var pose: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
    var forward: Vector3 = -pose.basis.z
    forward = Vector3(forward.x, 0.0, forward.z).normalized()
    var start: Vector3 = pose.origin
    var centre: Vector3 = start + forward * WALL_AT_M + Vector3(0.0, WALL_HEIGHT_M * 0.5, 0.0)
    # Turned to face the rig, so its near face is square across the path.
    var basis: Basis = Basis.looking_at(-forward, Vector3.UP)
    solver.add_obstacle_box(
        Transform3D(basis, centre),
        Vector3(8.0, WALL_HEIGHT_M * 0.5, WALL_THICKNESS_M),
        0
    )
    var near_face: float = WALL_AT_M - WALL_THICKNESS_M

    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(0.45)
    var past: float = 0.0
    for frame: int in int(DRIVE_SECONDS * 60.0):
        solver.step(dt, chunk)
        if not is_finite(solver.get_node_position(0).length()):
            return {
                "error": "the rig went non-finite %.2f s into the wall" % (float(frame) / 60.0),
                "past": 0.0, "travel": 0.0,
            }
        for position: Vector3 in solver.get_positions():
            past = maxf(past, (position - start).dot(forward) - near_face)
    var travel: float = (
        ActorFrame.of(solver.get_positions(), truck.camera_nodes).origin - start
    ).dot(forward)
    return {"error": "", "past": past, "travel": travel}
