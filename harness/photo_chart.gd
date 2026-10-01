class_name PhotoChart
extends RefCounted
## The photographer's instrument: a step wedge, a light of stated illuminance, and the readings
## taken off a photograph of them.
##
## Extracted so that every gate measuring light measures it with the *same* instrument. That is
## not tidiness. `a_photographed_chart_measures_the_light` established that this wedge, read this
## way, is linear in reflectance to 0.00% and scales exactly with exposure — and the only reason
## a later gate may trust its own numbers is that it is reading through that proven instrument
## rather than through a second copy of it that was never checked.
##
## Reflectances are set by the caller and asserted against; nothing here recites a published
## value, so no gate built on this is writing its own expectation.

## A photographic step wedge: a stop between each patch, centred on an 18% grey card.
##
## Six patches rather than one, because the two faults a wedge has already caught in this project
## — sky ambient leaking into a "dark" room, and fog — were both *additive*. An offset bends a
## measurement most where the subject is darkest and barely at all where it is brightest, so a
## single mid-grey card reads "about right" while the response is visibly bent.
const WEDGE: Array[float] = [0.72, 0.36, 0.18, 0.09, 0.045, 0.0225]
const PATCH_SIZE: float = 0.9
const PATCH_GAP: float = 1.05
## 6500 K daylight, as a neutral: a white balance check wants a light that is actually white.
const LIGHT_COLOUR: Color = Color(1.0, 1.0, 1.0)
## Half the side of the window sampled at each patch's centre, in pixels.
const WINDOW_PX: int = 10
## Rec. 709 luminance weights, which is what the renderer's own exposure is relative to.
const LUMA: Vector3 = Vector3(0.2126, 0.7152, 0.0722)


## Where the wedge stands, so a camera and a sampler agree without being told twice.
static func patch_position(index: int) -> Vector3:
    var span: float = float(WEDGE.size() - 1) * PATCH_GAP
    return Vector3(float(index) * PATCH_GAP - span * 0.5, 0.0, 0.0)


## How far back a camera has to stand to frame the whole wedge.
static func camera_distance() -> float:
    return float(WEDGE.size() - 1) * PATCH_GAP * 1.25


## The wedge as meshes, each patch a Lambertian plane of stated reflectance.
##
## `chart_patch.gdshader` and not a `StandardMaterial3D`: an albedo colour goes through an sRGB
## conversion on its way into the shader, so a patch asked for 0.18 would not be reflecting 0.18.
static func build_wedge() -> Array[MeshInstance3D]:
    var out: Array[MeshInstance3D] = []
    var shader: Shader = load("res://game/shaders/chart_patch.gdshader") as Shader
    for index: int in WEDGE.size():
        var plane: PlaneMesh = PlaneMesh.new()
        plane.size = Vector2(PATCH_SIZE, PATCH_SIZE)
        plane.orientation = PlaneMesh.FACE_Z
        var material: ShaderMaterial = ShaderMaterial.new()
        material.shader = shader
        var level: float = WEDGE[index]
        material.set_shader_parameter("reflectance", Vector3(level, level, level))
        var instance: MeshInstance3D = MeshInstance3D.new()
        instance.name = "Patch_%d" % index
        instance.mesh = plane
        instance.material_override = material
        instance.position = patch_position(index)
        out.append(instance)
    return out


## A light of stated illuminance, aimed at the chart from a direction.
static func build_light(name: String, from: Vector3, lux: float) -> DirectionalLight3D:
    var light: DirectionalLight3D = DirectionalLight3D.new()
    light.name = name
    light.look_at_from_position(Vector3.ZERO, -from.normalized(), Vector3.UP)
    light.light_intensity_lux = lux
    light.light_color = LIGHT_COLOUR
    light.light_energy = 1.0
    # A chart is flat and unoccluded; a shadow map here would only add its own bias.
    light.shadow_enabled = false
    return light


## Clears the stage: every mesh and every light the preset built, hidden. What is left is a
## darkroom with nothing in it, which is the only state a lighting measurement can start from.
static func clear_stage(world: Node3D) -> void:
    for child: Node in world.get_children():
        if child is MeshInstance3D:
            (child as MeshInstance3D).visible = false
        var light: Light3D = child as Light3D
        if light != null:
            light.visible = false


## The illuminance that actually lands on a surface, which is not the light's intensity.
##
## **Lambert's cosine law.** A gate once compared a photograph against the bare ratio of two
## lights' intensities, got a 70% "error", and was wrong: the fill arrived at 54 degrees, so only
## cos(54) = 0.588 of it landed. The renderer was right. An incident meter obeys the same law,
## which is why a photographer aims one at the camera rather than at the light.
static func incident_lux(lux: float, from: Vector3, surface_normal: Vector3) -> float:
    return lux * maxf(from.normalized().dot(surface_normal.normalized()), 0.0)


## One HDR photograph, read as a mean luminance at each patch centre.
##
## The capture is an unclipped float image: a PNG is 8-bit and display-encoded, so a ratio read
## off one is not a ratio of light. That cost this project every sun-to-sky figure it recorded
## before the EXR path existed.
static func read_patches(image: Image, at: PackedVector2Array) -> PackedFloat32Array:
    var out: PackedFloat32Array = PackedFloat32Array()
    for centre: Vector2 in at:
        out.append(window(image, centre))
    return out


## Where each patch lands on the film, for a camera that is already looking at the wedge.
static func patch_pixels(camera: Camera3D) -> PackedVector2Array:
    var at: PackedVector2Array = PackedVector2Array()
    for index: int in WEDGE.size():
        at.append(camera.unproject_position(patch_position(index)))
    return at


## Mean luminance over a small window, rather than one pixel: a single sample would carry
## whatever dither or edge the rasteriser happened to put there.
static func window(image: Image, centre: Vector2) -> float:
    var size: Vector2i = image.get_size()
    var total: float = 0.0
    var counted: int = 0
    for y: int in range(int(centre.y) - WINDOW_PX, int(centre.y) + WINDOW_PX):
        for x: int in range(int(centre.x) - WINDOW_PX, int(centre.x) + WINDOW_PX):
            if x < 0 or y < 0 or x >= size.x or y >= size.y:
                continue
            var colour: Color = image.get_pixel(x, y)
            total += colour.r * LUMA.x + colour.g * LUMA.y + colour.b * LUMA.z
            counted += 1
    return total / float(maxi(counted, 1))


## How far the widest value in a set sits from its own mean, as a share of it.
static func spread(values: PackedFloat32Array) -> float:
    var middle: float = mean(values)
    if middle <= 0.0:
        return INF
    var worst: float = 0.0
    for value: float in values:
        worst = maxf(worst, absf(value - middle) / middle)
    return worst


static func mean(values: PackedFloat32Array) -> float:
    if values.is_empty():
        return 0.0
    var total: float = 0.0
    for value: float in values:
        total += value
    return total / float(values.size())


## Each patch divided by the reflectance it was given. For a linear response these are all the
## same number, and that number is the illuminance the wedge is standing in.
static func per_reflectance(values: PackedFloat32Array) -> PackedFloat32Array:
    var out: PackedFloat32Array = PackedFloat32Array()
    for index: int in mini(values.size(), WEDGE.size()):
        out.append(values[index] / WEDGE[index])
    return out


## The readings as a readable row, reflectance at value, for a failure message that can be acted
## on without re-running anything.
static func row(values: PackedFloat32Array) -> String:
    var parts: PackedStringArray = PackedStringArray()
    for index: int in values.size():
        parts.append("%.4f@%.5f" % [WEDGE[index], values[index]])
    return ", ".join(parts)
