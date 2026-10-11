class_name DiffPanel
extends Control
## The differentials of the vehicle being driven, drawn as a plan of its axles: each axle a row with
## its two wheels, the kind of differential between them on a pill in the middle, and the one
## joining two axles on the shaft between their rows. A wheel fills with the torque it is getting,
## so a locked axle pulling one wheel back is something you can see.
##
## The V and J keys switch the kinds (`AxleRows.toggle`); a pill that has just changed flashes, so
## a key press is answered on screen as well as in the terminal. It follows the HUD: F1 hides both.

const MARGIN_PX: float = 16.0
const PAD_PX: float = 16.0
const WIDTH_PX: float = 244.0
const HEADER_PX: float = 30.0
const ROW_PX: float = 52.0
const SHAFT_PX: float = 40.0
const FOOTER_PX: float = 34.0
const WHEEL: Vector2 = Vector2(16.0, 42.0)
const FLASH_S: float = 0.7

const INK: Color = Color(0.11, 0.12, 0.14)
const SOFT_INK: Color = Color(0.11, 0.12, 0.14, 0.5)
const ACCENT: Color = Color(0.16, 0.45, 0.96)
const NAMES: Dictionary = {"s": "SPLIT", "o": "OPEN", "v": "VISCOUS", "l": "LOCKED"}

var _source: Callable
var _hud: CanvasItem
var _font: SystemFont
var _bold: SystemFont
var _model: Dictionary = {}
var _flash: Dictionary = {}
var _torque_scale: float = 1.0


## Puts a panel beside `hud`, reading from `source`: a Callable returning the solver of the vehicle
## being driven, or null when there is none to show.
static func attach(hud: CanvasItem, source: Callable) -> DiffPanel:
    var panel: DiffPanel = DiffPanel.new()
    panel.name = "DiffPanel"
    panel._source = source
    panel._hud = hud
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hud.get_parent().add_child(panel)
    return panel


## What the panel shows for `solver`: {axles: [{type, wheels}], shafts: [{type, axles}]}.
static func model(solver: RefCounted) -> Dictionary:
    var axles: Array[Dictionary] = []
    for i: int in solver.wheel_differential_count():
        axles.append({"type": solver.wheel_differential_type(i), "wheels": solver.wheel_differential_wheels(i)})
    var shafts: Array[Dictionary] = []
    for i: int in solver.axle_differential_count():
        shafts.append({"type": solver.axle_differential_type(i), "axles": solver.axle_differential_axles(i)})
    return {"axles": axles, "shafts": shafts}


func _ready() -> void:
    _font = _system_font(500)
    _bold = _system_font(650)


func _process(delta: float) -> void:
    var solver: RefCounted = _source.call() as RefCounted if _source.is_valid() else null
    var shown: bool = solver != null and _hud.visible
    if shown:
        var next: Dictionary = model(solver)
        shown = not (next["axles"] as Array).is_empty()
        _note_changes(next)
        _model = next
        _model["torque"] = _torques(solver, next)
    visible = shown
    for key: String in _flash.keys():
        _flash[key] = maxf(0.0, (_flash[key] as float) - delta)
    if shown:
        var rows: int = (_model["axles"] as Array).size()
        size = Vector2(WIDTH_PX, HEADER_PX + PAD_PX * 2.0 + rows * ROW_PX + (rows - 1) * SHAFT_PX + FOOTER_PX)
        position = Vector2(get_viewport_rect().size.x - size.x - MARGIN_PX, MARGIN_PX)
        queue_redraw()


