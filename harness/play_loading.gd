class_name PlayLoading
extends CanvasLayer
## The screen a session shows while a map is built: a picture, the map's name, and a bar that
## says what is being loaded.
##
## A terrain takes seconds to import, place, sweep and plant, and until this existed a person
## picking a map watched a frozen frame of the old one with no sign anything was happening. The
## screen covers the world while `PlayMap.populate` works through its stages and reports each
## one here; the stages yield a frame between them, which is what lets the bar move.
##
## The picture is `assets/ui/loading.png`, made by `tools/loading_shot.sh` from the hero vehicle
## on a road at dusk. It is a render of community content and so it is not committed; a build
## without it shows the gradient under it instead.

const IMAGE: String = "assets/ui/loading.png"
const LAYER: int = 3
const BAND_HEIGHT: int = 150
const INK: Color = Color(0.93, 0.93, 0.95)
const DIM_INK: Color = Color(0.70, 0.72, 0.78)
const BAR: Color = Color(0.98, 0.72, 0.30)

var _title: Label
var _stage: Label
var _bar: ProgressBar
var _root: Control


func _init() -> void:
    layer = LAYER
    _root = Control.new()
    _root.set_anchors_preset(Control.PRESET_FULL_RECT)
    _root.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_root)
    backdrop(_root)
    _band()
    _root.visible = false


## Shows the screen for a map, with an empty bar.
func open(map_title: String) -> void:
    _title.text = "Loading %s" % map_title
    _bar.value = 0.0
    _stage.text = ""
    _root.visible = true


## Says what is being loaded now, and how far along the whole load is.
func stage(label: String, fraction: float) -> void:
    _stage.text = label
    _bar.value = clampf(fraction, 0.0, 1.0)


func dismiss() -> void:
    _root.visible = false


func is_open() -> bool:
    return _root.visible


## The picture, or a gradient where there is none, and a fade into the band over it. Static so
## the main menu stands on the same picture.
static func backdrop(root: Control) -> void:
    var ground: ColorRect = ColorRect.new()
    ground.color = Color(0.03, 0.035, 0.05)
    ground.set_anchors_preset(Control.PRESET_FULL_RECT)
    root.add_child(ground)
    var path: String = SourceScan.repo_root().path_join(IMAGE)
    var picture: TextureRect = TextureRect.new()
    picture.set_anchors_preset(Control.PRESET_FULL_RECT)
    picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    picture.stretch_mode = TextureRect.STRETCH_SCALE
    var image: Image = Image.load_from_file(path) if FileAccess.file_exists(path) else null
    if image != null:
        picture.texture = ImageTexture.create_from_image(image)
        picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    else:
        var dusk: GradientTexture2D = GradientTexture2D.new()
        dusk.gradient = Gradient.new()
        dusk.gradient.set_color(0, Color(0.36, 0.22, 0.18))
        dusk.gradient.set_color(1, Color(0.05, 0.06, 0.10))
        dusk.fill = GradientTexture2D.FILL_RADIAL
        dusk.fill_from = Vector2(0.5, 0.85)
        dusk.fill_to = Vector2(0.5, 0.0)
        picture.texture = dusk
    root.add_child(picture)
    var fade: TextureRect = TextureRect.new()
    fade.set_anchors_preset(Control.PRESET_FULL_RECT)
    fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    fade.stretch_mode = TextureRect.STRETCH_SCALE
    var shade: GradientTexture2D = GradientTexture2D.new()
    shade.gradient = Gradient.new()
    shade.gradient.set_color(0, Color(0.0, 0.0, 0.0, 0.0))
    shade.gradient.set_color(1, Color(0.0, 0.0, 0.0, 0.85))
    shade.fill_from = Vector2(0.5, 0.45)
    shade.fill_to = Vector2(0.5, 1.0)
    fade.texture = shade
    root.add_child(fade)


## The band along the bottom: the map's name, the bar, and what the bar is doing.
func _band() -> void:
    var band: MarginContainer = MarginContainer.new()
    band.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    band.offset_top = -BAND_HEIGHT
    for side: String in ["left", "right"]:
        band.add_theme_constant_override("margin_%s" % side, 48)
    band.add_theme_constant_override("margin_bottom", 36)
    _root.add_child(band)
    var rows: VBoxContainer = VBoxContainer.new()
    rows.add_theme_constant_override("separation", 10)
    band.add_child(rows)
    _title = Label.new()
    _title.add_theme_font_size_override("font_size", 30)
    _title.add_theme_color_override("font_color", INK)
    rows.add_child(_title)
    _bar = ProgressBar.new()
    _bar.min_value = 0.0
    _bar.max_value = 1.0
    _bar.show_percentage = false
    _bar.custom_minimum_size = Vector2(0, 8)
    var fill: StyleBoxFlat = StyleBoxFlat.new()
    fill.bg_color = BAR
    fill.set_corner_radius_all(4)
    var trough: StyleBoxFlat = StyleBoxFlat.new()
    trough.bg_color = Color(1.0, 1.0, 1.0, 0.12)
    trough.set_corner_radius_all(4)
    _bar.add_theme_stylebox_override("fill", fill)
    _bar.add_theme_stylebox_override("background", trough)
    rows.add_child(_bar)
    _stage = Label.new()
    _stage.add_theme_font_size_override("font_size", 14)
    _stage.add_theme_color_override("font_color", DIM_INK)
    rows.add_child(_stage)
    var mark: Label = Label.new()
    mark.text = "ror-godot [%s]" % BuildProfile.label()
    mark.add_theme_font_size_override("font_size", 12)
    mark.add_theme_color_override("font_color", DIM_INK)
    mark.set_anchors_preset(Control.PRESET_TOP_LEFT)
    mark.position = Vector2(16, 12)
    _root.add_child(mark)
