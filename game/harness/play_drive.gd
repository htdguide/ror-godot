class_name PlayDrive
extends RefCounted
## Drives a built vehicle from the keyboard: the solver runs, the rig moves, the mesh
## follows.
##
## Everything a person needs in order to say whether the thing drives right, and nothing
## else. The controls are read here, the solver is stepped here, and the pose is pushed to
## the renderer here, so there is one place to look when the window and the gates disagree.


var solver: RefCounted
var truck: TruckParser
## The vehicle's own frame after the last pose, for a camera to follow.
var frame: Transform3D = Transform3D.IDENTITY

var _built: Dictionary = {}
var _throttle: float = 0.0
var _brake: float = 0.0
var _substep_remainder: float = 0.0
var _solver_usec: int = 0
var _selector: int = 1


## Returns "" on success. `built` is a VehicleBuilder result.
func setup(built: Dictionary) -> String:
    _built = built
    truck = built["truck"] as TruckParser
    var rig: Dictionary = RigBuilder.build(truck, DriveCfg.SPAWN_HEIGHT_M)
    if (rig["error"] as String) != "":
        return rig["error"] as String
    solver = rig["solver"] as RefCounted
    solver.set_ground(0.0, true)
    solver.start_engine()
    solver.set_gear_selector(_selector)
    _apply_pose()
    return ""


## Stands the rig on a terrain instead of the flat plane. Returns "" on success.
func use_terrain(data: Object) -> String:
    var applied: String = TerrainHeightfield.apply(
        solver, data, TerrainCfg.ORIGIN, TerrainCfg.MAP_SIZE, TerrainCfg.MAP_SIZE,
        TerrainCfg.VERTEX_SPACING
    )
    if applied != "":
        return applied
    # Put the rig down on the surface rather than where the flat plane used to be, or it
    # spawns inside a hillside and is fired out of it.
    _respawn()
    return ""


func step(delta: float) -> void:
    _read_controls(delta)
    # Substeps follow wall-clock time rather than a fixed count per frame, so the rig
    # drives at the same speed whatever the window is managing.
    var wanted: float = delta * DriveCfg.SUBSTEP_HZ + _substep_remainder
    var substeps: int = mini(int(wanted), DriveCfg.MAX_SUBSTEPS_PER_FRAME)
    _substep_remainder = wanted - float(substeps)
    if substeps <= 0:
        return
    var began: int = Time.get_ticks_usec()
    solver.step(1.0 / DriveCfg.SUBSTEP_HZ, substeps)
    _solver_usec = Time.get_ticks_usec() - began
    _apply_pose()


func on_key(keycode: Key) -> bool:
    match keycode:
        KEY_R:
            _set_selector(-1)
        KEY_N:
            _set_selector(0)
        KEY_G:
            _set_selector(1)
        KEY_I:
            if solver.engine_running():
                solver.stop_engine()
            else:
                solver.start_engine()
            print("DRIVE  engine %s" % ("running" if solver.engine_running() else "off"))
        KEY_BACKSPACE:
            _respawn()
        _:
            return false
    return true


func hud_line() -> String:
    # Road speed is what the driven wheels are turning at, which is the speed the rig's own
    # drivetrain works from. It is not the same as how fast the vehicle is going, and the
    # difference is wheelspin.
    return (
        "%s  gear %s  %4.0f rpm  clutch %.2f  wheels %.0f km/h  %.0f Nm\n"
        % [
            "ON" if solver.engine_running() else "OFF",
            _gear_name(),
            solver.engine_rpm(),
            solver.engine_clutch(),
            solver.road_speed() * 3.6,
            solver.engine_torque(),
        ]
        + "throttle %.2f  brake %.2f  steer %+.2f  solver %.2f ms"
        % [_throttle, _brake, solver.steer_state(), float(_solver_usec) / 1000.0]
    )


func _read_controls(delta: float) -> void:
    var wants_throttle: bool = Input.is_key_pressed(KEY_UP)
    var wants_brake: bool = Input.is_key_pressed(KEY_DOWN)
    _throttle = clampf(
        _throttle + (DriveCfg.THROTTLE_RATE if wants_throttle else -DriveCfg.THROTTLE_RATE) * delta,
        0.0,
        1.0
    )
    _brake = clampf(
        _brake + (DriveCfg.BRAKE_RATE if wants_brake else -DriveCfg.BRAKE_RATE) * delta, 0.0, 1.0
    )
    var steer: float = 0.0
    if Input.is_key_pressed(KEY_LEFT):
        steer += 1.0
    if Input.is_key_pressed(KEY_RIGHT):
        steer -= 1.0
    solver.set_throttle(_throttle)
    solver.set_brake(_brake)
    solver.set_parking_brake(Input.is_key_pressed(KEY_SPACE))
    solver.set_steer_command(steer)


func _apply_pose() -> void:
    var positions: PackedVector3Array = solver.get_positions()
    if positions.is_empty() or not is_finite(positions[0].length()):
        return
    var angles: PackedFloat32Array = PackedFloat32Array()
    for wheel: int in solver.wheel_count():
        angles.append(solver.get_wheel_rotation(wheel))
    VehicleBuilder.apply_pose(_built, truck, positions, angles)
    frame = ActorFrame.of(positions, truck.camera_nodes)


func _set_selector(selector: int) -> void:
    _selector = selector
    solver.set_gear_selector(selector)
    print("DRIVE  %s" % _gear_name())


func _gear_name() -> String:
    var gear: int = solver.engine_gear()
    if gear < 0:
        return "R"
    if gear == 0:
        return "N"
    return "%d" % gear


## Puts the rig back where it started, upright and at rest. The one control a person always
## wants after rolling a truck onto its roof.
func _respawn() -> void:
    var lowest: float = INF
    for node: Vector3 in truck.nodes:
        lowest = minf(lowest, node.y)
    # On terrain the spawn height is relative to the ground under the rig, not to zero.
    var ground: float = solver.ground_height_at(Vector3.ZERO)
    var lift: Vector3 = Vector3(0.0, ground + DriveCfg.SPAWN_HEIGHT_M - lowest, 0.0)
    for i: int in truck.nodes.size():
        solver.set_node_position(i, truck.nodes[i] + lift)
        solver.set_node_velocity(i, Vector3.ZERO)
    for beam: int in solver.beam_count():
        solver.set_beam_rest_length(beam, solver.get_beam_reference_length(beam))
    solver.set_steer_command(0.0)
    solver.start_engine()
    _apply_pose()
    print("DRIVE  respawned")
