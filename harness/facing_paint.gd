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
## How much a pixel may move, summed over the channels, between two captures of the same frame and
## still be the same surface rather than the background behind it.
const CHANGED: float = 0.02
## How wide a capture is scanned at. See `drawn_and_marked`.
const SAMPLE_WIDTH: int = 480


## Dresses every mesh under a node in the facing check: a whole terrain's scenery, in a session.
##
## **For looking at a map with, not for measuring.** A gate photographs one object alone on a
## stage and knows which surface it is asking about; a person driving round a map does not, and
## the question they need answered is the same one — which of these walls is turned away. Asked
## for from a window: show the back highlighted in the session, so a screenshot can show it.
##
## A mesh is dressed once however many batches share it, which is what the `seen` set is for, and
## a surface already wearing the shader is left alone — dressing it twice would read its own
## shader material as a `StandardMaterial3D`, get null, and lose the albedo.
static func dress(root: Node) -> int:
    var seen: Dictionary = {}
    var dressed: int = 0
    for node: Node in _mesh_nodes(root):
        var mesh: ArrayMesh = (node.get("mesh") as ArrayMesh)
        if mesh == null and node is MultiMeshInstance3D:
            mesh = (node as MultiMeshInstance3D).multimesh.mesh as ArrayMesh
        if mesh == null or seen.has(mesh.get_instance_id()):
            continue
        seen[mesh.get_instance_id()] = true
        apply(mesh)
        dressed += 1
    return dressed


## Every node under `root` that draws a mesh, itself included.
static func _mesh_nodes(root: Node) -> Array[Node]:
    var out: Array[Node] = []
    if root is MeshInstance3D or root is MultiMeshInstance3D:
        out.append(root)
    for child: Node in root.get_children():
        out.append_array(_mesh_nodes(child))
    return out


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
        if mesh.surface_get_material(surface) is ShaderMaterial:
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
## **The two captures are the same frame against two different backgrounds.** A pixel the subject
## drew is identical in both; a pixel of background is not. Capturing the stage without the
## subject and differencing instead looks equivalent and is not: it loses every part of a subject
## that happens to match the stage, and `sidewalk.mesh` — mid-grey concrete, drawn unshaded,
## against a mid-grey sky — cancelled over its entire top face, leaving the measure to be taken
## over its four edges, which are correctly back-facing from above. It read 83% and the slab was
## fine.
##
## Both frames are shrunk to a fixed small size first. A gate that photographs a whole map's
## object library takes thousands of these, and scanning a 1920x1080 capture pixel by pixel in
## GDScript is where the time goes, not the rendering. Nearest-neighbour, so a marker's primary
## colour survives the shrink unmixed — a bilinear resize would blend a marker with the background
## beside it and turn both into something that is neither.
static func drawn_and_marked(on_dark: String, on_light: String) -> Dictionary:
    var dark: Image = Image.load_from_file(on_dark)
    var light: Image = Image.load_from_file(on_light)
    if dark == null or light == null or dark.get_size() != light.get_size():
        return {"drawn": 0, "marked": 0, "sampled": 0}
    if dark.get_width() > SAMPLE_WIDTH:
        var height: int = maxi(1, dark.get_height() * SAMPLE_WIDTH / dark.get_width())
        dark.resize(SAMPLE_WIDTH, height, Image.INTERPOLATE_NEAREST)
        light.resize(SAMPLE_WIDTH, height, Image.INTERPOLATE_NEAREST)
    var drawn: int = 0
    var marked: int = 0
    for y: int in range(0, dark.get_height()):
        for x: int in range(0, dark.get_width()):
            var here: Color = dark.get_pixel(x, y)
            var there: Color = light.get_pixel(x, y)
            if (
                absf(here.r - there.r) + absf(here.g - there.g) + absf(here.b - there.b)
                > CHANGED
            ):
                continue
            drawn += 1
            if is_marker(here):
                marked += 1
    return {
        "drawn": drawn, "marked": marked,
        "sampled": dark.get_width() * dark.get_height(),
    }


## Whether one pixel is a marker rather than scenery.
static func is_marker(pixel: Color) -> bool:
    var high: float = maxf(pixel.r, maxf(pixel.g, pixel.b))
    var low: float = minf(pixel.r, minf(pixel.g, pixel.b))
    return high > MARKER_BRIGHTNESS and high - low > MARKER_SPREAD
