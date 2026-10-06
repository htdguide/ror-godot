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

## The camera this project is graded against: the exposure every stated brightness in it means.
##
## A weather preset that names no exposure of its own is metered here, and `exposure_scale` is how
## far from here any other hour has been taken.
const REFERENCE_F_STOP: float = 8.0
const REFERENCE_SHUTTER_S: float = 0.008
## **The reference film is a constant and not the project's current one.** It was
## `RenderCfg.CAMERA_ISO`, which is the sensitivity a daylight camera is set to and is tuned — and
## a reference that moves with what it is measuring is not a reference: every preset that states
## no film of its own came out at a scale of exactly 1.0 whatever the camera was doing, so opening
## the camera half a stop put the sky's light back to being exposed twice. Measured, the
## sunlit-to-skylit ratio of one unchanged scene fell from 13.3:1 to 10.4:1 on nothing but an ISO
## change. 32 is where this project's daylight camera stood when the skies were calibrated.
const REFERENCE_ISO: float = 32.0


## How much more light this hour's camera gathers than the reference one.
##
## **A sky must not follow the camera, and this is what lets it stop.** With physical light units
## Godot hands a sky shader a light energy that already has the camera's exposure in it, and then
## applies the exposure again to whatever the sky returns, so every part of a sky that is drawn
## from the sun — the scattering of `PhysicalSkyMaterial`, this project's own clouds and sun disc —
## is exposure *squared*. Measured on one unchanged noon scene, the sun lit a grey card at exactly
## twice the value for twice the ISO, as it must, while the sky lit it 6.2 times: the sunlit to
## skylit ratio read 19.2:1 at ISO 16, 6.4:1 at 32 and 2.7:1 at 64, which is a lighting balance
## that depends on the film in the camera. Dividing the sun's energy by this before the sky uses it
## leaves exactly one exposure on the result, which is the one the renderer applies.
static func exposure_scale(weather: Dictionary) -> float:
    var f_stop: float = float(weather.get("f_stop", REFERENCE_F_STOP))
    var shutter_s: float = float(weather.get("shutter_s", REFERENCE_SHUTTER_S))
    var iso: float = float(weather.get("iso", RenderCfg.CAMERA_ISO))
    var reference: float = (
        REFERENCE_ISO * REFERENCE_SHUTTER_S / (REFERENCE_F_STOP * REFERENCE_F_STOP)
    )
    if reference <= 0.0 or f_stop <= 0.0:
        return 1.0
    return (iso * shutter_s / (f_stop * f_stop)) / reference


## The same number for a camera that already exists, which is what a live exposure change has.
static func exposure_scale_of(camera: Camera3D) -> float:
    var attributes: CameraAttributesPhysical = (
        camera.attributes as CameraAttributesPhysical if camera != null else null
    )
    if attributes == null:
        return 1.0
    return exposure_scale({
        "f_stop": attributes.exposure_aperture,
        "shutter_s": 1.0 / maxf(attributes.exposure_shutter_speed, 0.000001),
        "iso": attributes.exposure_sensitivity,
    })


## The camera is physical: depth of field then follows from the lens instead of being
## dialled by hand, and exposure is comparable between weather presets.
static func build(from_preset: Dictionary, weather: Dictionary = {}) -> Camera3D:
    var attributes: CameraAttributesPhysical = CameraAttributesPhysical.new()
    attributes.frustum_focal_length = float(from_preset.get("focal_mm", 35.0))
    # **A physical camera carries its own far plane and it overrides the one on the node.**
    # `CameraAttributesPhysical.frustum_far` defaults to 4,000 m and Godot writes it onto the
    # `Camera3D` whenever the attributes are touched — so a camera set to draw fourteen kilometres
    # was pulled back to four the moment an hour re-metered it. Reported from a window as the
    # mountains disappearing when the weather is switched and never coming back: the switch
    # re-exposes the camera, and the terrain's own backdrop stands at 12.8 km. Measured by hiding
    # the backdrop and photographing the difference — 0.1569 as built, 0.0000 after one switch.
    attributes.frustum_far = RenderCfg.VIEW_DISTANCE_M
    attributes.auto_exposure_enabled = false
    _expose(attributes, from_preset, weather)
    var cam: Camera3D = Camera3D.new()
    cam.name = "HarnessCamera"
    cam.attributes = attributes
    # **How far a camera draws belongs to the camera, not to the window.** The session set this and
    # a gate did not, so every gate in this project photographed a four-kilometre world — Godot's
    # own default — while a session saw fourteen. A terrain's own backdrop stands at ten, so the
    # thing a session looks at was outside every measurement ever taken of it, and a probe written
    # to photograph that backdrop came back with no mountains in it and no reason given.
    cam.far = RenderCfg.VIEW_DISTANCE_M
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
        weather.get("f_stop", preset.get("f_stop", REFERENCE_F_STOP))
    )
    attributes.exposure_shutter_speed = 1.0 / maxf(
        float(weather.get("shutter_s", preset.get("shutter_s", REFERENCE_SHUTTER_S))), 0.000001
    )
    # With physical light units the exposure is the photographer's three numbers and nothing
    # else: aperture, shutter, sensitivity. There is no multiplier standing in for them.
    attributes.exposure_sensitivity = float(
        weather.get("iso", preset.get("iso", RenderCfg.CAMERA_ISO))
    )
