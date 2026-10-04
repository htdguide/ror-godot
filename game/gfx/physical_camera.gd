class_name PhysicalCamera
extends RefCounted
## A camera with a real lens: focal length, aperture, shutter and sensitivity.
##
## Extracted from `Harness` when it went over the source cap, and it belongs on the game side
## rather than in the harness because the client needs the same camera the gates photograph
## through — a chase camera whose depth of field disagrees with the one in a gate is a renderer
## nobody can judge from a gate.
##
## **Exposure is the photographer's three numbers and nothing else.** With physical light units
## on, the aperture, the shutter and the ISO decide how bright the image is, the way they do on a
## camera; there is no multiplier on the tonemapper standing in for them, and there is no
## auto-exposure, whose convergence is temporal and would make a gate's result depend on how many
## frames it happened to render.

## The camera is physical: depth of field then follows from the lens instead of being
## dialled by hand, and exposure is comparable between weather presets.
static func build(from_preset: Dictionary, weather: Dictionary = {}) -> Camera3D:
    var attributes: CameraAttributesPhysical = CameraAttributesPhysical.new()
    attributes.frustum_focal_length = float(from_preset.get("focal_mm", 35.0))
    attributes.auto_exposure_enabled = false
    _expose(attributes, from_preset, weather)
    var cam: Camera3D = Camera3D.new()
    cam.name = "HarnessCamera"
    cam.attributes = attributes
    cam.position = from_preset.get("pos", Vector3.ZERO) as Vector3
    cam.look_at_from_position(
        from_preset.get("pos", Vector3.ZERO) as Vector3,
        from_preset.get("look_at", Vector3.ZERO) as Vector3,
        Vector3.UP
    )
    return cam


## Re-meters a camera that already exists for another hour of the day.
##
## **An hour states its light in lux, so it has to state the exposure that light was metered
## for.** A camera set for a hundred thousand lux of midday sun — f/8, a hundred-and-twenty-fifth,
## ISO 32 — sees nothing at all by a two-lux moon, and nothing a vehicle's lamps do can reach it:
## a 22,000 cd low beam is about fifty lux on the road at twenty metres, a two-thousandth of what
## the day exposure was set for. That is the whole of "the headlights do not work at night", and
## it is not a fault in the headlights.
##
## The window re-meters when the weather changes, the way a driver's own eye does. A preset that
## states no exposure of its own keeps the shot's, which is every daylight hour this project has.
static func reexpose(camera: Camera3D, preset: Dictionary, weather: Dictionary) -> void:
    var attributes: CameraAttributesPhysical = (
        camera.attributes as CameraAttributesPhysical
    )
    if attributes == null:
        return
    _expose(attributes, preset, weather)


## The photographer's three numbers: the hour's where it states them, the shot's otherwise.
static func _expose(
    attributes: CameraAttributesPhysical, preset: Dictionary, weather: Dictionary
) -> void:
    attributes.exposure_aperture = float(
        weather.get("f_stop", preset.get("f_stop", 8.0))
    )
    attributes.exposure_shutter_speed = 1.0 / maxf(
        float(weather.get("shutter_s", preset.get("shutter_s", 0.008))), 0.000001
    )
    # With physical light units the exposure is the photographer's three numbers and nothing
    # else: aperture, shutter, sensitivity. There is no multiplier standing in for them.
    attributes.exposure_sensitivity = float(
        weather.get("iso", preset.get("iso", RenderCfg.CAMERA_ISO))
    )
