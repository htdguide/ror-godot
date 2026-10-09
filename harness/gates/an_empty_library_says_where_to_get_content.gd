extends GateBase
## A content list with nothing in it says where to get something, and every list ends with a
## button that opens the folder the content goes in.
##
## A production build opens with nothing and a person who has never seen Rigs of Rods' repository
## is looking at two empty lists. So an empty list names the hero truck and the two maps this
## project is developed on, each a link to its page; and every list, empty or not, ends with the
## one rule — unpacked folders, not zips — the folder's own path, and a button that opens it.
## Held by building the rows with an empty library and with the real one and reading the rows
## back: the links carry the stated pages, the folder named is the profile's, the last control is
## the button.


static func meta() -> Dictionary:
    return {
        "name": "an_empty_library_says_where_to_get_content",
        "proves": "an empty vehicle or map list links to the suggested content pages and names the folder; every list ends with an Open folder button for the profile's own folder",
        "builds_on": ["the_main_menu_hands_over_a_start"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "%d vehicle and %d map links with their URLs on an empty list; the folder note names the profile's folder; the last control of every list is the %s button" % [ContentBrowser.VEHICLE_SUGGESTIONS.size(), ContentBrowser.MAP_SUGGESTIONS.size(), ContentBrowser.OPEN_FOLDER],
        "why": (
            "a build that bundles nothing meets its first user with two empty lists, and a list"
            + " that says only 'no vehicles' has told them nothing they can act on."
        ),
        "budget_s": 10.0,
        "needs_gpu": false,
        "milestone": "M2",
    }


func run(_harness: Node) -> Dictionary:
    var problems: PackedStringArray = PackedStringArray()
    var empty: Array[Dictionary] = []
    for list: Array in [
        ["vehicles", ContentBrowser.VEHICLE_SUGGESTIONS, ContentBrowser.vehicles_folder()],
        ["maps", ContentBrowser.MAP_SUGGESTIONS, ContentBrowser.maps_folder()],
    ]:
        var what: String = list[0] as String
        var rows: VBoxContainer = VBoxContainer.new()
        if what == "vehicles":
            ContentBrowser.vehicles(rows, "", Callable(), empty)
        else:
            ContentBrowser.maps(rows, "", Callable(), empty)
        var links: Dictionary = {}
        var named_folder: bool = false
        for child: Node in rows.get_children():
            if child is LinkButton:
                links[(child as LinkButton).uri] = (child as LinkButton).text
            if child is Label and (child as Label).text.strip_edges() == (list[2] as String):
                named_folder = true
        for suggestion: Dictionary in list[1] as Array[Dictionary]:
            if not links.has(suggestion["url"]):
                problems.append("empty %s list has no link to %s" % [what, suggestion["url"]])
        if links.size() != (list[1] as Array).size():
            problems.append("empty %s list has %d links, %d suggested" % [what, links.size(), (list[1] as Array).size()])
        if not named_folder:
            problems.append("empty %s list does not name %s" % [what, list[2]])
        var last: Node = rows.get_child(rows.get_child_count() - 1)
        if not (last is Button) or (last as Button).text != ContentBrowser.OPEN_FOLDER:
            problems.append("empty %s list does not end with the %s button" % [what, ContentBrowser.OPEN_FOLDER])
        rows.free()
        # And the full list, whatever this checkout holds, ends the same way with no links.
        var full: VBoxContainer = VBoxContainer.new()
        if what == "vehicles":
            ContentBrowser.vehicles(full, "", Callable())
        else:
            ContentBrowser.maps(full, "", Callable())
        var last_full: Node = full.get_child(full.get_child_count() - 1)
        if not (last_full is Button) or (last_full as Button).text != ContentBrowser.OPEN_FOLDER:
            problems.append("the %s list does not end with the %s button" % [what, ContentBrowser.OPEN_FOLDER])
        full.free()
    if not problems.is_empty():
        return fail("; ".join(problems), problems.size())
    return ok("empty lists link %d vehicle and %d map pages and name the profile's folders; every list ends with %s" % [ContentBrowser.VEHICLE_SUGGESTIONS.size(), ContentBrowser.MAP_SUGGESTIONS.size(), ContentBrowser.OPEN_FOLDER], ContentBrowser.VEHICLE_SUGGESTIONS.size() + ContentBrowser.MAP_SUGGESTIONS.size())
