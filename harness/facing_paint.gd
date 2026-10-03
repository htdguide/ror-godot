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
## How much a pixel has to move, summed over the channels, to count as the subject rather than as
## the renderer's own noise between two captures of the same scene.
const CHANGED: float = 0.02


## Dresses every surface of `mesh` in the facing check, keeping each surface's own albedo.
##
## **A surface the terrain already draws from both sides is left alone.** A material declaring
## `alpha_rejection` is a punched-out card — foliage, a fence, a railing — and `RorObjects` gives
## it `CULL_DISABLED` on purpose, so the back of one is not a fault and marking it says nothing.
## Painted anyway, a correctly drawn fir filled 18% of its frame with marker. Those surfaces are
## photographed by the cut-out gate instead.
static func apply(mesh: ArrayMesh) -> void:
    var shader: Shader = load(SHADER) as Shader
    for surface: int in mesh.get_surface_count():
        if FacingViews.two_sided(mesh, surface):
            continue
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


## How many sampled pixels a subject drew into a frame, and how many of those are marker.
##
## Measured against the same view of the same stage without the subject, because a stage's own
## floor and sky fill a frame whether or not anything is standing in it: counting "pixels that
## are not background" passes every view on its own. Marker is counted only among the pixels the
## subject drew, so the figure is a share of the surface rather than of the frame and does not
## move when the framing does.
static func drawn_and_marked(shot: String, bare: String) -> Dictionary:
    var shown: Image = Image.load_from_file(shot)
    var stage: Image = Image.load_from_file(bare)
    if shown == null or stage == null or shown.get_size() != stage.get_size():
        return {"drawn": 0, "marked": 0}
    var drawn: int = 0
    var marked: int = 0
    for y: int in range(0, shown.get_height(), 2):
        for x: int in range(0, shown.get_width(), 2):
            var here: Color = shown.get_pixel(x, y)
            var there: Color = stage.get_pixel(x, y)
            if (
                absf(here.r - there.r) + absf(here.g - there.g) + absf(here.b - there.b)
                <= CHANGED
            ):
                continue
            drawn += 1
            if is_marker(here):
                marked += 1
    return {"drawn": drawn, "marked": marked}


## Whether one pixel is a marker rather than scenery.
static func is_marker(pixel: Color) -> bool:
    var high: float = maxf(pixel.r, maxf(pixel.g, pixel.b))
    var low: float = minf(pixel.r, minf(pixel.g, pixel.b))
    return high > MARKER_BRIGHTNESS and high - low > MARKER_SPREAD
