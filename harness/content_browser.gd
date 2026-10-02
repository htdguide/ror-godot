class_name ContentBrowser
extends RefCounted
## The lists of maps and vehicles a session can switch to, built from what is on the disk.
##
## **Grouped by pack, with variants under it.** That is the shape the content actually has and the
## shape that stops the list being unreadable: the Chevy pack is four variations of one truck,
## Starling Island is five vehicles and four maps in one download, and upstream's own shipped map
## is three `.terrn2` over one set of files. A flat alphabetical list puts `S10drag` next to
## `S10offroad` by luck and `starling-beach` nowhere near `starling-port`, and a person looking
## for "the Chevy" has to know which four of eighteen names are the Chevy.
##
## This is how a game with variation-heavy content does it — pick the thing, then pick the
## version of the thing — and it is the only level of nesting worth having here. A third level
## would need categories somebody has to maintain by hand, and nothing in a Rigs of Rods file
## says which category it belongs to.
##
## **Every row says what it is in the content's own words.** A vehicle's title and author come
## from its file, a map's title and size from its `.terrn2` and `.otc`. Nothing here is a label
## this project wrote about somebody else's content, so a pack dropped in five minutes ago
## describes itself correctly without anybody editing a list.

## The row for whatever is loaded right now is marked rather than hidden, so a person can see
## where they are without hunting.
const CURRENT_MARK: String = "●  "
const ABSENT_MARK: String = "    "
const PACK_COLOUR: Color = Color(0.62, 0.76, 1.0)
const DETAIL_COLOUR: Color = Color(0.68, 0.70, 0.74)
const BROKEN_COLOUR: Color = Color(1.0, 0.55, 0.5)


## The vehicle list. `on_pick` is called with a vehicle's name.
static func vehicles(into: VBoxContainer, current: String, on_pick: Callable) -> void:
    var packs: Dictionary = _by_pack(RorVehicleLibrary.summaries())
    if packs.is_empty():
        MenuWidgets.note(into, "No vehicles. Unpack one into assets/mods/ and reopen this.")
        return
    for pack: String in packs.keys():
        MenuWidgets.heading(into, pack)
        for item: Dictionary in packs[pack] as Array[Dictionary]:
            var detail: String = item["kind"] as String
            if (item["author"] as String) != "":
                detail += "  ·  %s" % item["author"]
            _row(
                into, item["title"] as String, detail, item["error"] as String,
                (item["name"] as String) == current,
                on_pick, item["name"] as String
            )


## The map list. `on_pick` is called with a terrain's name.
static func maps(into: VBoxContainer, current: String, on_pick: Callable) -> void:
    var packs: Dictionary = _by_pack(RorTerrainLibrary.summaries())
    if packs.is_empty():
        MenuWidgets.note(into, "No maps. Unpack one into assets/terrains/ and reopen this.")
        return
    for pack: String in packs.keys():
        MenuWidgets.heading(into, pack)
        for item: Dictionary in packs[pack] as Array[Dictionary]:
            var detail: String = ""
            if (item["error"] as String) == "":
                detail = "%.0f m across" % (item["size_m"] as float)
            _row(
                into, item["title"] as String, detail, item["error"] as String,
                (item["name"] as String) == current,
                on_pick, item["name"] as String
            )


## One pickable row: a button carrying the title, with its details under it.
static func _row(
    into: VBoxContainer, title: String, detail: String, error: String, is_current: bool,
    on_pick: Callable, name: String
) -> void:
    var button: Button = Button.new()
    button.text = (CURRENT_MARK if is_current else ABSENT_MARK) + title
    button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # Something that cannot load is shown and disabled rather than left out: "it is not in the
    # list" and "it is broken" are different problems, and only one of them is the library's.
    # The terrain library has always reported it this way and the browser keeps that promise.
    button.disabled = error != ""
    if is_current:
        button.add_theme_color_override("font_color", PACK_COLOUR)
    if not button.disabled and on_pick.is_valid():
        button.pressed.connect(func() -> void: on_pick.call(name))
    into.add_child(button)

    var text: String = error if error != "" else detail
    if text == "":
        return
    var note: Label = MenuWidgets.note(into, "        " + text)
    note.add_theme_color_override(
        "font_color", BROKEN_COLOUR if error != "" else DETAIL_COLOUR
    )


## Summaries grouped by the folder they came from, packs in name order and items in theirs.
##
## The folder is the pack: nothing in a Rigs of Rods file names the set it belongs to, so the
## directory somebody unpacked is the only grouping the content itself offers.
static func _by_pack(summaries: Array[Dictionary]) -> Dictionary:
    var out: Dictionary = {}
    for summary: Dictionary in summaries:
        var pack: String = (summary["directory"] as String).get_file()
        if not out.has(pack):
            out[pack] = ([] as Array[Dictionary])
        (out[pack] as Array[Dictionary]).append(summary)
    var ordered: Dictionary = {}
    var names: PackedStringArray = PackedStringArray(out.keys())
    names.sort()
    for pack: String in names:
        var items: Array[Dictionary] = out[pack] as Array[Dictionary]
        items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
            return (a["title"] as String).naturalnocasecmp_to(b["title"] as String) < 0
        )
        ordered[pack] = items
    return ordered
