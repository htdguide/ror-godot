class_name PlaySkyRows
extends RefCounted
## The sky's own rows in the settings panel that are not a weather's numbers: the clock, and the
## tonemap exposure.
##
## Split out of `PlayMenu` when that file went over the source cap. The weather's own numbers —
## the clouds, the sun, the sky's colours — are `PlayWeatherRows`, built from one table so that
## every key a preset states is a row and every row is refreshed when a preset is chosen.


## Builds them. `on_hour` is called with a clock hour.
static func build(
    rows: VBoxContainer, environment: Environment, hour: float, on_hour: Callable
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
