extends GateBase
## The main menu's three choices reach the session together, and only after the third.
##
## Start a game is a vehicle, then a map, then the weather to open under, and the session gets
## all three at once or nothing: a game started with a map and no weather would open under
## whatever was on last. The choices are made here through the same handlers the buttons call,
## and the weather list is checked against the preset table — every hour of the day offered,
## no measurement preset among them.


static func meta() -> Dictionary:
    return {
        "name": "the_main_menu_hands_over_a_start",
        "proves": "the main menu hands the session a vehicle, a map and a weather together, only once the third is chosen, and offers every non-measurement weather preset",
        "builds_on": ["the_graphics_settings_round_trip_and_apply"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "0 starts before the third choice, 1 start after it carrying all three, the weather list equal to the presets less the instruments",
        "why": (
            "a start handed over piecemeal opens a map under last session's weather, and a menu"
            + " that lists an instrument preset opens a black world with working headlights."
        ),
        "budget_s": 10.0,
        "needs_gpu": false,
        "milestone": "M2",
    }


func run(_harness: Node) -> Dictionary:
    var starts: Array = []
    var quits: Array = []
    var menu: MainMenu = MainMenu.new()
    menu.setup(GraphicsSettings.new(), func(choice: Dictionary) -> void: starts.append(choice),
        func() -> void: quits.append(true), Callable())
    menu.open()
    menu.pick_vehicle("S10offroad")
    if not starts.is_empty():
        menu.free()
        return fail("a start was handed over after the vehicle alone", starts.size())
    menu.pick_map("lapaz")
    if not starts.is_empty():
        menu.free()
        return fail("a start was handed over after the map, before the weather", starts.size())
    menu.pick_weather("dawn_mist")
    var offered: PackedStringArray = MainMenu.weathers()
    var expected: PackedStringArray = PackedStringArray()
    for name: String in WeatherCfg.PRESETS.keys():
        if not bool((WeatherCfg.get_preset(name)).get("measurement", false)):
            expected.append(name)
    var still_open: bool = menu.is_open()
    menu.free()
    if starts.size() != 1:
        return fail("%d starts handed over after the third choice" % starts.size(), starts.size())
    var choice: Dictionary = starts[0] as Dictionary
    if choice.get("vehicle") != "S10offroad" or choice.get("map") != "lapaz" or choice.get("weather") != "dawn_mist":
        return fail("the start carried %s" % JSON.stringify(choice), 0)
    if still_open:
        return fail("the menu stayed open after handing over a start", 0)
    if offered != expected:
        return fail("the weather list is %s, the presets less instruments are %s" % [",".join(offered), ",".join(expected)], 0)
    if not quits.is_empty():
        return fail("quit was called by a start", quits.size())
    return ok("vehicle, map and weather handed over together after the third choice; %d weathers offered, no instrument among them" % offered.size(), offered.size())
