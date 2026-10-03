class_name FacingPaint
extends RefCounted
## Paints the back of every surface a bright colour, so a face turned the wrong way is visible
## instead of absent.
##
## **A back face is culled, and nothing is not measurable.** A wall wound the wrong way round
## renders as empty sky, which is pixel for pixel what a correct empty sky looks like, so a
## photograph of the fault and a photograph of nothing being wrong are the same image. Asked for
## from a window, in those words: paint the surfaces by their normal so a wrongly turned texture
## highlights itself.
##
## The front of a face keeps its own texture. The back draws the axis it points along — red for
## x, green for y, blue for z — unshaded, so the marker reads the same under any light and the
## measurement does not become a measurement of the lighting.
##
## This is a diagnostic dress, not how a terrain is drawn. `apply` puts it on and the caller
## throws the mesh away afterwards.

const SHADER: String = "res://game/shaders/facing_check.gdshader"
## How saturated a pixel has to be to be a marker rather than scenery. A terrain's own colours —
## brick, grass, asphalt, a pale sky — sit well inside this; the markers are primaries.
const MARKER_SPREAD: float = 0.5
const MARKER_BRIGHTNESS: float = 0.5


## Dresses every surface of `mesh` in the facing check, keeping each surface's own albedo.
static func apply(mesh: ArrayMesh) -> void:
    var shader: Shader = load(SHADER) as Shader
    for surface: int in mesh.get_surface_count():
        var original: StandardMaterial3D = mesh.surface_get_material(
            surface
        ) as StandardMaterial3D
        var painted: ShaderMaterial = ShaderMaterial.new()
        painted.shader = shader
        if original != null:
            painted.set_shader_parameter("albedo_colour", original.albedo_color)
            if original.albedo_texture != null:
                painted.set_shader_parameter("albedo_texture", original.albedo_texture)
        mesh.surface_set_material(surface, painted)


## How much of an image is marker: a pixel whose channels are further apart than any of a
## terrain's own colours and bright with it.
static func marked_share(path: String) -> float:
    var image: Image = Image.load_from_file(path)
    if image == null:
        return 0.0
    var marked: int = 0
    var total: int = 0
    for y: int in range(0, image.get_height(), 2):
        for x: int in range(0, image.get_width(), 2):
            total += 1
            if is_marker(image.get_pixel(x, y)):
                marked += 1
    return 0.0 if total == 0 else float(marked) / float(total)


## Whether one pixel is a marker rather than scenery.
static func is_marker(pixel: Color) -> bool:
    var high: float = maxf(pixel.r, maxf(pixel.g, pixel.b))
    var low: float = minf(pixel.r, minf(pixel.g, pixel.b))
    return high > MARKER_BRIGHTNESS and high - low > MARKER_SPREAD
