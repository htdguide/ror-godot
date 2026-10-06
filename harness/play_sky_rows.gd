class_name PlaySkyRows
extends RefCounted
## The sky's own rows in the settings panel: the clock, the exposure, and the weather.
##
## Split out of `PlayMenu` when that file went over the source cap, and it is a seam rather than a
## slice: every row here changes what is above the scene, and none of them touches the sky itself.
## A value moved goes to the session's weather state — the hour, with whatever has been moved by
## hand over it — so that it survives the next hour the clock is dragged to. See
## `PlayWeather.set_override`.


## Builds them. `on_hour` is called with a clock hour, `on_sky` with a weather key and a value.
static func build(
    rows: VBoxContainer, environment: Environment, hour: float,
    on_hour: Callable, on_sky: Callable
) -> void:
    MenuWidgets.heading(rows, "Sky")
    # The clock, which is the whole day rather than a preset: sun, moon, stars, haze and the
    # exposure that light was metered for. `Sky brightness` used to sit here and did nothing —
    # `ambient_light_energy` is ignored while the sky supplies all of the ambient.
    MenuWidgets.slider(
        rows, "Time of day", 0.0, 24.0, hour,
        func(value: float) -> void: on_hour.call(value),
        "%.1f h"
    )
    MenuWidgets.slider(
        rows, "Exposure", 0.1, 3.0, environment.tonemap_exposure,
        func(value: float) -> void: environment.tonemap_exposure = value
    )
    # The weather itself, which every sky this project draws now has: the marched cloud layer sits
    # over the stated gradient and over a captured sky alike, so there is no hour whose clouds a
    # session cannot move. Cover takes the sky over to the overcast capture as it thickens.
    var clouds: Dictionary = SkyClouds.settings(environment)
    if clouds.is_empty():
        MenuWidgets.note(rows, "This sky has no clouds to move.")
        return
    MenuWidgets.slider(
        rows, "Cloud cover", 0.0, 1.0, clouds["coverage"] as float,
        func(value: float) -> void: on_sky.call("cloud_coverage", value)
    )
    MenuWidgets.slider(
        rows, "Cloud density", 0.0, 3.0, clouds["density"] as float,
        func(value: float) -> void: on_sky.call("cloud_density", value)
    )
    MenuWidgets.slider(
        rows, "Wind", 0.0, 0.05, clouds["wind_speed"] as float,
        func(value: float) -> void: on_sky.call("cloud_wind_speed", value),
        "%.3f"
    )