func _draw() -> void:
    if not _model.has("torque"):
        return
    var card: StyleBoxFlat = StyleBoxFlat.new()
    card.bg_color = Color(1.0, 1.0, 1.0, 0.74)
    card.set_corner_radius_all(14)
    card.set_border_width_all(1)
    card.border_color = Color(1.0, 1.0, 1.0, 0.9)
    card.shadow_color = Color(0.0, 0.0, 0.0, 0.14)
    card.shadow_size = 14
    card.shadow_offset = Vector2(0.0, 3.0)
    card.anti_aliasing = true
    draw_style_box(card, Rect2(Vector2.ZERO, size))

    draw_string(_bold, Vector2(PAD_PX, PAD_PX + 12.0), "DIFFERENTIALS", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, SOFT_INK)
    var axles: Array = _model["axles"] as Array
    var top: float = PAD_PX + HEADER_PX
    var centres: Array[float] = []
    for i: int in axles.size():
        centres.append(top + i * (ROW_PX + SHAFT_PX) + ROW_PX * 0.5)
    var mid: float = size.x * 0.5
    for shaft: Dictionary in _model["shafts"] as Array:
        var joined: Vector2i = shaft["axles"] as Vector2i
        if joined.x < 0 or joined.y >= centres.size() or joined.x >= centres.size():
            continue
        var a: float = centres[mini(joined.x, joined.y)]
        var b: float = centres[maxi(joined.x, joined.y)]
        draw_line(Vector2(mid, a), Vector2(mid, b), Color(INK, 0.28), 2.0, true)
        _pill(Vector2(mid, (a + b) * 0.5), shaft["type"] as String, "shaft%d%d" % [joined.x, joined.y])
    var torques: Array = _model["torque"] as Array
    for i: int in axles.size():
        var y: float = centres[i]
        var left: Vector2 = Vector2(PAD_PX + 6.0, y - WHEEL.y * 0.5)
        var right: Vector2 = Vector2(size.x - PAD_PX - 6.0 - WHEEL.x, y - WHEEL.y * 0.5)
        draw_line(Vector2(left.x + WHEEL.x, y), Vector2(right.x, y), Color(INK, 0.28), 2.0, true)
        _wheel(left, (torques[i] as Vector2).x)
        _wheel(right, (torques[i] as Vector2).y)
        _pill(Vector2(mid, y), axles[i]["type"] as String, "axle%d" % i)

    var y_keys: float = size.y - PAD_PX - 4.0
    var x: float = _key(Vector2(PAD_PX, y_keys), "V", "axles")
    _key(Vector2(x + 14.0, y_keys), "J", "between axles")


## A wheel, filled from the bottom by the share of the largest torque lately seen that it carries.
func _wheel(at: Vector2, torque: float) -> void:
    var body: StyleBoxFlat = StyleBoxFlat.new()
    body.bg_color = Color(INK, 0.13)
    body.set_corner_radius_all(4)
    body.anti_aliasing = true
    draw_style_box(body, Rect2(at, WHEEL))
    var share: float = clampf(absf(torque) / _torque_scale, 0.0, 1.0)
    if share > 0.01:
        var fill: StyleBoxFlat = StyleBoxFlat.new()
        fill.bg_color = Color(ACCENT, 0.9) if torque >= 0.0 else Color(0.93, 0.36, 0.22, 0.9)
        fill.set_corner_radius_all(4)
        fill.anti_aliasing = true
        var h: float = maxf(WHEEL.y * share, 8.0)
        draw_style_box(fill, Rect2(Vector2(at.x, at.y + WHEEL.y - h), Vector2(WHEEL.x, h)))


## A differential's kind on a pill centred at `centre`; it flashes the accent while `key` is fresh.
func _pill(centre: Vector2, type: String, key: String) -> void:
    var text: String = NAMES.get(type, "?") as String
    var width: float = _bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 24.0
    var box: StyleBoxFlat = StyleBoxFlat.new()
    var flash: float = (_flash.get(key, 0.0) as float) / FLASH_S
    var base: Color = INK if type == "l" else Color(1.0, 1.0, 1.0, 0.95)
    box.bg_color = base.lerp(ACCENT, flash)
    box.set_corner_radius_all(11)
    box.set_border_width_all(0 if type == "l" else 1)
    box.border_color = Color(INK, 0.18)
    box.anti_aliasing = true
    draw_style_box(box, Rect2(centre - Vector2(width * 0.5, 12.0), Vector2(width, 24.0)))
    var ink: Color = Color.WHITE if type == "l" or flash > 0.5 else INK
    draw_string(_bold, centre + Vector2(-width * 0.5, 4.0), text, HORIZONTAL_ALIGNMENT_CENTER, width, 12, ink)


