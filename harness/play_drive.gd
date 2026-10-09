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

## Whether the solver steps on this thread or on its own. PLAN §3.2 says `--deterministic` forces
## one thread, and this is where the harness grants it. The thread changes where the arithmetic
## runs and not what it is — `the_solver_steps_on_its_own_thread` hashes the two against each
## other — so the flag is policy rather than a fix.
var synchronous: bool = Harness.args.has_flag("deterministic")
## What the solver cost last frame, on whichever thread ran it, and how long this thread waited
## for it. Public so a gate can read a frame's figures without parsing the metric line.
var solver_usec: int = 0
var wait_usec: int = 0

var _built: Dictionary = {}
var _throttle: float = 0.0
var _brake: float = 0.0
var _substep_remainder: float = 0.0
var _deform_usec: int = 0
var _submit_usec: int = 0
var _stepped: bool = false
## A steer held by a script instead of the keys, as a photograph wants the wheels turned. NAN
## leaves the keys in charge.
var scripted_steer: float = NAN
## The solver's state as of this frame's step: node positions, wheel angles and the drivetrain's
## readings. Everything drawn or shown is drawn from this and not from the solver, so that nothing
## asks the solver anything while it is stepping. See `begin` and `finish`.
var _state: Dictionary = {}
var _selector: int = 1
var _lit: bool = false
## The main beam. A second filament rather than a second switch: it only shows while the lights
## are on, and a vehicle with no `h` lamps of its own puts its low beams onto the main-beam
## pattern instead.
var _main_beam: bool = false
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
    _snapshot()
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


## One frame, in one call: `begin` and then `finish`. A session that has work of its own between
## the two — the camera, the grass, the HUD — calls them apart, and the solver runs on its thread
## while that work is done.
func step(delta: float) -> void:
    begin(delta)
    finish()


## Reads the controls onto the rig and posts this frame's substeps to the solver's thread.
##
## **The step is posted first and drawn last, inside one frame.** The first version of this drew
## the *last* frame's step and posted this frame's, which is Rigs of Rods' own model and is one
## frame of lag; under frame times that vary — a window with vsync off runs 9 to 13 ms — the lag
## varies with them, and a session saw every vehicle stutter. The thread gate could not: it holds
## positions, not when they are drawn. So the rig drawn in a frame is the rig the solver has at
## the end of that frame, and what the thread overlaps is whatever the session does between
## `begin` and `finish`, which is honest about how little that is at 0.5 ms a step.
func begin(delta: float) -> void:
    _seconds += delta
    _read_controls(delta)
    # Substeps follow wall-clock time rather than a fixed count per frame, so the rig
    # drives at the same speed whatever the window is managing.
    var wanted: float = delta * DriveCfg.SUBSTEP_HZ + _substep_remainder
    var substeps: int = mini(int(wanted), DriveCfg.MAX_SUBSTEPS_PER_FRAME)
    _substep_remainder = wanted - float(substeps)
    _stepped = substeps > 0
    if not _stepped:
        return
    if synchronous:
        solver.step(1.0 / DriveCfg.SUBSTEP_HZ, substeps)
    else:
        solver.step_async(1.0 / DriveCfg.SUBSTEP_HZ, substeps)


## Waits for the step, takes the state it produced, and poses the vehicle from it. What is
## measured is the step's own time on its own thread, and separately the time this thread spent
## waiting for it here.
func finish() -> void:
    _snapshot()
    wait_usec = solver.take_wait_usec()
    Harness.metrics.phase("solver", solver_usec)
    Harness.metrics.phase("solver_wait", wait_usec)
    if not _stepped:
        return
    _apply_pose()
    _apply_cabin()


## The node positions the vehicle was last posed from. A gate compares them with the solver's
## own, which is how "drawn this frame, not last" is held.
func posed_positions() -> PackedVector3Array:
    return _state.get("positions", PackedVector3Array()) as PackedVector3Array


