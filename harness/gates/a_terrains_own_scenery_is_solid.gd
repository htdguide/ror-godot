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
##
## **The crash is aimed, and it is slow, and both are deliberate.** A rig is nodes; a pole is
## 0.17 m across. The hero truck carries its nodes in longitudinal rows — body sides at ±1.0 m,
## frame rails at ±0.4, a centre line — with 25 cm of nothing between them, and a pole that
## arrives in a gap meets no node and passes through the truck untouched. That is what the node
## model does, upstream's as much as this one's, and it is what this gate did for a day when the
## drift of a full-throttle run moved the pole from a row into a gap: 380 nodes, zero contacts.
## So the gate drives the truck the way a person would: steering by the bearing to the pole so
## that it meets the rig's densest run of nodes near its middle, hands off for the last two
## metres, and holding 25 km/h, which is where a pickup meets a steel post and stays there. The
## hero's own centre line is a single 5 cm row of 11 nodes with 10 cm of nothing either side, and
## the pole steered onto it exactly passed between them; the row 0.4 m to its right catches 36. Driven at 49 km/h the aimed truck broke 21 beams and tore past at
## 66% of its speed, and at 72 km/h it broke 17 and never slowed; those are the beams' stated
## strengths doing what they say. A gate that asked for a stop at 72 km/h was asking for a truck
## welded solid, and it had one until the yield floors were read correctly. Moving the start
## sideways to aim was tried first and does not work here: the ground under the start is not flat,
## so the heading the rig settles to moves with it and the drift is not repeatable.

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
## The speed the rig is held to on the approach. A pickup meets a steel post at 25 km/h and
## stays; at 49 it tears past. See the header.
const APPROACH_KMH: float = 25.0
## How far off that speed brings full throttle or full brake.
const SPEED_HOLD_BAND_KMH: float = 10.0
## The driver: steering intent per radian of bearing between the rig's forward and the aim point,
## and how far out the hands come off so the last of the approach is straight. Pursuit on the
## bearing holds the aim to 3 cm the whole way; steering on the lateral offset instead swung two
## metres either side at every gain tried. The sign is the solver's convention for the hero.
const STEER_GAIN_PER_RAD: float = -4.0
const HANDS_OFF_M: float = 2.0
## Where to aim: the pole-wide lateral window holding the most nodes within this far of the rig's
## middle. The pole's width is La Paz's, off its collision mesh.
const AIM_SEARCH_M: float = 0.5
const AIM_STEP_M: float = 0.05
const POLE_WIDTH_M: float = 0.15
## The rig is a 4 m truck and the pole is 0.7 m across, so "reached it" is the two touching.
const MAX_REACH_M: float = 3.5
## And what it may still be doing after. Aimed at a node row at 25 km/h the hero keeps 19%; at
## 49 km/h it keeps 66% and at 72 all of it. Between those populations, nearer the one that stops.
const MAX_SPEED_KEPT: float = 0.3


