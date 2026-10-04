class_name PlayDistanceRows
extends RefCounted
## The settings panel's distance rows: how far a session can see, and what closes the distance.
##
## Split out of `PlayMenu` when the day-of-the-clock slider took that file over its source cap.
## It is a clean seam rather than a convenience: these rows touch the camera's far plane, the
## environment's haze and the vegetation's own range, and none of them touch anything else the
## panel holds.

## What a session may ask to see, how thick the haze may be, and how far the grass is drawn.
const VIEW_RANGE_M: Vector2 = Vector2(200.0, 12000.0)
const FOG_RANGE: Vector2 = Vector2(0.0, 0.02)
const GRASS_RANGE_M: Vector2 = Vector2(0.0, 400.0)


## Adds the rows to a panel. `vegetation` may be null, which is a terrain that grows nothing.
static func build(
    rows: VBoxContainer, environment: Environment, camera: Camera3D, vegetation: RorVegetation
) -> void:
    MenuWidgets.heading(rows, "Distance")
    MenuWidgets.slider(
        rows, "View distance", VIEW_RANGE_M.x, VIEW_RANGE_M.y,
        camera.far if camera != null else RenderCfg.VIEW_DISTANCE_M,
        func(value: float) -> void:
            if camera != null:
                camera.far = value,
        "%.0f m"
    )
    MenuWidgets.check(
        rows, "Fog", environment.fog_enabled,
        func(on: bool) -> void: environment.fog_enabled = on
    )
    MenuWidgets.slider(
        rows, "Fog thickness", FOG_RANGE.x, FOG_RANGE.y, environment.fog_density,
        func(value: float) -> void:
            environment.fog_density = value
            environment.fog_enabled = value > 0.0,
        "%.4f"
    )
    MenuWidgets.slider(
        rows, "Fog in the sky", 0.0, 1.0, environment.fog_sky_affect,
        func(value: float) -> void: environment.fog_sky_affect = value
    )
    MenuWidgets.slider(
        rows, "Grass distance", GRASS_RANGE_M.x, GRASS_RANGE_M.y,
        vegetation.range_m() if vegetation != null else RorVegetation.MAX_RANGE_M,
        func(value: float) -> void:
            if vegetation != null:
                vegetation.set_range(value),
        "%.0f m"
    )
