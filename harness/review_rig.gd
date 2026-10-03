class_name ReviewRig
extends Node
## A window that shows a map's objects one at a time and takes a person's verdict on each.
##
## **The gates have gone as far as a file can take them.** `object_photoset` settles whether a
## surface agrees with the normals its own file carries; `a_reversed_solid_is_caught` settles
## whether a solid is inside out; `an_object_is_not_a_hole_from_outside` photographs every object
## a map places and counts the back faces — and then stops, because three classes of content show
## a back from outside while being right and no measurement separates them from the fault. A road
## sign is one card. `store08.mesh` is two parallel facades. A warehouse has no roof.
##
## A person turning the object over answers that in a second. This is where they do it: one
## object at a time, the mouse turns it, two buttons settle it, and what they say is written to
## `harness/reference/object_review.json` and never asked again.
##
## **Passed objects do not come back.** The list each session offers is the map's objects minus
## everything already on record, so the work shrinks. `--again` offers the lot regardless, for
## when something has changed under them.

## The map whose objects are offered, unless one is named.
const DEFAULT_TERRAIN: String = "starling-port"
## How far back to stand, as a multiple of the object's own diagonal, and the limits on coming
## closer or going further.
const DISTANCE_SCALE: float = 1.6
const NEAR_SCALE: float = 0.35
const FAR_SCALE: float = 6.0
const ZOOM_STEP: float = 1.12
## How far the mouse turns the object, in radians per pixel, and how far up or down it may go.
const TURN_PER_PIXEL: float = 0.008
const MAX_PITCH: float = 1.45
## Where the camera starts: a three-quarter view from slightly above, which is how a person
## standing near a building sees it.
const START_YAW: float = 0.7
const START_PITCH: float = 0.25

var _camera: Camera3D
var _world: Node3D
var _panel: ReviewPanel
var _subjects: PackedStringArray = PackedStringArray()
var _terrain: RorTerrain = null
var _state: Dictionary = {}
var _at: int = 0
var _node: MeshInstance3D = null
var _centre: Vector3 = Vector3.ZERO
var _distance: float = 1.0
var _span: float = 1.0
var _yaw: float = START_YAW
var _pitch: float = START_PITCH
var _turning: bool = false
var _painted: bool = false


func setup(camera: Camera3D, world: Node3D) -> void:
    _camera = camera
    _world = world
    _panel = ReviewPanel.new().build(self)
    _panel.pass_button.pressed.connect(func() -> void: _settle(ObjectReview.PASS))
    _panel.fail_button.pressed.connect(func() -> void: _settle(ObjectReview.FAIL))
    _panel.skip_button.pressed.connect(func() -> void: _step(1))
    _panel.paint_button.pressed.connect(_toggle_paint)
    # The stage, not a map: one object alone against a plain ground, because the question is
    # about the object and a map behind it is something else to look at.
    var ground: MeshInstance3D = _world.get_node_or_null(^"Ground") as MeshInstance3D
    if ground != null:
        ground.visible = true

    var wanted: String = Harness.args.get_string("terrain-dir", DEFAULT_TERRAIN)
    var loaded: Dictionary = RorTerrainLibrary.load_named(wanted)
    if (loaded.get("error", "") as String) != "":
        printerr("REVIEW  %s" % loaded["error"])
        return
    _terrain = loaded["terrain"] as RorTerrain
    _state = RorObjects.state(_terrain)
    _subjects = _remaining(Harness.args.has_flag("again"))
    print("REVIEW  %s: %d objects to look at; P pass, F fail, arrows move, B paints backs"
        % [wanted, _subjects.size()])
    _show()


## Every distinct mesh the map places, most-placed first, minus whatever is already on record.
func _remaining(again: bool) -> PackedStringArray:
    var counts: Dictionary = {}
    for placement: Dictionary in RorObjects.placements(_terrain):
        var odef: Dictionary = RorObjects.definition(
            _terrain, placement["name"] as String, _state
        )
        if (odef.get("error", "") as String) != "":
            continue
        for file: String in odef["meshes"] as PackedStringArray:
            counts[file] = (counts.get(file, 0) as int) + 1
    var names: Array = counts.keys()
    names.sort_custom(func(a: String, b: String) -> bool:
        return (counts[a] as int) > (counts[b] as int)
    )
    var out: PackedStringArray = PackedStringArray()
    for name: String in names:
        if again or ObjectReview.verdict_of(name as String) == "":
            out.append(name as String)
    return out


