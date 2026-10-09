class_name PlayDistanceRows
extends RefCounted
## The settings panel's distance rows: how far a session can see, and what closes the distance.
##
## Split out of `PlayMenu` when the day-of-the-clock slider took that file over its source cap.
## It is a clean seam rather than a convenience: these rows touch the camera's far plane, the
## environment's haze and the vegetation's own range, and none of them touch anything else the
## panel holds.

## What a session may ask to see, and how far the grass is drawn.
const VIEW_RANGE_M: Vector2 = Vector2(200.0, 14000.0)
const GRASS_RANGE_M: Vector2 = Vector2(0.0, 400.0)


## Adds the rows to a panel. `vegetation` may be null, which is a terrain that grows nothing.
static func build(
    rows: VBoxContainer, environment: Environment, camera: Camera3D,
    vegetation: RorVegetation, world: Node3D = null
) -> void:
    MenuWidgets.heading(rows, "Distance")
    # **The view distance moves the scenery, not the far plane.** It used to set `camera.far`,
    # which clips everything: pulling it in to look at the near ground took the terrain's own
    # painted horizon with it, and there is nothing behind a horizon to show instead. The camera
    # reaches as far as the terrain draws and stays there; this is how far the things standing on
    # the terrain are drawn, and the backdrop is left out of it. See `SceneryRange.set_draw_distance`.
    MenuWidgets.slider(
        rows, "View distance", VIEW_RANGE_M.x, VIEW_RANGE_M.y, RenderCfg.VIEW_DISTANCE_M,
        func(value: float) -> void:
            if world != null:
                SceneryRange.set_draw_distance(world, value),
        "%.0f m"
    )
    # And the far plane itself, named as what it is. A session reported "view distance stopped
    # working" the day it stopped clipping the terrain and the mountains: the camera's clip is
    # a different thing from how far scenery is drawn, and both are a person's to move.
    MenuWidgets.slider(
        rows, "Far plane", VIEW_RANGE_M.x, VIEW_RANGE_M.y, camera.far,
        func(value: float) -> void: camera.far = value,
        "%.0f m"
    )
    # The fog's thickness and colour are weather rows; this is the one fog number that is not.
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
