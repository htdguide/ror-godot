class_name ReviewPanel
extends RefCounted
## The strip across the bottom of a review window: which object this is, how many are left, and
## the two buttons that settle it.
##
## Split from `ReviewRig` so that the flow — which object, what the camera is doing, what gets
## written — is readable without the widget code in the way.

const HEIGHT_PX: int = 132
const FONT_PX: int = 18
const NAME_FONT_PX: int = 22
const BUTTON_W: int = 150
const BUTTON_H: int = 44
const PAD: int = 18
const PLATE: Color = Color(0.06, 0.07, 0.09, 0.92)
const HINT: String = "drag to turn it over, wheel to come closer, click a surface to mark it"

var name_label: Label = null
var progress_label: Label = null
var note_label: Label = null
var pass_button: Button = null
var fail_button: Button = null
var skip_button: Button = null
var paint_button: Button = null
var note_field: LineEdit = null
var marks_label: Label = null


## Builds the strip into `into` and returns itself, wired to nothing: the rig connects the
## buttons, because the rig is what knows what they mean.
func build(into: Node) -> ReviewPanel:
    var layer: CanvasLayer = CanvasLayer.new()
    layer.name = "ReviewPanel"
    var plate: ColorRect = ColorRect.new()
    plate.color = PLATE
    plate.anchor_left = 0.0
    plate.anchor_right = 1.0
    plate.anchor_top = 1.0
    plate.anchor_bottom = 1.0
    plate.offset_top = -HEIGHT_PX
    plate.mouse_filter = Control.MOUSE_FILTER_STOP
    layer.add_child(plate)

    var row: HBoxContainer = HBoxContainer.new()
    row.anchor_left = 0.0
    row.anchor_right = 1.0
    row.anchor_top = 1.0
    row.anchor_bottom = 1.0
    row.offset_top = -HEIGHT_PX
    row.offset_left = PAD
    row.offset_right = -PAD
    row.add_theme_constant_override("separation", PAD)
    row.alignment = BoxContainer.ALIGNMENT_BEGIN
    layer.add_child(row)

    var names: VBoxContainer = VBoxContainer.new()
    names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    names.alignment = BoxContainer.ALIGNMENT_CENTER
    name_label = _label("", NAME_FONT_PX)
    progress_label = _label("", FONT_PX)
    note_label = _label(HINT, FONT_PX)
    note_label.modulate = Color(0.75, 0.78, 0.82)
    names.add_child(name_label)
    names.add_child(progress_label)
    names.add_child(note_label)
    row.add_child(names)

    var saying: VBoxContainer = VBoxContainer.new()
    saying.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    saying.custom_minimum_size = Vector2(380, 0)
    saying.alignment = BoxContainer.ALIGNMENT_CENTER
    # **A typed reason, because the verdict alone did not say enough.** Thirteen of the objects
    # failed by eye were called clean by every measurement in the suite, and nothing recorded why
    # they were failed. One line here is the difference between a list of names and a fault.
    note_field = LineEdit.new()
    note_field.placeholder_text = "what is wrong with it?"
    note_field.add_theme_font_size_override("font_size", FONT_PX)
    note_field.custom_minimum_size = Vector2(380, BUTTON_H)
    marks_label = _label("click a surface to mark it, right-click to clear", FONT_PX)
    marks_label.modulate = Color(0.75, 0.78, 0.82)
    saying.add_child(note_field)
    saying.add_child(marks_label)
    row.add_child(saying)

    paint_button = _button("Paint backs  B")
    skip_button = _button("Skip  →")
    fail_button = _button("Fail  F")
    fail_button.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
    pass_button = _button("Pass  P")
    pass_button.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
    for button: Button in [paint_button, skip_button, fail_button, pass_button]:
        row.add_child(button)

    into.add_child(layer)
    return self


## What the strip says about the object on screen now.
func show_object(mesh_file: String, index: int, total: int, verdict: String) -> void:
    name_label.text = mesh_file
    progress_label.text = "%d of %d left to look at" % [index + 1, total]
    if verdict == "":
        note_label.text = HINT
        note_label.modulate = Color(0.75, 0.78, 0.82)
        return
    note_label.text = "already marked %s — pressing again overwrites it" % verdict
    note_label.modulate = (
        Color(0.55, 1.0, 0.6) if verdict == ObjectReview.PASS else Color(1.0, 0.55, 0.5)
    )


## How many surfaces are marked on the object on screen.
func show_marks(marked: int) -> void:
    if marked == 0:
        marks_label.text = "click a surface to mark it, right-click to clear"
        marks_label.modulate = Color(0.75, 0.78, 0.82)
        return
    marks_label.text = "%d surface%s marked" % [marked, "" if marked == 1 else "s"]
    marks_label.modulate = ReviewPick.MARKED


## What the strip says when there is nothing left to look at.
func show_done(passed: int, failed: int) -> void:
    name_label.text = "nothing left to look at"
    progress_label.text = "%d passed, %d failed, on record" % [passed, failed]
    note_label.text = "close the window; the verdicts are in harness/reference/object_review.json"
    note_label.modulate = Color(0.75, 0.78, 0.82)


func _label(text: String, size: int) -> Label:
    var label: Label = Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", size)
    return label


func _button(text: String) -> Button:
    var button: Button = Button.new()
    button.text = text
    button.custom_minimum_size = Vector2(BUTTON_W, BUTTON_H)
    button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    button.add_theme_font_size_override("font_size", FONT_PX)
    return button
