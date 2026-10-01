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
static func build(from_preset: Dictionary) -> Camera3D:
    var attributes: CameraAttributesPhysical = CameraAttributesPhysical.new()
    attributes.frustum_focal_length = float(from_preset.get("focal_mm", 35.0))
    attributes.exposure_aperture = float(from_preset.get("f_stop", 8.0))
    attributes.exposure_shutter_speed = 1.0 / maxf(float(from_preset.get("shutter_s", 0.008)), 0.000001)
    # With physical light units the exposure is the photographer's three numbers and nothing else:
    # aperture, shutter, sensitivity. There is no multiplier standing in for them.
    attributes.exposure_sensitivity = float(from_preset.get("iso", RenderCfg.CAMERA_ISO))
    attributes.auto_exposure_enabled = false
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