## Puts the object at `_at` on the stage and frames it.
func _show() -> void:
    if _node != null:
        _world.remove_child(_node)
        _node.queue_free()
        _node = null
    if _subjects.is_empty():
        var tally: Dictionary = ObjectReview.tally()
        _panel.show_done(tally["pass"] as int, tally["fail"] as int)
        return
    _at = clampi(_at, 0, _subjects.size() - 1)
    var file: String = _subjects[_at]
    var mesh: ArrayMesh = RorObjects.mesh_of(_terrain, file, _state)
    if mesh == null:
        _panel.show_object("%s — will not read" % file, _at, _subjects.size(), "")
        return
    var shown: ArrayMesh = mesh
    if _painted:
        shown = mesh.duplicate() as ArrayMesh
        FacingPaint.apply(shown)
    _node = MeshInstance3D.new()
    _node.mesh = shown
    # The same -90 degree pitch every object is placed with, so it stands the way the map
    # stands it rather than on its side.
    _node.transform = RorObjects.transform_of(
        {"position": Vector3.ZERO, "rotation": Vector3.ZERO}, Vector3.ONE
    )
    _world.add_child(_node)
    var bounds: AABB = _node.transform * mesh.get_aabb()
    _centre = bounds.get_center()
    _span = maxf(bounds.size.length(), 0.5)
    _distance = _span * DISTANCE_SCALE
    _panel.show_object(file, _at, _subjects.size(), ObjectReview.verdict_of(file))
    _aim()


## Where the camera sits, from the yaw, pitch and distance the mouse has set.
func _aim() -> void:
    var direction: Vector3 = Vector3(
        cos(_pitch) * sin(_yaw), sin(_pitch), cos(_pitch) * cos(_yaw)
    )
    _camera.look_at_from_position(_centre + direction * _distance, _centre, Vector3.UP)


## Writes what a person said and moves on.
func _settle(verdict: String) -> void:
    if _subjects.is_empty():
        return
    var file: String = _subjects[_at]
    var error: String = ObjectReview.record(file, verdict)
    if error != "":
        printerr("REVIEW  %s" % error)
        return
    print("REVIEW  %s %s" % [file, verdict])
    # Taken off the list in this session too, so the count on screen is what is left rather than
    # what there was when the window opened.
    _subjects.remove_at(_at)
    if _at >= _subjects.size():
        _at = maxi(_subjects.size() - 1, 0)
    _show()


## Moves without settling anything.
func _step(by: int) -> void:
    if _subjects.is_empty():
        return
    _at = posmod(_at + by, _subjects.size())
    _show()


func _toggle_paint() -> void:
    _painted = not _painted
    _panel.paint_button.text = "Paint backs  B" if not _painted else "Paint off  B"
    _show()


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        var click: InputEventMouseButton = event as InputEventMouseButton
        if click.button_index == MOUSE_BUTTON_LEFT:
            _turning = click.pressed
        elif click.pressed and click.button_index == MOUSE_BUTTON_WHEEL_UP:
            _zoom(1.0 / ZOOM_STEP)
        elif click.pressed and click.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _zoom(ZOOM_STEP)
        return
    if event is InputEventMouseMotion and _turning:
        var moved: InputEventMouseMotion = event as InputEventMouseMotion
        _yaw -= moved.relative.x * TURN_PER_PIXEL
        _pitch = clampf(_pitch + moved.relative.y * TURN_PER_PIXEL, -MAX_PITCH, MAX_PITCH)
        _aim()
        return
    if event is not InputEventKey or not (event as InputEventKey).pressed:
        return
    match (event as InputEventKey).keycode:
        KEY_P:
            _settle(ObjectReview.PASS)
        KEY_F:
            _settle(ObjectReview.FAIL)
        KEY_RIGHT:
            _step(1)
        KEY_LEFT:
            _step(-1)
        KEY_B:
            _toggle_paint()
        KEY_R:
            _yaw = START_YAW
            _pitch = START_PITCH
            _distance = _span * DISTANCE_SCALE
            _aim()


func _zoom(by: float) -> void:
    _distance = clampf(_distance * by, _span * NEAR_SCALE, _span * FAR_SCALE)
    _aim()