## A key cap and what it does; returns where the next one can start.
func _key(at: Vector2, cap: String, label: String) -> float:
    var cap_box: StyleBoxFlat = StyleBoxFlat.new()
    cap_box.bg_color = Color(1.0, 1.0, 1.0, 0.9)
    cap_box.set_corner_radius_all(5)
    cap_box.set_border_width_all(1)
    cap_box.border_width_bottom = 2
    cap_box.border_color = Color(INK, 0.22)
    cap_box.anti_aliasing = true
    draw_style_box(cap_box, Rect2(at + Vector2(0.0, -15.0), Vector2(20.0, 20.0)))
    draw_string(_bold, at + Vector2(0.0, -1.0), cap, HORIZONTAL_ALIGNMENT_CENTER, 20.0, 11, INK)
    draw_string(_font, at + Vector2(26.0, -1.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, SOFT_INK)
    return at.x + 26.0 + _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x


## Each axle's two wheel torques, and the scale they are drawn against: the largest lately seen,
## easing down so the bars stay readable both flat out and creeping.
func _torques(solver: RefCounted, next: Dictionary) -> Array[Vector2]:
    var out: Array[Vector2] = []
    var largest: float = 0.0
    for axle: Dictionary in next["axles"] as Array:
        var wheels: Vector2i = axle["wheels"] as Vector2i
        var pair: Vector2 = Vector2(solver.get_wheel_torque(wheels.x), solver.get_wheel_torque(wheels.y))
        largest = maxf(largest, maxf(absf(pair.x), absf(pair.y)))
        out.append(pair)
    _torque_scale = maxf(maxf(largest, _torque_scale * 0.995), 50.0)
    return out


## A switch key flashes its pills even when there is nothing to switch to: the hero's lock between
## axles has one kind, and a key that answers with nothing reads as a key that did not work.
func _input(event: InputEvent) -> void:
    var key: InputEventKey = event as InputEventKey
    if key == null or not key.pressed or key.echo or not visible or _model.is_empty():
        return
    match DriveKeys.action_of(DriveKeys.SOLO, key.keycode):
        "wheel_diffs":
            for i: int in (_model["axles"] as Array).size():
                _flash["axle%d" % i] = FLASH_S
        "axle_diffs":
            for shaft: Dictionary in _model["shafts"] as Array:
                var joined: Vector2i = shaft["axles"] as Vector2i
                _flash["shaft%d%d" % [joined.x, joined.y]] = FLASH_S


func _note_changes(next: Dictionary) -> void:
    if _model.is_empty():
        return
    var before: Array = _model["axles"] as Array
    var after: Array = next["axles"] as Array
    for i: int in mini(before.size(), after.size()):
        if before[i]["type"] != after[i]["type"]:
            _flash["axle%d" % i] = FLASH_S
    var shafts_before: Array = _model["shafts"] as Array
    var shafts_after: Array = next["shafts"] as Array
    for i: int in mini(shafts_before.size(), shafts_after.size()):
        var joined: Vector2i = shafts_after[i]["axles"] as Vector2i
        if shafts_before[i]["type"] != shafts_after[i]["type"]:
            _flash["shaft%d%d" % [joined.x, joined.y]] = FLASH_S


static func _system_font(weight: int) -> SystemFont:
    var font: SystemFont = SystemFont.new()
    font.font_names = PackedStringArray(["SF Pro Text", "Helvetica Neue", "Segoe UI", "Inter", "Arial"])
    font.font_weight = weight
    font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
    return font
