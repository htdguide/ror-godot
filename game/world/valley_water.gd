class_name ValleyWater
extends RefCounted
## Builds the water: the lake at the low end, and the river that crosses the floor and drains
## into it.
##
## The surfaces come from `ValleyWaterCut`, which also carved the bed, so the water and the ground
## under it cannot disagree about where the shoreline is. Nothing here decides an elevation.
##
## Two things are worth knowing before changing it.
##
## The depth of the water under each vertex is baked into the mesh as vertex colour, and the
## shader fades the surface out with it. That is what gives a shoreline instead of a hard edge,
## and it works because the bed is a function this code can evaluate rather than something it has
## to read back from a depth buffer.
##
## The meshes extend past the shoreline, under the ground. Trimming a water mesh to its own
## shoreline is the obvious thing to do and it produces a visible edge as soon as the ripples move
## the surface: the ground is what hides the water, so there has to be water under the ground for
## it to hide.


## Builds every water body as one node, or null when there is nothing to build.
static func build() -> Node3D:
    var material: ShaderMaterial = _material()
    if material == null:
        return null
    var root: Node3D = Node3D.new()
    root.name = "Water"
    root.add_child(_lake(material))
    root.add_child(_crossing(material))
    root.add_child(_drain(material))
    return root


## The lake: one grid at a flat level, covering the basin and a margin of dry ground past it.
static func _lake(material: ShaderMaterial) -> MeshInstance3D:
    var west: float = TerrainCfg.ORIGIN.x
    var east: float = ValleyLayout.LAKE_SHORE_X_M + WaterCfg.LAKE_MARGIN_M
    var half: float = ValleyWaterCut.LAKE_HALF_WIDTH_M + WaterCfg.LAKE_MARGIN_M
    var level: float = ValleyShape.lake_water_y()
    var mesh: ArrayMesh = _grid(
        west, east, -half, half, WaterCfg.LAKE_CELL_M,
        func(_x: float, _z: float) -> float: return level
    )
    return _instance("Lake", mesh, material)


## The crossing: the strip of river that cuts across the valley floor, with the ford on it.
static func _crossing(material: ShaderMaterial) -> MeshInstance3D:
    var centre: float = ValleyLayout.RIVER_CROSS_X_M
    var half: float = ValleyLayout.RIVER_CROSS_HALF_WIDTH_M
    var mesh: ArrayMesh = _grid(
        centre - half, centre + half,
        ValleyLayout.DRAIN_Z_M, ValleyLayout.RIVER_INLET_Z_M,
        WaterCfg.RIVER_CELL_M,
        func(_x: float, z: float) -> float: return ValleyWaterCut.crossing_water_y(z)
    )
    return _instance("Crossing", mesh, material)


## The drain: the strip that runs west from the junction to the lake's own level.
static func _drain(material: ShaderMaterial) -> MeshInstance3D:
    var half: float = ValleyLayout.DRAIN_HALF_WIDTH_M
    var drain_z: float = ValleyLayout.DRAIN_Z_M
    # Stops where the lake's own mesh starts. Two transparent surfaces at the same level blend
    # twice and fight for depth, which reads as a flickering rectangle on the water.
    var mesh: ArrayMesh = _grid(
        ValleyLayout.LAKE_SHORE_X_M + WaterCfg.LAKE_MARGIN_M, ValleyLayout.RIVER_CROSS_X_M,
        drain_z - half, drain_z + half,
        WaterCfg.RIVER_CELL_M,
        func(x: float, _z: float) -> float: return ValleyWaterCut.drain_water_y(x)
    )
    return _instance("Drain", mesh, material)


