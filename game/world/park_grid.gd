class_name ParkGrid
extends RefCounted
## The test park's dev grid, drawn as an overlay above the ground instead of painted into it.
##
## Painting it into the terrain's colour map is what was here first, and a session reported the
## result as "too blurry". That is a resolution fault rather than a palette one: the colour map is
## one texel per metre, filtered and mipmapped, so a 0.45 m line is a third of a texel and arrives
## as a smear that gets worse with distance. A line that has to stay a line at 5 m and at 300 m
## cannot be stored in a texture at all — it has to be a function of the position, evaluated per
## pixel, which is `shaders/park_grid.gdshader`.
##
## So the terrain keeps the ground's own colour and every surface a test area is made of, and this
## adds the lines on top, alpha-blended a couple of centimetres above a floor that is flat where
## the grid is drawn. Off the road the park's height is exactly zero: the washboard, the ruts,
## the dips and the hump are all inside the road's width, so a plane is the right shape for it,
## and `park_ground_is_a_dev_grid` measures that the lines land where the grid function says.
##
## Where the grid is *not* drawn is baked from `ParkShape` rather than restated in the shader: the
## road, its patches and the skid pad are drawn as themselves, and the one function that knows
## where they are stays the one function that knows.

const SHADER_PATH: String = "res://shaders/park_grid.gdshader"
## How much of the mask to actually ask `ParkShape` about. The mask is grid everywhere except the
## test areas, and the test areas are two places, so the bake fills the map and then walks only
## their bounding boxes — 13 k samples rather than 4.2 M. A box that is too big costs a few
## thousand more samples and changes nothing; one that is too small would leave a grid drawn over
## a test area, which is what the gate looks for.
const MASK_MARGIN_M: float = 4.0

## The mask is the same lattice as the terrain, so it is built once and kept.
static var _mask: ImageTexture = null


## The grid overlay. Add it to the world after the terrain.
static func build() -> MeshInstance3D:
    var plane: PlaneMesh = PlaneMesh.new()
    var span: float = float(TerrainCfg.MAP_SIZE) * TerrainCfg.VERTEX_SPACING
    plane.size = Vector2(span, span)
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = "ParkGrid"
    instance.mesh = plane
    instance.position = Vector3(0.0, ParkCfg.GRID_LIFT_M, 0.0)
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    instance.material_override = material()
    # A 2 km plane is inside the frustum from everywhere in the park, and its own bounds are
    # correct, so nothing here needs a custom AABB.
    return instance


## The overlay's material, for the mesh and for anything that wants to read the grid's own
## parameters back out of it.
static func material() -> ShaderMaterial:
    var shader: Shader = load(SHADER_PATH) as Shader
    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("spacing_m", ParkCfg.GRID_SPACING_M)
    material.set_shader_parameter("line_width_m", ParkCfg.GRID_LINE_M)
    material.set_shader_parameter("major_every", float(ParkCfg.GRID_MAJOR_EVERY))
    material.set_shader_parameter("major_width_scale", ParkCfg.GRID_MAJOR_WIDTH_SCALE)
    material.set_shader_parameter("line_colour", ParkCfg.GRID_LINE)
    material.set_shader_parameter("major_colour", ParkCfg.GRID_MAJOR)
    material.set_shader_parameter("test_area_mask", mask())
    # Sampled with a filter, so the origin is the first texel's *centre*: half a texel in from
    # where the map starts. Half a metre of grid drawn over a kerb is not worth a fault report,
    # but it is exactly the sort of half-texel error that makes a gate's numbers unrepeatable.
    material.set_shader_parameter("mask_origin_m", Vector2(
        TerrainCfg.ORIGIN.x - TerrainCfg.VERTEX_SPACING * 0.5,
        TerrainCfg.ORIGIN.z - TerrainCfg.VERTEX_SPACING * 0.5
    ))
    material.set_shader_parameter(
        "mask_size_m", float(TerrainCfg.MAP_SIZE) * TerrainCfg.VERTEX_SPACING
    )
    material.set_shader_parameter("grid_roughness", ParkCfg.GRID_ROUGHNESS)
    return material


## Where the grid may be drawn, as a texture: white for grid, black for a test area.
static func mask() -> ImageTexture:
    if _mask != null:
        return _mask
    _mask = ImageTexture.create_from_image(mask_image())
    return _mask


## The same mask as an image, which is what the gate reads.
static func mask_image() -> Image:
    var size: int = TerrainCfg.MAP_SIZE
    var image: Image = Image.create_empty(size, size, false, Image.FORMAT_R8)
    image.fill(Color(1.0, 0.0, 0.0))
    for box: Rect2 in _test_area_bounds():
        _clear_test_areas(image, box)
    return image


## Boxes big enough to hold every part of the park that is drawn as itself.
static func _test_area_bounds() -> Array[Rect2]:
    var margin: float = MASK_MARGIN_M
    var road: Rect2 = Rect2(
        ParkCfg.ROAD_WEST_M - margin,
        -ParkCfg.ROAD_HALF_WIDTH_M - margin,
        ParkCfg.ROAD_EAST_M - ParkCfg.ROAD_WEST_M + margin * 2.0,
        ParkCfg.ROAD_HALF_WIDTH_M * 2.0 + margin * 2.0
    )
    var reach: float = ParkCfg.SKID_PAD_RADIUS_M + margin
    var pad: Rect2 = Rect2(
        ParkCfg.SKID_PAD_CENTRE.x - reach,
        ParkCfg.SKID_PAD_CENTRE.y - reach,
        reach * 2.0,
        reach * 2.0
    )
    return [road, pad]


## Asks the shape which cells inside a box are test areas, and blacks those out.
static func _clear_test_areas(image: Image, box: Rect2) -> void:
    var size: int = TerrainCfg.MAP_SIZE
    var spacing: float = TerrainCfg.VERTEX_SPACING
    var first_x: int = _cell(box.position.x - TerrainCfg.ORIGIN.x, spacing, size)
    var last_x: int = _cell(box.end.x - TerrainCfg.ORIGIN.x, spacing, size)
    var first_z: int = _cell(box.position.y - TerrainCfg.ORIGIN.z, spacing, size)
    var last_z: int = _cell(box.end.y - TerrainCfg.ORIGIN.z, spacing, size)
    var black: Color = Color(0.0, 0.0, 0.0)
    for z: int in range(first_z, last_z + 1):
        for x: int in range(first_x, last_x + 1):
            var world: Vector2 = ValleyShape.world_of(x, z)
            if ParkShape.is_test_area(world.x, world.y):
                image.set_pixel(x, z, black)


## Which cell an offset from the map's origin falls in, inside the map.
static func _cell(offset: float, spacing: float, size: int) -> int:
    return clampi(int(round(offset / spacing)), 0, size - 1)