## Copies out what this frame draws and shows. Waits for a pending step, which is where a frame
## pays for a solver slower than the work it overlapped.
func _snapshot() -> void:
    solver_usec = solver.take_step_usec()
    var angles: PackedFloat32Array = PackedFloat32Array()
    for wheel: int in solver.wheel_count():
        angles.append(solver.get_wheel_rotation(wheel))
    _state = {
        "positions": solver.get_positions(),
        "angles": angles,
        "steer": solver.steer_state(),
        "rpm": solver.engine_rpm(),
        "road_speed": solver.road_speed(),
        "torque": solver.engine_torque(),
        "clutch": solver.engine_clutch(),
        "gear": solver.engine_gear(),
        "running": solver.engine_running(),
    }


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
        KEY_K:
            _main_beam = not _main_beam
            print("DRIVE  main beam %s" % ("on" if _main_beam else "off"))
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
            "ON" if bool(_state.get("running", false)) else "OFF",
            _gear_name(),
            float(_state.get("rpm", 0.0)),
            float(_state.get("clutch", 0.0)),
            float(_state.get("road_speed", 0.0)) * 3.6,
            float(_state.get("torque", 0.0)),
        ]
        + "throttle %.2f  brake %.2f  steer %+.2f  lights %s  solver %.2f  wait %.2f  deform %.2f  submit %.2f ms"
        % [
            _throttle, _brake, float(_state.get("steer", 0.0)), "on" if _lit else "off",
            float(solver_usec) / 1000.0, float(wait_usec) / 1000.0,
            float(_deform_usec) / 1000.0, float(_submit_usec) / 1000.0,
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
    if not is_nan(scripted_steer):
        steer = scripted_steer
    solver.set_steer_command(DriveCfg.steer_command(steer))


## Poses the vehicle from the last snapshot. Asks the solver nothing.
func _apply_pose() -> void:
    var positions: PackedVector3Array = _state.get("positions", PackedVector3Array())
    if positions.is_empty() or not is_finite(positions[0].length()):
        return
    var angles: PackedFloat32Array = _state.get("angles", PackedFloat32Array())
    var timed: Dictionary = VehicleBuilder.apply_pose(_built, truck, positions, angles)
    _deform_usec = timed["deform_usec"] as int
    _submit_usec = timed["submit_usec"] as int
    Harness.metrics.phase("deform", _deform_usec)
    Harness.metrics.phase("submit", _submit_usec)
    frame = ActorFrame.of(positions, truck.camera_nodes)


func _set_selector(selector: int) -> void:
    _selector = selector
    solver.set_gear_selector(selector)
    print("DRIVE  %s" % _gear_name())


func _gear_name() -> String:
    var gear: int = int(_state.get("gear", 0))
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
    _snapshot()
    _apply_pose()
    print("DRIVE  recovered")


## Puts the rig back where it started, upright and at rest.
func _respawn() -> void:
    RigBuilder.place(solver, truck, spawn, spawn_heading, DriveCfg.SPAWN_HEIGHT_M)
    _lit = false
    _main_beam = false
    solver.start_engine()
    _snapshot()
    _apply_pose()
    print("DRIVE  respawned")


## The parts of the vehicle that are driven rather than posed: the lamps, the steering wheel and
## the instruments. Updated per frame from the state the controls left behind.
func _apply_cabin() -> void:
    FlareBuilder.apply_state(_built["lamps"] as Array[Node3D], truck, {
        "headlights": _lit,
        "high_beam": _main_beam,
        "brake": _brake,
        "reverse": _selector < 0,
        "left": _left_indicator,
        "right": _right_indicator,
        "seconds": _seconds,
    })
    Cockpit.turn_wheel(_built, truck, float(_state.get("steer", 0.0)))
    Cockpit.update(
        _cockpit, float(_state.get("rpm", 0.0)), float(_state.get("road_speed", 0.0)), _lit
    )
