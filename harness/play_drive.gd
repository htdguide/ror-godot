class_name PlayDrive
extends RefCounted
## Drives a built vehicle from the keyboard: the solver runs, the rig moves, the mesh
## follows.
##
## Everything a person needs in order to say whether the thing drives right, and nothing
## else. The controls are read here, the solver is stepped here, and the pose is pushed to
## the renderer here, so there is one place to look when the window and the gates disagree.
##
## The cab is driven from the same place: the steering wheel turns, the gauges read the
## drivetrain, and the lamps light by what the vehicle is doing rather than all together.


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
var _lit: bool = false
var _left_indicator: bool = false
var _right_indicator: bool = false
var _seconds: float = 0.0
var _cockpit: Node3D


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
    _cockpit = Cockpit.build(built["root"] as Node3D, truck, built)
    _apply_pose()
    return ""


## The node this vehicle draws through, for a session swapping one vehicle for another.
func vehicle_root() -> Node3D:
    return _built.get("root", null) as Node3D


## Puts the rig back at its spawn. The menu changes vehicles by placing the new one where the old
## one stood and calling this, so a swap and a reset are the same operation.
func respawn() -> void:
    _respawn()


## The driver's eye in the vehicle's own local frame, for a camera to sit at. The cinecam is in
## rig space, and the vehicle is drawn in its own, so the frame it was built with converts.
func eye() -> Vector3:
    return (_built["rig_to_local"] as Transform3D) * Cockpit.eye_position(truck)


## Whether the lamps are on, and a way for a panel to say so.
func lights_on() -> bool:
    return _lit


func set_lights(on: bool) -> void:
    _lit = on
    print("DRIVE  lights %s" % ("on" if _lit else "off"))


## Where this world starts a vehicle, and which way it faces. Zero is the middle of a generated
## world; a loaded terrain states its own, and La Paz's is 3.9 km along its own map.
var spawn: Vector3 = Vector3.ZERO
var spawn_heading: float = 0.0


## Stands the rig on a terrain instead of the flat plane. Returns "" on success.
func use_terrain(data: Object) -> String:
    var applied: String = Harness.terrain.give_to_solver(solver, data)
    if applied != "":
        return applied
    # Put the rig down on the surface rather than where the flat plane used to be, or it
    # spawns inside a hillside and is fired out of it.
    _respawn()
    return ""


func step(delta: float) -> void:
    _seconds += delta
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
    _apply_cabin()


func on_key(keycode: Key) -> bool:
    match keycode:
        KEY_B:
            _set_selector(-1)
        KEY_H:
            _set_selector(0)
        KEY_G:
            _set_selector(1)
        KEY_R:
            # Back to where the map starts the vehicle, undamaged — what a person means by
            # "reset". Recovery in place, which this used to do, is on Enter. The gears moved to
            # make room: B backs it up, H is neutral.
            _respawn()
        KEY_I:
            if solver.engine_running():
                solver.stop_engine()
            else:
                solver.start_engine()
            print("DRIVE  engine %s" % ("running" if solver.engine_running() else "off"))
        KEY_L, KEY_N:
            set_lights(not _lit)
        KEY_Z:
            _left_indicator = not _left_indicator
            _right_indicator = false
            print("DRIVE  left indicator %s" % ("on" if _left_indicator else "off"))
        KEY_C:
            _right_indicator = not _right_indicator
            _left_indicator = false
            print("DRIVE  right indicator %s" % ("on" if _right_indicator else "off"))
        KEY_X:
            _left_indicator = false
            _right_indicator = false
            print("DRIVE  indicators off")
        KEY_BACKSPACE:
            _respawn()
        KEY_ENTER:
            _recover()
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
        + "throttle %.2f  brake %.2f  steer %+.2f  lights %s  solver %.2f ms"
        % [
            _throttle, _brake, solver.steer_state(), "on" if _lit else "off",
            float(_solver_usec) / 1000.0,
        ]
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
    solver.set_steer_command(DriveCfg.steer_command(steer))


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


## Sets the rig upright where it is, keeping the heading it was travelling on.
##
## What a person wants after rolling a truck is to carry on from there, not to be sent back to
## the start — a recovery, not a respawn. The rig is rebuilt from its rest shape rather than
## being rotated in place: a rolled soft-body vehicle is deformed, and turning the wreck the
## right way up leaves it a wreck. Upstream's reset does the same.
func _recover() -> void:
    var positions: PackedVector3Array = solver.get_positions()
    var origin: Vector3 = ActorFrame.of(positions, truck.camera_nodes).origin
    # Keep where it is and which way it was facing; discard the roll and pitch that put it
    # on its roof.
    RigBuilder.place(
        solver,
        truck,
        origin,
        RigBuilder.heading_of(positions, truck.camera_nodes),
        DriveCfg.RECOVER_CLEARANCE_M
    )
    solver.start_engine()
    _apply_pose()
    print("DRIVE  recovered")


## Puts the rig back where it started, upright and at rest.
func _respawn() -> void:
    RigBuilder.place(solver, truck, spawn, spawn_heading, DriveCfg.SPAWN_HEIGHT_M)
    _lit = false
    solver.start_engine()
    _apply_pose()
    print("DRIVE  respawned")


## The parts of the vehicle that are driven rather than posed: the lamps, the steering wheel and
## the instruments. Updated per frame from the state the controls left behind.
func _apply_cabin() -> void:
    FlareBuilder.apply_state(_built["lamps"] as Array[Node3D], truck, {
        "headlights": _lit,
        "brake": _brake,
        "reverse": _selector < 0,
        "left": _left_indicator,
        "right": _right_indicator,
        "seconds": _seconds,
    })
    Cockpit.turn_wheel(_built, truck, solver.steer_state())
    Cockpit.update(_cockpit, solver.engine_rpm(), solver.road_speed(), _lit)
