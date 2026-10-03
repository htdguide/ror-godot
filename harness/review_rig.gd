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
## everything already on record, so the work shrinks. `--again` offers the lot regardless, and
## `--failed` offers only what is already on record as failed, which is how you go back over a
## list of faults.
##
## **What is written down is a verdict, a sentence and a set of surfaces.** The first round
## recorded verdicts alone, and thirteen objects failed by eye came back clean from every
## measurement in the suite with nothing to say why. So there is a box to type in, and clicking a
## surface marks it: hovering lights it, a click pins it, and what goes in the file is which
## submesh, how many triangles, how big it is and which way it looks.

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
## How far the mouse may move between press and release and still be a click rather than a drag.
const CLICK_SLOP: float = 4.0

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
var _pick: ReviewPick = ReviewPick.new()
var _hover: MeshInstance3D = null
var _marks: MeshInstance3D = null
## Which surfaces are pinned on the object on screen, as indices into the pick's own list.
var _marked: PackedInt32Array = PackedInt32Array()
## Where the mouse went down and how far it has moved since, so that turning the object over is
## not also marking whatever was under the cursor when the drag started.
var _pressed_at: Vector2 = Vector2.ZERO
var _dragged: float = 0.0


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
    print("REVIEW  %s: %d objects to look at; P pass, F fail, arrows move, B paints backs,"
        % [wanted, _subjects.size()] + " click a surface to mark it")
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
    # `--object <file>` is one mesh and nothing else, for settling an argument about that mesh.
    var named: String = Harness.args.get_string("object", "")
    if named != "":
        return PackedStringArray([named] if counts.has(named) else [])
    # `--failed` is the round after a round: only what is already on record as wrong, so that a
    # list of faults can be gone back over with the reason box and the surface marks.
    var only_failed: bool = Harness.args.has_flag("failed")
    var out: PackedStringArray = PackedStringArray()
    for name: String in names:
        var verdict: String = ObjectReview.verdict_of(name as String)
        if only_failed:
            if verdict == ObjectReview.FAIL:
                out.append(name as String)
            continue
        if again or verdict == "":
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
    _hover = _overlay_node("Hover")
    _marks = _overlay_node("Marks")
    _marked = PackedInt32Array()
    var read: Dictionary = (_state["reader"] as RefCounted).read_file(
        RorContentPath.find(file, _terrain.directory)
    )
    _pick.study(read["submeshes"] as Array if (read.get("error", "") as String) == "" else [])
    var bounds: AABB = _node.transform * mesh.get_aabb()
    _centre = bounds.get_center()
    _span = maxf(bounds.size.length(), 0.5)
    _distance = _span * DISTANCE_SCALE
    # **The box starts empty every time.** Loading the previous note back into it looked helpful
    # and was a trap: a sign carrying "this side is transparent and broken" from an earlier round
    # was passed on a second look, and the stale complaint went into the record attached to the
    # new verdict. What was said before is shown, not re-submitted.
    _panel.note_field.text = ""
    _panel.show_marks(0)
    var known: Dictionary = ObjectReview.record_of(file)
    _panel.show_object(
        file, _at, _subjects.size(), known.get("verdict", "") as String,
        known.get("note", "") as String
    )
    _aim()


## A child of the object that draws a highlight over it, in the object's own frame.
func _overlay_node(name: String) -> MeshInstance3D:
    var node: MeshInstance3D = MeshInstance3D.new()
    node.name = name
    _node.add_child(node)
    return node


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
    var marks: Array = []
    for index: int in _marked:
        marks.append(_pick.describe(index))
    var error: String = ObjectReview.record(
        file, verdict, _panel.note_field.text.strip_edges(), marks
    )
    if error != "":
        printerr("REVIEW  %s" % error)
        return
    print("REVIEW  %s %s%s%s" % [
        file, verdict,
        "" if _panel.note_field.text.strip_edges().is_empty()
            else " — " + _panel.note_field.text.strip_edges(),
        "" if marks.is_empty() else " (%d surface(s) marked)" % marks.size(),
    ])
    _panel.note_field.text = ""
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
    # Nothing on the stage, nothing to pick. The list empties as verdicts are given, and the
    # mouse carries on moving over the empty stage afterwards.
    if _node == null:
        return
    if event is InputEventMouseButton:
        var click: InputEventMouseButton = event as InputEventMouseButton
        if click.button_index == MOUSE_BUTTON_LEFT:
            _turning = click.pressed
            if click.pressed:
                _pressed_at = click.position
                _dragged = 0.0
            # A click is a press and a release with the object still where it was. Anything else
            # was a drag to turn it over, and turning it over must not mark whatever happened to
            # be under the cursor when the drag began.
            elif _dragged < CLICK_SLOP:
                _mark(_pick.under(_node.transform, _camera, click.position))
        elif click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
            _marked = PackedInt32Array()
            _marks.mesh = null
            _panel.show_marks(0)
        elif click.pressed and click.button_index == MOUSE_BUTTON_WHEEL_UP:
            _zoom(1.0 / ZOOM_STEP)
        elif click.pressed and click.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _zoom(ZOOM_STEP)
        return
    if event is InputEventMouseMotion:
        var moved: InputEventMouseMotion = event as InputEventMouseMotion
        if not _turning:
            _light(_pick.under(_node.transform, _camera, moved.position))
            return
        _dragged += moved.relative.length()
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


## Lights the surface under the cursor, so that what a click would mark is never a surprise.
func _light(index: int) -> void:
    if _hover == null:
        return
    _hover.mesh = (
        null if index < 0 or _marked.has(index) else _pick.overlay(index, ReviewPick.HOVER)
    )


## Pins or unpins the surface under the cursor.
func _mark(index: int) -> void:
    if index < 0 or _marks == null:
        return
    if _marked.has(index):
        _marked.remove_at(_marked.find(index))
    else:
        _marked.append(index)
    # One mesh holding every pinned surface, rebuilt rather than added to: a handful of surfaces
    # on one object, and a rebuild cannot drift out of step with the list.
    var all: ArrayMesh = null
    for pinned: int in _marked:
        var piece: ArrayMesh = _pick.overlay(pinned, ReviewPick.MARKED)
        if piece == null:
            continue
        if all == null:
            all = piece
            continue
        all.add_surface_from_arrays(
            Mesh.PRIMITIVE_TRIANGLES, piece.surface_get_arrays(0)
        )
        all.surface_set_material(all.get_surface_count() - 1, piece.surface_get_material(0))
    _marks.mesh = all
    _hover.mesh = null
    _panel.show_marks(_marked.size())


func _zoom(by: float) -> void:
    _distance = clampf(_distance * by, _span * NEAR_SCALE, _span * FAR_SCALE)
    _aim()
