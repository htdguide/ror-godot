class_name DriveRoute
extends RefCounted
## Drives a rig along a route through the valley and reports what happened to it.
##
## PLAN M1 acceptance 7 wants three scenarios — the switchback climb, the ford crossing and the
## rut traverse — completed "without the actor falling through terrain, getting stuck, or
## exploding", with the solver's energy bounded. Those are four different failures with four
## different signatures, and a run that ends early tells you nothing unless it says which one it
## was. So this drives, watches all four, and returns the numbers rather than a verdict: the gate
## that called it decides what its route was supposed to do.
##
## The driver is deliberately simple — steer toward the next waypoint, hold a speed, change gear
## on engine speed — because it is a fixture, not a feature. A route that only a clever driver can
## complete is a route that says nothing about the terrain, and the terrain is the subject here.
## When a gate fails, the first question to ask is whether the driver could have done better; the
## reported path and the reason are there to answer it.

const FRAME_HZ: float = 60.0
## How close counts as arriving. A truck is 5 m long and the corridor is 11 m wide, so asking for
## much less than this is asking the driver to thread a needle rather than follow a road.
const REACH_M: float = 9.0
## Steering: how hard to turn per radian of heading error, before the command is clamped.
const STEER_GAIN: float = 1.6
## Throttle, as a share of the target speed. Below the target the driver is on the throttle; above
## it, off; well above, braking.
const THROTTLE_ON: float = 0.55
const THROTTLE_IDLE: float = 0.12
const BRAKE_OVER_SHARE: float = 1.35
const BRAKE: float = 0.35
## Gear changes, as shares of the engine's own maximum speed.
const UPSHIFT_SHARE: float = 0.80
const DOWNSHIFT_SHARE: float = 0.35
## How long the rig is allowed to make no progress before it counts as stuck.
const STUCK_WINDOW_S: float = 8.0
const STUCK_TRAVEL_M: float = 3.0
## A node this far under the terrain has gone through it.
##
## The terrain here is the one the renderer draws — the `RorTerrain` read from its author's own
## files — and not the heightfield the solver was handed. Asking the solver whether its own
## ground is where it thinks it is cannot fail: a heightfield handed over five metres low was
## driven on quite happily, with the rig floating five metres over the drawn terrain and every
## check reporting nothing wrong.
const FALL_THROUGH_M: float = 1.0
## And the other half of the same claim: the rig has to stay *on* that ground. A wheel lifts over a
## crest, so this is a clearance that has to be held for a while before it counts.
const FLOAT_M: float = 0.9
const FLOAT_WINDOW_S: float = 2.5
## A node moving this fast is not driving, whatever else it is doing.
const EXPLODE_SPEED_MS: float = 60.0
## How often every node is checked against the terrain. Every frame costs a terrain query per node
## per frame and makes a long route slower to watch than to drive; a rig that goes through the
## ground stays through it, so three times a second is enough to catch it.
const WATCH_EVERY: int = 20
## How long to let the rig settle on its springs before the engine starts.
const SETTLE_S: float = 1.5


## Drives `solver` along `waypoints` (world x/z) and returns what happened.
##
## Returns {"error", "reason", "completed", "reached", "distance_m", "seconds", "worst_speed_ms",
## "deepest_m", "energy_ratio", "path"}. `reason` is "" when the route completed.
## `terrain` is the terrain being driven on, asked for its own heights as the renderer-side
## oracle. Without it the fall-through and floating checks have nothing to compare against.
static func drive(
    solver: RefCounted, truck: TruckParser, waypoints: Array[Vector2], options: Dictionary,
    terrain: Object
) -> Dictionary:
    var substep_hz: float = float(options.get("substep_hz", 2000.0))
    var limit_s: float = float(options.get("limit_s", 180.0))
    var target_speed: float = float(options.get("target_speed_ms", 6.0))
    var dt: float = 1.0 / substep_hz
    var chunk: int = int(substep_hz / FRAME_HZ)

    solver.set_brake(1.0)
    for _i: int in int(SETTLE_S * FRAME_HZ):
        solver.step(dt, chunk)
    solver.set_brake(0.0)
    var settled_energy: float = maxf(solver.total_energy(), 0.0001)
    solver.start_engine()
    solver.set_gear_selector(1)

    var start_height: float = _origin(solver, truck).y
    var state: Dictionary = {
        "error": "", "reason": "", "completed": false, "reached": 0, "distance_m": 0.0,
        "seconds": 0.0, "worst_speed_ms": 0.0, "deepest_m": 0.0, "energy_ratio": 1.0,
        "climb_m": 0.0, "clearance_m": 0.0, "floating_since": -1.0,
        "path": PackedVector2Array(),
    }
    # Kept as a local and handed back at the end: a PackedVector2Array in a Dictionary is a value,
    # so appending to it through the Dictionary appends to a copy and the path comes out empty.
    var path: PackedVector2Array = PackedVector2Array()
    var index: int = 1
    var previous: Vector3 = _origin(solver, truck)
    var progress_mark: Vector3 = previous
    var progress_at: float = 0.0
    var frames: int = int(limit_s * FRAME_HZ)
    for frame: int in frames:
        var seconds: float = float(frame) / FRAME_HZ
        var pose: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
        if not is_finite(pose.origin.length()):
            state["reason"] = "the solver went non-finite after %.1f s" % seconds
            state["seconds"] = seconds
            return state
        _steer_toward(solver, pose, waypoints[index], target_speed)
        _change_gear(solver)
        solver.step(dt, chunk)

        var here: Vector3 = _origin(solver, truck)
        state["distance_m"] = (state["distance_m"] as float) + Vector2(
            here.x - previous.x, here.z - previous.z
        ).length()
        previous = here
        state["climb_m"] = here.y - start_height
        if frame % int(FRAME_HZ) == 0:
            path.append(Vector2(here.x, here.z))
            state["path"] = path

        var watched: String = ""
        if frame % WATCH_EVERY == 0:
            watched = _watch(solver, state, settled_energy, seconds, terrain)
        if watched != "":
            state["reason"] = watched
            state["seconds"] = seconds
            return state

        if Vector2(here.x - waypoints[index].x, here.z - waypoints[index].y).length() < REACH_M:
            index += 1
            state["reached"] = index - 1
            progress_mark = here
            progress_at = seconds
            if index >= waypoints.size():
                state["completed"] = true
                state["seconds"] = seconds
                return state
        elif seconds - progress_at > STUCK_WINDOW_S:
            var moved: float = Vector2(
                here.x - progress_mark.x, here.z - progress_mark.z
            ).length()
            if moved < STUCK_TRAVEL_M:
                state["reason"] = (
                    "stuck at %v: %.1f m in %.0f s while making for waypoint %d at %v"
                    % [Vector2(here.x, here.z), moved, STUCK_WINDOW_S, index, waypoints[index]]
                )
                state["seconds"] = seconds
                return state
            progress_mark = here
            progress_at = seconds

    state["seconds"] = limit_s
    state["reason"] = (
        "ran out of time %.0f m from waypoint %d of %d, having travelled %.0f m"
        % [
            Vector2(previous.x - waypoints[index].x, previous.z - waypoints[index].y).length(),
            index, waypoints.size() - 1, state["distance_m"] as float,
        ]
    )
    return state


