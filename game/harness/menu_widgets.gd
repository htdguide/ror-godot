class_name MenuWidgets
extends RefCounted
## The controls the settings panel is made of.
##
## One place that decides what a row looks like, so a panel with five sections in it stays a
## panel a person can read: the same label width, the same readout, the same spacing, whatever
## the setting is. Kept apart from the panel itself because the panel is about what the settings
## *are*, and this is about what a slider is.

const LABEL_WIDTH: int = 132
const CONTROL_WIDTH: int = 158
const READOUT_WIDTH: int = 52
const HEADING_TOP_MARGIN: int = 10


## A section heading, with air above it so sections read as sections.
static func heading(into: VBoxContainer, text: String) -> void:
    var label: Label = Label.new()
    label.text = text.to_upper()
    label.add_theme_font_size_override("font_size", 12)
    label.add_theme_color_override("font_color", Color(0.62, 0.74, 0.92))
    var margin: MarginContainer = MarginContainer.new()
    margin.add_theme_constant_override("margin_top", HEADING_TOP_MARGIN)
    margin.add_child(label)
    into.add_child(margin)


## A slider with its value beside it. `format` is a printf pattern for the readout, so metres and
## degrees can say what they are.
static func slider(
    into: VBoxContainer,
    text: String,
    low: float,
    high: float,
    value: float,
    on_change: Callable,
    format: String = "%.2f"
) -> HSlider:
    var row: HBoxContainer = _row(into, text)
    var control: HSlider = HSlider.new()
    control.min_value = low
    control.max_value = high
    control.step = (high - low) / 200.0
    control.value = clampf(value, low, high)
    control.custom_minimum_size = Vector2(CONTROL_WIDTH, 0)
    control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    var readout: Label = Label.new()
    readout.text = format % control.value
    readout.custom_minimum_size = Vector2(READOUT_WIDTH, 0)
    control.value_changed.connect(func(changed: float) -> void:
        readout.text = format % changed
        on_change.call(changed)
    )
    row.add_child(control)
    row.add_child(readout)
    return control


## A drop-down of named choices.
static func options(
    into: VBoxContainer, text: String, names: PackedStringArray, selected: int,
    on_change: Callable
) -> OptionButton:
    var row: HBoxContainer = _row(into, text)
    var control: OptionButton = OptionButton.new()
    control.custom_minimum_size = Vector2(CONTROL_WIDTH, 0)
    for index: int in names.size():
        control.add_item(names[index], index)
    control.selected = clampi(selected, 0, maxi(names.size() - 1, 0))
    control.item_selected.connect(func(index: int) -> void: on_change.call(index))
    row.add_child(control)
    return control


## A tick box.
static func check(
    into: VBoxContainer, text: String, value: bool, on_change: Callable
) -> CheckBox:
    var box: CheckBox = CheckBox.new()
    box.text = text
    box.button_pressed = value
    box.toggled.connect(func(pressed: bool) -> void: on_change.call(pressed))
    into.add_child(box)
    return box


## A row of buttons, side by side.
static func buttons(into: VBoxContainer, labels: PackedStringArray, on_press: Callable) -> void:
    var row: HBoxContainer = HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    for index: int in labels.size():
        var button: Button = Button.new()
        button.text = labels[index]
        button.custom_minimum_size = Vector2(110, 30)
        var pressed_index: int = index
        button.pressed.connect(func() -> void: on_press.call(pressed_index))
        row.add_child(button)
    var margin: MarginContainer = MarginContainer.new()
    margin.add_theme_constant_override("margin_top", HEADING_TOP_MARGIN)
    margin.add_child(row)
    into.add_child(margin)


## A line of text, for something that is read rather than changed.
static func note(into: VBoxContainer, text: String) -> Label:
    var label: Label = Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", 12)
    label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.78))
    into.add_child(label)
    return label


static func _row(into: VBoxContainer, text: String) -> HBoxContainer:
    var row: HBoxContainer = HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    var label: Label = Label.new()
    label.text = text
    label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
    label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(label)
    into.add_child(row)
    return row
