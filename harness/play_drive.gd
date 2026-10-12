class_name PlayDrive
extends RefCounted
## Drives a built vehicle from the keyboard: the solver runs, the rig moves, the mesh follows.
##
## Everything a person needs in order to say whether the thing drives right, and nothing
## else. The controls are read here, the solver is stepped here, and the pose is pushed to
## the renderer here, so there is one place to look when the window and the gates disagree.
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
var _airplane: AirplaneKeys = null
var _throttle: float = 0.0
var _brake: float = 0.0
var _substep_remainder: float = 0.0
var _deform_usec: int = 0
var _submit_usec: int = 0
var _stepped: bool = false
## A steer held by a script instead of the keys, as a photograph wants the wheels turned. NAN
## leaves the keys in charge.
var scripted_steer: float = NAN
## And a throttle, for a measurement that drives: NAN leaves the keys in charge.
var scripted_throttle: float = NAN
## The solver's state as of this frame's step: node positions, wheel angles and the drivetrain's
## readings. Everything drawn or shown is drawn from this and not from the solver, so that nothing
## asks the solver anything while it is stepping. See `begin` and `finish`.
var _state: Dictionary = {}
var _selector: int = 1
## The lamps and their switches (`DriveLights`).
var _lights: DriveLights
var _seconds: float = 0.0
var _cockpit: Node3D
## When a `RorWorld` steps this vehicle together with others, `begin` reads the controls and works
## out the substeps but leaves the stepping to the world, which reads them from here.
var world_stepped: bool = false
## The world this vehicle is stepped in, for its hooks to reach the others; null alone.
var world: RorWorld = null
var substeps_wanted: int = 0
## Which key does what for this driver. A one-driver window keeps `DriveKeys.SOLO`; a split
## window hands each driver its own half of the keyboard.
var keys: Dictionary = DriveKeys.SOLO


## Returns "" on success. `built` is a VehicleBuilder result.
func setup(built: Dictionary) -> String:
    _built = built
    truck = built["truck"] as TruckParser
    if truck.modules.size() > 1:
        print("DRIVE  modules %s; built with %s (choose with <file>@<module>)" % [", ".join(truck.modules), truck.selected_module])
    var rig: Dictionary = RigBuilder.build(truck, DriveCfg.SPAWN_HEIGHT_M)
    if (rig["error"] as String) != "":
        return rig["error"] as String
    solver = rig["solver"] as RefCounted
    solver.set_ground(0.0, true)
    solver.start_engine()
    solver.set_gear_selector(_selector)
    _cockpit = Cockpit.build(built["root"] as Node3D, truck, built)
    _lights = DriveLights.new(truck)
    _airplane = AirplaneKeys.new() if not truck.links.aero_engines.is_empty() else null
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
    return _lights.state.headlights


func set_lights(on: bool) -> void:
    _lights.set_headlights(on)
    print("DRIVE  lights %s" % ("on" if on else "off"))


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
## **The step is posted first and drawn last, inside one frame.** Drawing the last frame's step
## (Rigs of Rods' own model) is a frame of lag that varies with frame time, and a session saw every
## vehicle stutter; so the rig drawn in a frame is the rig the solver has at the end of it.
func begin(delta: float) -> void:
    _seconds += delta
    _read_controls(delta)
    # Substeps follow wall-clock time rather than a fixed count per frame, so the rig
    # drives at the same speed whatever the window is managing.
    var wanted: float = delta * DriveCfg.SUBSTEP_HZ + _substep_remainder
    var substeps: int = mini(int(wanted), DriveCfg.MAX_SUBSTEPS_PER_FRAME)
    _substep_remainder = wanted - float(substeps)
    _stepped = substeps > 0
    substeps_wanted = substeps
    if not _stepped or world_stepped:
        return
    # Alone, its auto-lock hooks try their own nodes once a frame; a world does this for everyone.
    if solver.hook_count() > 0:
        solver.toggle_hooks(0, -2)
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
        "contact": solver.engine_contact(),
    }


