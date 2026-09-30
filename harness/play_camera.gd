class_name PlayCamera
extends RefCounted
## Where the camera is during a session: behind the vehicle, in the driver's seat, or flying.
##
## Extracted from `PlayRig` when that file reached its size cap. It is a real responsibility
## rather than a slice taken to fit under a number: three ways of deciding where a camera should
## be, and one of them — the driver's seat — has a rule the other two do not, which is that the
## view is attached to the cab and takes every shake the cab takes.

## How fast the free camera flies, and what Shift multiplies it by.
const MOVE_SPEED: float = 8.0
const BOOST_MULTIPLIER: float = 4.0
const MOUSE_SENSITIVITY: float = 0.0025
const PITCH_LIMIT: float = 1.5

enum Mode { FREE, CHASE, CAB }

var mode: Mode = Mode.FREE

var _camera: Camera3D
var _yaw: float = 0.0
var _pitch: float = 0.0
## In the cab the mouse turns the driver's head inside the vehicle's own frame, so the two angles
## are kept apart from the free camera's.
var _look_yaw: float = 0.0
var _look_pitch: float = 0.0


func setup(camera: Camera3D) -> void:
    _camera = camera
    _yaw = camera.rotation.y
    _pitch = camera.rotation.x


## Puts the camera in a mode, and sets the lens the mode wants.
func set_mode(wanted: Mode) -> void:
    mode = wanted
    if wanted != Mode.CAB:
        return
    _look_yaw = 0.0
    _look_pitch = 0.0
    # The camera is physical, so the lens is a focal length rather than an angle.
    var lens: CameraAttributesPhysical = _camera.attributes as CameraAttributesPhysical
    if lens != null:
        lens.frustum_focal_length = CockpitCfg.FOCAL_MM


## Follows the vehicle, in whichever way the mode says. Does nothing in the free mode, where the
## camera is wherever the keys have left it.
func follow(drive: PlayDrive, delta: float) -> void:
    if drive == null:
        return
    match mode:
        Mode.CAB:
            _ride_in_cab(drive)
        Mode.CHASE:
            _chase(drive, delta)
        _:
            pass


## The mouse. In the cab it turns the head and is stopped where a neck stops; everywhere else it
## turns the camera itself.
func look(relative: Vector2) -> void:
    if mode == Mode.CAB:
        _look_yaw = clampf(
            _look_yaw - relative.x * MOUSE_SENSITIVITY,
            -deg_to_rad(CockpitCfg.LOOK_YAW_LIMIT_DEG),
            deg_to_rad(CockpitCfg.LOOK_YAW_LIMIT_DEG)
        )
        _look_pitch = clampf(
            _look_pitch - relative.y * MOUSE_SENSITIVITY,
            -deg_to_rad(CockpitCfg.LOOK_PITCH_LIMIT_DEG),
            deg_to_rad(CockpitCfg.LOOK_PITCH_LIMIT_DEG)
        )
        return
    _yaw -= relative.x * MOUSE_SENSITIVITY
    _pitch = clampf(_pitch - relative.y * MOUSE_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
    _camera.rotation = Vector3(_pitch, _yaw, 0.0)


## WASD and Q/E only: the arrow keys belong to the driver once a vehicle is loaded, and having
## them do two things at once is the sort of thing that makes a session report "the steering is
## broken".
func fly(delta: float) -> void:
    var direction: Vector3 = Vector3.ZERO
    if Input.is_key_pressed(KEY_D):
        direction.x += 1.0
    if Input.is_key_pressed(KEY_A):
        direction.x -= 1.0
    if Input.is_key_pressed(KEY_S):
        direction.z += 1.0
    if Input.is_key_pressed(KEY_W):
        direction.z -= 1.0
    if Input.is_key_pressed(KEY_E):
        direction.y += 1.0
    if Input.is_key_pressed(KEY_Q):
        direction.y -= 1.0
    if direction == Vector3.ZERO:
        return
    var speed: float = MOVE_SPEED
    if Input.is_key_pressed(KEY_SHIFT):
        speed *= BOOST_MULTIPLIER
    _camera.translate(direction.normalized() * speed * delta)


## --------------------------------------------------------------------------------


## Sits where the driver sits: at the rig's own cinecam, in the vehicle's frame, turning with it.
##
## No lag and no smoothing, unlike the chase camera. A driver's head is attached to the cab, so
## every shake the cab takes is a shake the view takes, and that is the point of the view.
func _ride_in_cab(drive: PlayDrive) -> void:
    var frame: Transform3D = drive.frame
    var eye: Vector3 = frame * drive.eye()
    var look_basis: Basis = frame.basis * Basis.from_euler(
        Vector3(_look_pitch, _look_yaw, 0.0)
    )
    _camera.transform = Transform3D(look_basis, eye)
    _yaw = _camera.rotation.y
    _pitch = _camera.rotation.x


## Rides behind the vehicle in its own frame, lagging so that a turn is visible as a turn.
## Godot's +Z points backwards, which is also where the actor frame's +Z points, so the offset is
## behind the vehicle without a sign flip.
func _chase(drive: PlayDrive, delta: float) -> void:
    var frame: Transform3D = drive.frame
    var wanted: Vector3 = frame * DriveCfg.CHASE_OFFSET
    var aim: Vector3 = frame * DriveCfg.CHASE_AIM
    var smoothing: float = clampf(DriveCfg.CHASE_SMOOTHING * delta * 60.0, 0.0, 1.0)
    var position: Vector3 = _camera.position.lerp(wanted, smoothing)
    if position.distance_to(aim) < 0.01:
        return
    _camera.look_at_from_position(position, aim, Vector3.UP)
    _yaw = _camera.rotation.y
    _pitch = _camera.rotation.x
