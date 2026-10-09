class_name MainMenu
extends CanvasLayer
## The menu a person opens the game to: start a game, set the graphics, quit.
##
## Starting a game is three choices in a row — a vehicle, a map, the weather to open it under —
## each a page of the same panel, and the last hands all three to the session at once. The
## library lists are `ContentBrowser`'s, the same ones the in-game panel shows; the weather list
## is every preset a window may put up. The page under the wallpaper is `PlayLoading`'s backdrop,
## so the menu and the loading screen are one picture.

const LAYER: int = 4
const PANEL_WIDTH: int = 460
const PANEL_HEIGHT: int = 560

## Called with {"vehicle", "map", "weather"} when the third choice is made.
var on_start: Callable
var on_quit: Callable
## The choices so far, so a gate can see the flow and a page can show them.
var chosen: Dictionary = {}

var _root: Control
var _pages: Control
var _graphics: GraphicsSettings
var _on_graphics: Callable


func setup(graphics: GraphicsSettings, start: Callable, quit: Callable, on_graphics: Callable) -> void:
    _graphics = graphics
    on_start = start
    on_quit = quit
    _on_graphics = on_graphics
    layer = LAYER
    _root = Control.new()
    _root.set_anchors_preset(Control.PRESET_FULL_RECT)
    _root.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(_root)
    PlayLoading.backdrop(_root)
    var centre: CenterContainer = CenterContainer.new()
    centre.set_anchors_preset(Control.PRESET_FULL_RECT)
    _root.add_child(centre)
    _pages = PanelContainer.new()
    _pages.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
    centre.add_child(_pages)
    show_home()


func open() -> void:
    _root.visible = true
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    show_home()


func close() -> void:
    _root.visible = false


func is_open() -> bool:
    return _root != null and _root.visible


## --- Pages ------------------------------------------------------------------------------------


func show_home() -> void:
    chosen = {}
    var rows: VBoxContainer = _page("ror-godot", "An alternative Rigs of Rods client")
    _button(rows, "Start a game", show_vehicles)
    _button(rows, "Graphics", show_graphics)
    _button(rows, "Quit", func() -> void:
        if on_quit.is_valid():
            on_quit.call()
    )
    MenuWidgets.note(rows, "%s build" % BuildProfile.label())


func show_vehicles() -> void:
    var rows: VBoxContainer = _page("Pick a vehicle", "1 of 3")
    ContentBrowser.vehicles(rows, chosen.get("vehicle", "") as String, pick_vehicle)
    _button(rows, "Back", show_home)


func show_maps() -> void:
    var rows: VBoxContainer = _page("Pick a map", "2 of 3 — driving %s" % chosen.get("vehicle", ""))
    ContentBrowser.maps(rows, chosen.get("map", "") as String, pick_map)
    _button(rows, "Back", show_vehicles)


func show_weathers() -> void:
    var rows: VBoxContainer = _page("Pick the weather", "3 of 3 — %s on %s" % [chosen.get("vehicle", ""), chosen.get("map", "")])
    for name: String in weathers():
        var picked: String = name
        _button(rows, name.replace("_", " ").capitalize(), func() -> void: pick_weather(picked))
    _button(rows, "Back", show_maps)


func show_graphics() -> void:
    var rows: VBoxContainer = _page("Graphics", "Saved as you change them")
    _graphics.build_rows(rows, _on_graphics)
    _button(rows, "Back", show_home)


## --- The choices, as the buttons make them ---------------------------------------------------


func pick_vehicle(name: String) -> void:
    chosen["vehicle"] = name
    show_maps()


func pick_map(name: String) -> void:
    chosen["map"] = name
    show_weathers()


func pick_weather(name: String) -> void:
    chosen["weather"] = name
    var start: Dictionary = chosen.duplicate()
    close()
    if on_start.is_valid():
        on_start.call(start)


## Every weather a window may open on: the presets that are hours of the day, not instruments.
static func weathers() -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    for name: String in WeatherCfg.PRESETS.keys():
        if not bool((WeatherCfg.get_preset(name)).get("measurement", false)):
            out.append(name)
    return out


## --- Widgets ----------------------------------------------------------------------------------


func _page(title: String, subtitle: String) -> VBoxContainer:
    for child: Node in _pages.get_children():
        _pages.remove_child(child)
        child.queue_free()
    var margin: MarginContainer = MarginContainer.new()
    for side: String in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_%s" % side, 20)
    _pages.add_child(margin)
    var scroll: ScrollContainer = ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    margin.add_child(scroll)
    var rows: VBoxContainer = VBoxContainer.new()
    rows.add_theme_constant_override("separation", 8)
    rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(rows)
    var heading: Label = Label.new()
    heading.text = title
    heading.add_theme_font_size_override("font_size", 28)
    rows.add_child(heading)
    MenuWidgets.note(rows, subtitle)
    return rows


func _button(into: VBoxContainer, text: String, pressed: Callable) -> void:
    var button: Button = Button.new()
    button.text = text
    button.custom_minimum_size = Vector2(0, 36)
    button.pressed.connect(pressed)
    into.add_child(button)
