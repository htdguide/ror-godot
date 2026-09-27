extends GateBase
## The poles beside a loaded terrain's road stop a truck.
##
## A terrain ships meshes, not collision: La Paz's `.odef`s declare no collision boxes at all, so
## its roadside poles were scenery a vehicle drove through. What a session asked for is to be
## able to crash into one, and that is two claims — the boxes exist where the poles are, and a rig
## driven at one stops.
##
## The boxes are worked out from each mesh by columns rather than from its bounding box: a pole
## object here is a 40 m span of wire with two poles in it, and its own box is a wall across the
## desert. So the check on the shapes is that they are pole-shaped — a handful of them, none of
## them wide — and the check on the driving is a rig that hits one and stops.

const TERRAIN_DIR: String = "assets/terrains/lapaz2"
const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const SUBSTEP_HZ: float = 2000.0
## What a pole is: taller than this and narrower than that.
const MIN_POLE_HEIGHT_M: float = 1.0
const MAX_POLE_WIDTH_M: float = 3.0
## How many solid boxes a terrain of a hundred objects should come to, at either end: too few and
## nothing is solid, too many and a bounding box has been used somewhere.
const MIN_BOXES: int = 20
const MAX_BOXES: int = 4000
## The crash: driven at the pole from this far back, having to get within reach of it and lose
## most of its speed there.
const RUN_UP_M: float = 30.0
const THROTTLE: float = 1.0
const DRIVE_SECONDS: float = 8.0
## The rig is a 4 m truck and the pole is 0.7 m across, so "reached it" is the two touching.
const MAX_REACH_M: float = 3.5
## And what it may still be doing after: a fifth of the speed it arrived at.
const MAX_SPEED_KEPT: float = 0.2