static func meta() -> Dictionary:
    return {
        "name": "a_terrains_own_scenery_is_solid",
        "proves": "the objects a loaded terrain ships are solid in the solver, shaped like what they are, and stop a vehicle driven at one",
        "builds_on": ["ror_terrain_objects_are_placed", "obstacles_are_solid"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "between %d and %d boxes, each over %.1f m tall and under %.1f m wide, and a rig"
            % [MIN_BOXES, MAX_BOXES, MIN_POLE_HEIGHT_M, MAX_POLE_WIDTH_M]
            + " driven at one at %.0f km/h, steered onto a dense row of its nodes, touching it,"
            % APPROACH_KMH + " losing"
            + " %.0f%% of its speed there and never passing it" % ((1.0 - MAX_SPEED_KEPT) * 100.0)
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
    var target: Vector3 = _nearest_pole(terrain, boxes)
    if not is_finite(target.x):
        return fail("no solid box stands more than %.0f m from the spawn" % RUN_UP_M)
    var crash: Dictionary = _drive_at_a_pole(mod_dir, terrain, target)
    if (crash["error"] as String) != "":
        return fail(crash["error"] as String, crash["value"] as float)
    return ok(
        (
            "%d solid boxes, the widest %.1f m and the shortest %.1f m tall; steered the rig at"
            + " one, met it at %.0f km/h with the pole %+.2f m off its aim (a %d-node row) and"
            + " %d nodes in contact, kept %.0f%% of its speed; body centre came within %.2f m"
        )
        % [boxes.size(), widest, shortest, crash["speed"], crash["pole_x"], crash["aim_nodes"],
           crash["contacts"], 100.0 * float(crash["kept"]), crash["value"]],
        crash["value"]
    )


## The pole to aim at: the one nearest the terrain's own spawn beyond the run-up, which is the
## one a session would meet. NaN when there is none.
func _nearest_pole(terrain: RorTerrain, boxes: Array[Dictionary]) -> Vector3:
    var start: Vector3 = terrain.start_position()
    var target: Vector3 = Vector3(NAN, NAN, NAN)
    var nearest: float = INF
    for box: Dictionary in boxes:
        var at: Vector3 = (box["transform"] as Transform3D).origin
        var away: float = Vector2(at.x - start.x, at.z - start.z).length()
        if away < nearest and away > RUN_UP_M:
            nearest = away
            target = at
    return target


## Drives the hero truck at the pole, steering to keep the pole on the rig's lateral middle and
## holding the approach speed. Returns the approach speed, the most nodes inside a box at once, the
## share of speed kept, and where the pole crossed the rig relative to its aim when the hands came
## off; `value` is the body centre's closest approach to the pole.
func _drive_at_a_pole(mod_dir: String, terrain: RorTerrain, target: Vector3) -> Dictionary:
    var out: Dictionary = {
        "error": "", "value": 0.0, "speed": 0.0, "kept": 0.0, "contacts": 0, "pole_x": 0.0,
        "aim_nodes": 0,
    }
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
    var start: Vector3 = terrain.start_position()
    RigBuilder.place(solver, truck, Vector3(start.x, 0.0, start.z), 0.0, 0.15)
    for _settle: int in 60:
        solver.step(dt, chunk)
    var pose: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
    var forward: Vector3 = Vector3(-pose.basis.z.x, 0.0, -pose.basis.z.z).normalized()
    var from: Vector3 = target - forward * RUN_UP_M
    RigBuilder.place(solver, truck, Vector3(from.x, 0.0, from.z), 0.0, 0.15)
    for _settle: int in 120:
        solver.step(dt, chunk)
    var aim: Dictionary = _aim_row(solver, truck)
    out["aim_nodes"] = aim["count"]

    solver.start_engine()
    solver.set_gear_selector(1)
    # How fast the *body* is going, not how fast the wheels are turning. A truck stopped against
    # a pole with its wheels spinning reads 55 km/h of road speed and is not going anywhere,
    # which is how this gate first passed a rig that had been stopped and then failed it.
    var previous: Vector3 = ActorFrame.of(solver.get_positions(), truck.camera_nodes).origin
    var ahead: float = INF
    var before_impact: float = 0.0
    var body_kmh: float = 0.0
    var contacts: int = 0
    var pole_x: float = 0.0
    var hands_on: bool = true
    for frame: int in int(DRIVE_SECONDS * 60.0):
        # Hold the approach speed — throttle below it, brake above it, both in proportion — so
        # what arrives at the pole is a truck at the speed the claim is about, not whatever 30 m
        # of acceleration comes to. Cutting the throttle at the speed and coasting is not enough:
        # the approach to La Paz's pole runs downhill and a coasting truck arrived at 43 km/h.
        # Hands off the pedals too once the hands are off the wheel: a controller still holding
        # 25 km/h against a stopped truck drives it round the pole and away at 40.
        if hands_on:
            solver.set_throttle(clampf((APPROACH_KMH - body_kmh) / SPEED_HOLD_BAND_KMH, 0.0, THROTTLE))
            solver.set_brake(clampf((body_kmh - APPROACH_KMH) / SPEED_HOLD_BAND_KMH, 0.0, 1.0))
        else:
            solver.set_throttle(0.0)
            solver.set_brake(0.0)
        var frame_now: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
        var off_aim: float = (
            frame_now.affine_inverse() * Vector3(target.x, frame_now.origin.y, target.z)
        ).x - float(aim["x"])
        if hands_on:
            var still_ahead: float = (target - frame_now.origin).dot(forward)
            if still_ahead > HANDS_OFF_M:
                var bearing: float = atan2(off_aim, still_ahead)
                solver.set_steer_command(
                    DriveCfg.steer_command(clampf(STEER_GAIN_PER_RAD * bearing, -1.0, 1.0))
                )
            else:
                solver.set_steer_command(0.0)
                hands_on = false
                pole_x = off_aim
        solver.step(dt, chunk)
        frame_now = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
        var here: Vector3 = frame_now.origin
        body_kmh = previous.distance_to(here) * 60.0 * 3.6
        previous = here
        var to_pole: float = Vector2(here.x - target.x, here.z - target.z).length()
        if to_pole < ahead:
            ahead = to_pole
            before_impact = maxf(before_impact, body_kmh)
        if to_pole < 6.0:
            contacts = maxi(contacts, _nodes_in_a_box(solver))
        if not is_finite(solver.get_node_position(0).length()):
            out["error"] = "the solver went non-finite %.1f s into the run" % (
                float(frame) / 60.0)
            return out
    out["speed"] = before_impact
    out["value"] = ahead
    out["kept"] = body_kmh / maxf(before_impact, 0.1)
    out["contacts"] = contacts
    out["pole_x"] = pole_x
    if ahead > MAX_REACH_M:
        out["error"] = (
            "driven at a pole %.0f m away the rig got no closer than %.1f m: the run-up did not"
            % [RUN_UP_M, ahead] + " reach it"
        )
        return out
    var aimed: String = " (pole %+.2f m off its aim when the hands came off; %d nodes in contact)" % [
        pole_x, contacts]
    if contacts == 0:
        out["error"] = (
            "steered onto a %d-node row of the rig, the pole met no node at all: either the boxes"
            % aim["count"] + " are not where the pole is or the rig has a gap there" + aimed
        )
    elif float(out["kept"]) > MAX_SPEED_KEPT:
        out["error"] = (
            "the rig reached the pole at %.0f km/h and its body was still moving at %.0f"
            % [before_impact, body_kmh] + " afterwards: it did not stop" + aimed
        )
    return out


## How many of the rig's nodes are inside a solid box right now.
func _nodes_in_a_box(solver: RefCounted) -> int:
    var count: int = 0
    for position: Vector3 in solver.get_positions():
        if bool((solver.obstacle_contact(position) as Dictionary)["hit"]):
            count += 1
    return count


## Where across the rig to put the pole: the pole-wide lateral window (rig frame) holding the most
## nodes within `AIM_SEARCH_M` of the rig's middle, the middle being halfway between its outermost
## nodes. Measured rather than taken as x = 0 — the frame's origin is a camera node 0.4 m off the
## hero's centre line — and a window the pole's own width because that is what the pole sweeps.
func _aim_row(solver: RefCounted, truck: TruckParser) -> Dictionary:
    var inverse: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes).affine_inverse()
    var xs: PackedFloat32Array = PackedFloat32Array()
    var lo: float = INF
    var hi: float = -INF
    for position: Vector3 in solver.get_positions():
        var x: float = (inverse * position).x
        xs.append(x)
        lo = minf(lo, x)
        hi = maxf(hi, x)
    var middle: float = (lo + hi) * 0.5
    var best_x: float = middle
    var best_count: int = -1
    var steps: int = int(AIM_SEARCH_M / AIM_STEP_M)
    for i: int in range(-steps, steps + 1):
        var centre: float = middle + float(i) * AIM_STEP_M
        var count: int = 0
        for x: float in xs:
            if absf(x - centre) <= POLE_WIDTH_M * 0.5:
                count += 1
        if count > best_count:
            best_count = count
            best_x = centre
    return {"x": best_x, "count": best_count}


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