func on_key(keycode: Key) -> bool:
    if DriveKeys.is_cruise_key(keys, keycode) or (_airplane != null and _airplane.on_key(keycode)):
        return true
    var action: String = DriveKeys.action_of(keys, keycode)
    if keys == DriveKeys.SOLO and Input.is_key_pressed(KEY_SHIFT) and DriveKeys.SOLO_SHIFTED.values().has(keycode):
        action = DriveKeys.SOLO_SHIFTED.find_key(keycode)
    if _lights.on_key(action, keycode, truck):
        return true
    match action:
        "reverse":
            _set_selector(-1)
        "neutral":
            _set_selector(0)
        "drive":
            _set_selector(1)
        "respawn":
            # Back to where the map starts the vehicle, undamaged — what a person means by
            # "reset". Recovery in place is its own key.
            _respawn()
        "ignition":
            if solver.engine_running():
                solver.stop_engine()
            else:
                _start_engine()
            print("DRIVE  engine %s" % ("running" if solver.engine_running() else "off"))
        "ties", "hook" when action == "ties" or Input.is_key_pressed(KEY_CTRL):
            # Upstream's `TIE_TOGGLE`, or with Ctrl its `ROPE_TOGGLE`, on group -1.
            var ties: bool = action == "ties"
            if world != null:
                world.call("toggle_ties" if ties else "toggle_ropes", solver, -1)
            else:
                solver.call("toggle_ties" if ties else "toggle_ropes", -1)
            print("DRIVE  %s toggled" % ("ties" if ties else "ropes"))
        "hook":
            # Upstream's `HOOK_TOGGLE` on group -1, or with Alt its `HOOK_UNLOCK` of the auto-locks.
            var mode: int = 1 if Input.is_key_pressed(KEY_ALT) else 2
            var group: int = -2 if mode == 1 else -1
            if world != null:
                world.toggle_hooks(solver, mode, group)
            else:
                solver.toggle_hooks(mode, group)
            print("DRIVE  hooks %s" % ("auto-locks let go" if mode == 1 else "toggled"))
        "recover":
            _recover()
        "wheel_diffs", "axle_diffs":
            print("DRIVE  %s" % AxleRows.toggle(solver, DriveKeys.action_of(keys, keycode) == "axle_diffs"))
        "antilock", "traction_control":
            var kind: String = "abs" if action == "antilock" else "tc"
            print("DRIVE  %s %s" % [kind.to_upper(), "on" if solver.toggle_drive_aid(kind) else "off"])
        "cruise_control":
            solver.toggle_cruise_control()
            print("DRIVE  cruise control %s" % ("on" if solver.cruise_control_on() else "off"))
        "transfer_case", "transfer_range":
            print("DRIVE  %s" % AxleRows.shift_transfer_case(solver, DriveKeys.action_of(keys, keycode) == "transfer_range"))
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
            _throttle, _brake, float(_state.get("steer", 0.0)), "on" if lights_on() else "off",
            float(solver_usec) / 1000.0, float(wait_usec) / 1000.0,
            float(_deform_usec) / 1000.0, float(_submit_usec) / 1000.0,
        ]
    )


func _read_controls(delta: float) -> void:
    if _airplane != null:
        return _airplane.read(solver, delta)
    var wants_throttle: bool = DriveKeys.held(keys, "throttle")
    if not is_nan(scripted_throttle):
        wants_throttle = scripted_throttle > 0.0
    var wants_brake: bool = DriveKeys.held(keys, "brake")
    _throttle = clampf(
        _throttle + (DriveCfg.THROTTLE_RATE if wants_throttle else -DriveCfg.THROTTLE_RATE) * delta,
        0.0,
        1.0
    )
    _brake = clampf(
        _brake + (DriveCfg.BRAKE_RATE if wants_brake else -DriveCfg.BRAKE_RATE) * delta, 0.0, 1.0
    )
    var steer: float = 0.0
    if DriveKeys.held(keys, "left"):
        steer += 1.0
    if DriveKeys.held(keys, "right"):
        steer -= 1.0
    solver.set_throttle(_throttle)
    solver.set_brake(_brake)
    solver.set_parking_brake(DriveKeys.held(keys, "parking") and not DriveKeys.cruise_modifier(keys))
    # Command keys, held: the vehicle's own rams move while their key is down.
    var command_keys: Array = keys.get("commands", []) as Array
    # Not while Ctrl is down: Ctrl and a digit is a user light.
    var ctrl: bool = Input.is_key_pressed(KEY_CTRL)
    for index: int in command_keys.size():
        solver.set_command_key(index + 1, 1.0 if Input.is_key_pressed(command_keys[index] as Key) and not ctrl else 0.0)
    if not is_nan(scripted_steer):
        steer = scripted_steer
    solver.set_steer_command(DriveCfg.steer_command(steer))
    DriveKeys.drive_cruise(solver, keys, delta)


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
    _start_engine()
    _snapshot()
    _apply_pose()
    print("DRIVE  recovered")


## Puts the rig back where it started, upright and at rest.
func _respawn() -> void:
    RigBuilder.place(solver, truck, spawn, spawn_heading, DriveCfg.SPAWN_HEIGHT_M)
    _lights.set_headlights(false)
    _lights.state.high_beams = false
    _start_engine()
    _snapshot()
    _apply_pose()
    print("DRIVE  respawned")


## The parts of the vehicle that are driven rather than posed: the lamps, the steering wheel and
## the instruments. Updated per frame from the state the controls left behind.
func _apply_cabin() -> void:
    _lights.apply(_built["lamps"] as Array[Node3D], truck, _seconds, _brake, DriveKeys.held(keys, "parking"),
            -1 if _selector < 0 else 1, _state)
    Cockpit.turn_wheel(_built, truck, float(_state.get("steer", 0.0)))
    Cockpit.update(
        _cockpit, float(_state.get("rpm", 0.0)), float(_state.get("road_speed", 0.0)), lights_on()
    )


## Starting the engine puts an automatic box in first with DRIVE selected, as upstream's does, so
## the selector this driver shows has to follow it. And the pedals start from rest: the throttle
## ramps down over a quarter of a second after its key is let go, and a truck respawned inside that
## quarter was put back at a standstill with its foot still down, and set off on its own.
func _start_engine() -> void:
    solver.start_engine()
    _selector = 1
    _throttle = 0.0
    _brake = 0.0