static func meta() -> Dictionary:
    return {
        "name": "a_terrains_own_scenery_is_solid",
        "proves": "the objects a loaded terrain ships are solid in the solver, shaped like what they are, and stop a vehicle driven at one",
        "builds_on": ["ror_terrain_objects_are_placed", "obstacles_are_solid"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "between %d and %d boxes, each over %.1f m tall and under %.1f m wide, and a rig"
            % [MIN_BOXES, MAX_BOXES, MIN_POLE_HEIGHT_M, MAX_POLE_WIDTH_M]
            + " driven at one reaching it and losing %.0f%% of its speed there"
            % ((1.0 - MAX_SPEED_KEPT) * 100.0)
        ),
        "why": (
            "a terrain's props are meshes and nothing else; without collision a session drives"
            + " through the poles beside the road. Taking each mesh's bounding box instead would"
            + " make La Paz's power lines into walls 40 m across, so the shapes are worked out by"
            + " column and the result is checked by driving into one."
        ),
        "budget_s": 180.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var directory: String = SourceScan.repo_root().path_join(TERRAIN_DIR)
    if not DirAccess.dir_exists_absolute(directory):
        return ok("skipped: no terrain at %s" % TERRAIN_DIR, 0)
    var loaded: Dictionary = RorTerrain.load_from(directory)
    if (loaded["error"] as String) != "":
        return fail(loaded["error"] as String)
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain

    var boxes: Array[Dictionary] = RorObjectCollision.boxes(terrain)
    if boxes.size() < MIN_BOXES or boxes.size() > MAX_BOXES:
        return fail(
            "the terrain's %d objects came to %d solid boxes, outside %d to %d"
            % [RorObjects.placements(terrain).size(), boxes.size(), MIN_BOXES, MAX_BOXES],
            boxes.size()
        )
    var widest: float = 0.0
    var shortest: float = INF
    for box: Dictionary in boxes:
        var half: Vector3 = box["half"] as Vector3
        widest = maxf(widest, maxf(half.x, half.y) * 2.0)
        shortest = minf(shortest, half.z * 2.0)
    if widest > MAX_POLE_WIDTH_M:
        return fail(
            "a solid box is %.1f m across, over %.1f: a mesh's bounding box has been taken for"
            % [widest, MAX_POLE_WIDTH_M] + " its shape",
            widest
        )
    if shortest < MIN_POLE_HEIGHT_M:
        return fail(
            "a solid box is %.2f m tall, under %.1f: scenery is being made solid"
            % [shortest, MIN_POLE_HEIGHT_M],
            shortest
        )

    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok(
            "%d solid boxes, the widest %.1f m and the shortest %.1f m tall; skipped the crash:"
            % [boxes.size(), widest, shortest] + " the hero asset is not present",
            boxes.size()
        )
    var crash: Dictionary = _drive_at_a_pole(mod_dir, terrain, boxes)
    if (crash["error"] as String) != "":
        return fail(crash["error"] as String, crash["value"] as float)
    return ok(
        "%d solid boxes, the widest %.1f m and the shortest %.1f m tall; hit one at %.0f km/h"
        % [boxes.size(), widest, shortest, crash["speed"] as float]
        + " and stopped %.2f m short of its far side" % (crash["value"] as float),
        crash["value"]
    )


## Drives the hero truck at the nearest pole to the terrain's own spawn.
func _drive_at_a_pole(
    mod_dir: String, terrain: RorTerrain, boxes: Array[Dictionary]
) -> Dictionary:
    var out: Dictionary = {"error": "", "value": 0.0, "speed": 0.0}
    var start: Vector3 = terrain.start_position()
    # The pole to aim at: the one nearest the spawn, which is the one a session would meet.
    var target: Vector3 = Vector3.ZERO
    var nearest: float = INF
    for box: Dictionary in boxes:
        var at: Vector3 = (box["transform"] as Transform3D).origin
        var away: float = Vector2(at.x - start.x, at.z - start.z).length()
        if away < nearest and away > RUN_UP_M:
            nearest = away
            target = at
    if not is_finite(nearest):
        out["error"] = "no solid box stands more than %.0f m from the spawn" % RUN_UP_M
        return out

    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        out["error"] = rig["error"] as String
        return out
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    _give_terrain(solver, terrain)
    RorObjectCollision.apply(terrain, solver)
    solver.set_ground(0.0, true)

    # Which way the rig faces when it is placed at a heading of zero is the rig's own business,
    # so it is measured rather than assumed: place it, settle it, read its forward, and then put
    # it that far back from the pole along that line.
    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    RigBuilder.place(solver, truck, Vector3(start.x, 0.0, start.z), 0.0, 0.15)
    for _settle: int in 60:
        solver.step(dt, chunk)
    var pose: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
    var forward: Vector3 = -pose.basis.z
    forward = Vector3(forward.x, 0.0, forward.z).normalized()
    var from: Vector3 = target - forward * RUN_UP_M
    RigBuilder.place(solver, truck, Vector3(from.x, 0.0, from.z), 0.0, 0.15)
    for _settle: int in 120:
        solver.step(dt, chunk)

    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(THROTTLE)
    # How fast the *body* is going, not how fast the wheels are turning. A truck stopped against
    # a pole with its wheels spinning reads 55 km/h of road speed and is not going anywhere,
    # which is how this gate first passed a rig that had been stopped and then failed it.
    var closest: float = INF
    var before_impact: float = 0.0
    var previous: Vector3 = ActorFrame.of(solver.get_positions(), truck.camera_nodes).origin
    var body_kmh: float = 0.0
    for frame: int in int(DRIVE_SECONDS * 60.0):
        solver.step(dt, chunk)
        var here: Vector3 = ActorFrame.of(solver.get_positions(), truck.camera_nodes).origin
        body_kmh = previous.distance_to(here) * 60.0 * 3.6
        previous = here
        var away: float = Vector2(here.x - target.x, here.z - target.z).length()
        if away < closest:
            closest = away
            before_impact = maxf(before_impact, body_kmh)
        if not is_finite(solver.get_node_position(0).length()):
            out["error"] = "the solver went non-finite %.1f s into the run" % (
                float(frame) / 60.0)
            return out
    out["speed"] = before_impact
    out["value"] = closest
    if closest > MAX_REACH_M:
        out["error"] = (
            "driven at a pole %.0f m away the rig got no closer than %.1f m: the run-up did not"
            % [RUN_UP_M, closest] + " reach it"
        )
        return out
    if body_kmh > before_impact * MAX_SPEED_KEPT:
        out["error"] = (
            "the rig reached the pole at %.0f km/h and its body was still moving at %.0f"
            % [before_impact, body_kmh] + " afterwards: it drove through it"
        )
    return out


## The terrain's own heights, straight from the shape.
func _give_terrain(solver: RefCounted, terrain: RorTerrain) -> void:
    var grid: Dictionary = terrain.lattice()
    var size: int = grid["size"] as int
    var heights: PackedFloat32Array = PackedFloat32Array()
    heights.resize(size * size)
    for z: int in size:
        var row: int = z * size
        for x: int in size:
            heights[row + x] = terrain.height_at(x, z)
    solver.set_heightfield(
        heights, size, size, grid["origin"] as Vector3, grid["spacing"] as float
    )