## The four ways a run ends badly, watched every frame. Returns "" while nothing is wrong.
static func _watch(
    solver: RefCounted, state: Dictionary, settled_energy: float, seconds: float,
    terrain: Object
) -> String:
    var deepest: float = 0.0
    var fastest: float = 0.0
    var clearance: float = INF
    var positions: PackedVector3Array = solver.get_positions()
    for node: int in positions.size():
        var at: Vector3 = positions[node]
        var ground: float = terrain.call("height_at_world", at.x, at.z)
        deepest = maxf(deepest, ground - at.y)
        clearance = minf(clearance, at.y - ground)
        fastest = maxf(fastest, solver.get_node_velocity(node).length())
    state["clearance_m"] = clearance
    state["deepest_m"] = maxf(state["deepest_m"] as float, deepest)
    state["worst_speed_ms"] = maxf(state["worst_speed_ms"] as float, fastest)
    var energy: float = solver.total_energy() / settled_energy
    state["energy_ratio"] = maxf(state["energy_ratio"] as float, energy)
    if deepest > FALL_THROUGH_M:
        return "a node was %.2f m under the terrain after %.1f s: it fell through" % [
            deepest, seconds]
    if fastest > EXPLODE_SPEED_MS:
        return "a node reached %.0f m/s after %.1f s: the rig came apart" % [fastest, seconds]
    if clearance > FLOAT_M:
        var since: float = state["floating_since"] as float
        if since < 0.0:
            state["floating_since"] = seconds
        elif seconds - since > FLOAT_WINDOW_S:
            return (
                "the rig's lowest node has been %.2f m over the terrain for %.1f s after %.1f s:"
                % [clearance, seconds - since, seconds]
                + " it is not driving on the ground it is drawn on"
            )
    else:
        state["floating_since"] = -1.0
    return ""


## Points the steering at a waypoint and sets the throttle for a target speed.
static func _steer_toward(
    solver: RefCounted, pose: Transform3D, target: Vector2, target_speed: float
) -> void:
    var forward: Vector3 = -pose.basis.z
    var flat_forward: Vector2 = Vector2(forward.x, forward.z).normalized()
    var to_target: Vector2 = (target - Vector2(pose.origin.x, pose.origin.z)).normalized()
    # Positive intent is left, which is the convention `DriveCfg.steer_command` owns.
    # Negated: in the x/z plane a positive cross product puts the target to the rig's right,
    # while `DriveCfg.steer_command`'s positive intent is left. Taken the other way round the
    # driver steers away from every waypoint and the rig drives in circles, which is what it did.
    var error: float = -atan2(
        flat_forward.x * to_target.y - flat_forward.y * to_target.x,
        flat_forward.dot(to_target)
    )
    solver.set_steer_command(DriveCfg.steer_command(clampf(error * STEER_GAIN, -1.0, 1.0)))
    var speed: float = absf(solver.road_speed())
    if speed > target_speed * BRAKE_OVER_SHARE:
        solver.set_throttle(0.0)
        solver.set_brake(BRAKE)
    elif speed > target_speed:
        solver.set_throttle(THROTTLE_IDLE)
        solver.set_brake(0.0)
    else:
        solver.set_throttle(THROTTLE_ON)
        solver.set_brake(0.0)


## Changes gear on engine speed, which is all an automatic gearbox is from the outside.
static func _change_gear(solver: RefCounted) -> void:
    var maximum: float = maxf(solver.engine_max_rpm(), 1.0)
    var share: float = solver.engine_rpm() / maximum
    var gear: int = solver.engine_gear()
    if share > UPSHIFT_SHARE and gear < solver.engine_gear_count():
        solver.set_gear_selector(gear + 1)
    elif share < DOWNSHIFT_SHARE and gear > 1:
        solver.set_gear_selector(gear - 1)


static func _origin(solver: RefCounted, truck: TruckParser) -> Vector3:
    return ActorFrame.of(solver.get_positions(), truck.camera_nodes).origin