## A grid of quads over an x/z rectangle, at whatever height `level_at` gives, carrying the depth
## of the water under each vertex as its colour.
##
## The height comes from the water body and the depth comes from the bed, so a vertex where the
## bed is above the surface carries a depth of zero and the shader draws nothing there. That is
## the whole shoreline mechanism.
static func _grid(
    west: float, east: float, south: float, north: float, cell: float, level_at: Callable
) -> ArrayMesh:
    var columns: int = maxi(1, int(ceil((east - west) / cell)))
    var rows: int = maxi(1, int(ceil((north - south) / cell)))
    var tool: SurfaceTool = SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    for column: int in columns:
        for row: int in rows:
            var x0: float = west + float(column) * cell
            var x1: float = minf(east, x0 + cell)
            var z0: float = south + float(row) * cell
            var z1: float = minf(north, z0 + cell)
            var corners: Array[Vector2] = [
                Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1),
            ]
            # Wound so the surface faces up. The material is double-sided anyway, because a camera
            # under the water still wants to see it.
            for index: int in [0, 2, 1, 0, 3, 2]:
                var at: Vector2 = corners[index]
                var level: float = level_at.call(at.x, at.y) as float
                if not is_finite(level):
                    level = ValleyShape.lake_water_y()
                var depth: float = maxf(0.0, level - ValleyShape.height_at_world(at.x, at.y))
                # As a fraction of the fade depth, not as metres. A mesh stores vertex colour as
                # eight bits a channel, so anything over 1.0 is clamped: baked in metres, every
                # part of an 11 m lake arrived at the shader as 1 m of water and the whole basin
                # rendered as shallows. A fraction has 14 mm of resolution over the fade, which is
                # finer than the shoreline needs.
                tool.set_color(Color(minf(depth / WaterCfg.FADE_DEPTH_M, 1.0), 0.0, 0.0, 1.0))
                tool.set_normal(Vector3.UP)
                tool.set_uv(Vector2(at.x, at.y))
                tool.add_vertex(Vector3(at.x, level, at.y))
    return tool.commit()


static func _instance(name: String, mesh: ArrayMesh, material: ShaderMaterial) -> MeshInstance3D:
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = name
    instance.mesh = mesh
    instance.material_override = material
    # Water is not a shadow caster: a transparent surface casting an opaque shadow puts a dark
    # slab on the bed under it.
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    return instance


static func _material() -> ShaderMaterial:
    var shader: Shader = load("res://shaders/water.gdshader") as Shader
    if shader == null:
        return null
    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("shallow_colour", WaterCfg.SHALLOW_COLOUR)
    material.set_shader_parameter("deep_colour", WaterCfg.DEEP_COLOUR)
    material.set_shader_parameter("fade_depth_m", WaterCfg.FADE_DEPTH_M)
    material.set_shader_parameter("edge_depth_m", WaterCfg.EDGE_DEPTH_M)
    material.set_shader_parameter("ripples", _ripple_map())
    material.set_shader_parameter("ripple_scale_m", WaterCfg.RIPPLE_SCALE_M)
    material.set_shader_parameter("ripple_scale_fine_m", WaterCfg.RIPPLE_SCALE_FINE_M)
    material.set_shader_parameter("ripple_drift", WaterCfg.RIPPLE_DRIFT)
    material.set_shader_parameter("ripple_drift_fine", WaterCfg.RIPPLE_DRIFT_FINE)
    material.set_shader_parameter("ripple_strength", WaterCfg.RIPPLE_STRENGTH)
    material.set_shader_parameter("water_roughness", WaterCfg.ROUGHNESS)
    material.set_shader_parameter("water_specular", WaterCfg.SPECULAR)
    return material


## A tiling ripple normal map, generated rather than sourced, like the ground textures: noise
## turned into a normal map by Godot's own native call, so the whole scene still needs no
## third-party asset.
static func _ripple_map() -> ImageTexture:
    var noise: FastNoiseLite = FastNoiseLite.new()
    noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    noise.frequency = WaterCfg.RIPPLE_FREQUENCY
    noise.seed = 0
    var height: Image = noise.get_image(
        WaterCfg.RIPPLE_PIXELS, WaterCfg.RIPPLE_PIXELS, false, false, true
    )
    height.bump_map_to_normal_map(1.0)
    return ImageTexture.create_from_image(height)
