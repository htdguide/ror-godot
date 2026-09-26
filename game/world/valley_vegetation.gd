class_name ValleyVegetation
extends RefCounted
## Grows the valley's conifers and shrubs.
##
## Placement is a pure function of position: each cell of a grid is hashed, and the hash decides
## whether something grows there, which species it is, how big it is and which way it faces. There
## is no random number generator and no stored list, so the same valley grows the same forest on
## any machine, and a gate can check an instance by recomputing it rather than by trusting a
## record of what was planted.
##
## **Not Terrain3DInstancer, which PLAN §0.6 named.** The instancer stores its instances inside
## Terrain3D's region files — the same files `ValleyCache` keeps between runs — so the forest would
## become cached data rather than a consequence of the layout, and the cache's verification only
## samples heights. It also wants a `PackedScene` per species, which means assets on disk, and the
## CLI-only rule prefers generated. A multimesh built from the placement function keeps one source
## of truth and costs a draw call per species.
##
## The meshes are deliberately plain: a trunk and stacked cones for a conifer, a squashed sphere
## for a shrub. This is vegetation tier 1, which exists so that the money shots have something to
## break the sun on; the detail arrives with the material work.

const CONIFER_ID: int = 0
const SHRUB_ID: int = 1


## Builds every species as one node, or null when nothing grew.
static func build() -> Node3D:
    var placements: Dictionary = place()
    var root: Node3D = Node3D.new()
    root.name = "Vegetation"
    var conifers: Array[Transform3D] = placements[CONIFER_ID] as Array[Transform3D]
    var shrubs: Array[Transform3D] = placements[SHRUB_ID] as Array[Transform3D]
    if conifers.is_empty() and shrubs.is_empty():
        return null
    if not conifers.is_empty():
        root.add_child(_instance(
            "Conifers", _conifer_mesh(), conifers,
            VegetationCfg.CONIFER_CASTS_SHADOW, VegetationCfg.CONIFER_VISIBLE_M
        ))
    if not shrubs.is_empty():
        root.add_child(_instance(
            "Shrubs", _shrub_mesh(), shrubs,
            VegetationCfg.SHRUB_CASTS_SHADOW, VegetationCfg.SHRUB_VISIBLE_M
        ))
    return root


## Every plant in the valley, as {species id: Array[Transform3D]}.
##
## Walks the whole map on the placement grid. The rules are checked in the order they are cheapest
## to fail, because this is 50,000 cells of GDScript and most of them are rejected.
static func place() -> Dictionary:
    var conifers: Array[Transform3D] = []
    var shrubs: Array[Transform3D] = []
    var half: float = 0.5 * float(TerrainCfg.MAP_SIZE) * TerrainCfg.VERTEX_SPACING
    var cell: float = VegetationCfg.CELL_M
    var columns: int = int(2.0 * half / cell)
    for column: int in columns:
        var x: float = -half + (float(column) + 0.5) * cell
        for row: int in columns:
            var z: float = -half + (float(row) + 0.5) * cell
            var species: int = species_at(x, z)
            if species < 0:
                continue
            var pose: Transform3D = pose_at(x, z, species)
            if species == CONIFER_ID:
                conifers.append(pose)
            else:
                shrubs.append(pose)
    return {CONIFER_ID: conifers, SHRUB_ID: shrubs}


## Where the plant in a cell actually stands, on the x/z plane.
##
## Jittered off the cell centre, so that a forest does not read as a lattice. The jitter does not
## depend on the species, which is what lets the rules be applied here rather than at the centre:
## a tree rejected for being too close to the road has to be rejected where it *stands*, and the
## jitter is up to half a cell.
static func position_at(x: float, z: float) -> Vector2:
    var reach: float = VegetationCfg.CELL_M * 0.8
    return Vector2(x, z) + Vector2(
        (_hash01(x, z, 4) - 0.5) * reach, (_hash01(x, z, 5) - 0.5) * reach
    )


## Which species grows in the cell containing a point, or -1 for bare ground.
##
## Pure, so a gate can ask the same question of an instance it found in the scene and get the same
## answer. The cell's own centre is what is hashed, not the point, so everything inside a cell
## agrees about what is in it; the rules are then applied where the plant stands.
static func species_at(x: float, z: float) -> int:
    var at: Vector2 = position_at(x, z)
    if absf(at.y) < VegetationCfg.MIN_ABS_Z_M:
        return -1
    var surface: String = GroundModels.name_of(ValleyShape.surface_at_world(at.x, at.y))
    if not VegetationCfg.SURFACES.has(surface):
        return -1
    if ValleyShape.road_distance(at.x, at.y) <= VegetationCfg.ROAD_CLEARANCE_M:
        return -1
    var ground: float = ValleyShape.height_at_world(at.x, at.y)
    if ground < ValleyShape.lake_water_y() + VegetationCfg.SHORE_CLEARANCE_M:
        return -1
    if slope_at(at.x, at.y) > VegetationCfg.MAX_SLOPE:
        return -1
    var roll: float = _hash01(x, z, 1)
    # Thinning out toward the valley floor rather than stopping at a line.
    var edge: float = ValleyShape.ramp(
        absf(at.y) - VegetationCfg.MIN_ABS_Z_M, VegetationCfg.EDGE_FADE_M
    )
    var conifer_chance: float = float(VegetationCfg.CONIFER["chance"]) * edge
    var shrub_chance: float = float(VegetationCfg.SHRUB["chance"]) * edge
    if _in_stand(at.x, at.y) > 0.0:
        var stand: float = _in_stand(at.x, at.y)
        conifer_chance = lerpf(
            conifer_chance, float(VegetationCfg.CONIFER["stand_chance"]) * edge, stand
        )
        shrub_chance = lerpf(
            shrub_chance, float(VegetationCfg.SHRUB["stand_chance"]) * edge, stand
        )
    # Above the tree line the wall is bare rock and only shrubs hold on.
    if _above_tree_line(at.y):
        conifer_chance = 0.0
    if roll < conifer_chance:
        return CONIFER_ID
    if roll < conifer_chance + shrub_chance:
        return SHRUB_ID
    return -1


## Where one plant stands, how big it is and which way it faces.
static func pose_at(x: float, z: float, species: int) -> Transform3D:
    var traits: Dictionary = VegetationCfg.CONIFER if species == CONIFER_ID else VegetationCfg.SHRUB
    var spread: float = float(traits["height_spread"])
    var scale: float = 1.0 + spread * (_hash01(x, z, 2) * 2.0 - 1.0)
    var basis: Basis = Basis(Vector3.UP, _hash01(x, z, 3) * TAU).scaled(Vector3.ONE * scale)
    var at: Vector2 = position_at(x, z)
    return Transform3D(basis, Vector3(at.x, ValleyShape.height_at_world(at.x, at.y), at.y))


## How steep the ground is at a point, as a gradient.
static func slope_at(x: float, z: float) -> float:
    var step: float = 2.0
    var here: float = ValleyShape.height_at_world(x, z)
    var along: float = ValleyShape.height_at_world(x + step, z) - here
    var across: float = ValleyShape.height_at_world(x, z + step) - here
    return Vector2(along, across).length() / step


## --------------------------------------------------------------------------------


## How much of the conifer stand a point is in: one inside, zero outside, ramped at the edge.
static func _in_stand(x: float, z: float) -> float:
    var edge: float = VegetationCfg.CELL_M + ValleyLayout.STAND_EDGE_M
    var inside_x: float = minf(
        x - (ValleyLayout.STAND_WEST_M - edge), (ValleyLayout.STAND_EAST_M + edge) - x
    )
    var inside_z: float = minf(
        z - (ValleyLayout.STAND_FAR_Z_M - edge), (ValleyLayout.STAND_NEAR_Z_M + edge) - z
    )
    if inside_x <= 0.0 or inside_z <= 0.0:
        return 0.0
    return minf(
        ValleyShape.ramp(inside_x, ValleyLayout.STAND_EDGE_M),
        ValleyShape.ramp(inside_z, ValleyLayout.STAND_EDGE_M)
    )


## Whether a point is above the altitude where the wall turns to bare rock.
static func _above_tree_line(z: float) -> bool:
    var across: float = absf(z)
    var line: float = (
        ValleyLayout.SHOULDER_END_M
        + (ValleyLayout.WALL_END_M - ValleyLayout.SHOULDER_END_M) * VegetationCfg.TREE_LINE
    )
    return across > line


## A stable 0-to-1 value for a cell and a purpose. Hashed from the cell's integer coordinates, so
## it is the same on every machine and in every run, and `no_global_random` stays satisfied.
static func _hash01(x: float, z: float, purpose: int) -> float:
    var cell: float = VegetationCfg.CELL_M
    var column: int = int(floor(x / cell))
    var row: int = int(floor(z / cell))
    var mixed: int = (column * 73856093) ^ (row * 19349663) ^ (purpose * 83492791)
    mixed = (mixed ^ VegetationCfg.HASH_SALT) & 0x7FFFFFFF
    mixed = (mixed * 1103515245 + 12345) & 0x7FFFFFFF
    return float(mixed % 100000) / 100000.0


static func _instance(
    name: String, mesh: Mesh, poses: Array[Transform3D], shadows: bool, visible_m: float
) -> MultiMeshInstance3D:
    var multimesh: MultiMesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = poses.size()
    for index: int in poses.size():
        multimesh.set_instance_transform(index, poses[index])
    var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
    instance.name = name
    instance.multimesh = multimesh
    instance.cast_shadow = (
        GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows
        else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    )
    instance.visibility_range_end = visible_m
    instance.visibility_range_end_margin = visible_m * 0.1
    return instance


## A conifer: a trunk with stacked cones on it, each narrower and shorter than the one below.
static func _conifer_mesh() -> ArrayMesh:
    var traits: Dictionary = VegetationCfg.CONIFER
    var height: float = float(traits["height_m"])
    var radius: float = float(traits["radius_m"])
    var tiers: int = int(traits["tiers"])
    var tool: SurfaceTool = SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_color(traits["trunk"] as Color)
    _add_cylinder(tool, float(traits["trunk_radius_m"]), height * 0.32, 6)
    tool.set_color(traits["foliage"] as Color)
    for tier: int in tiers:
        var share: float = float(tier) / float(tiers)
        _add_cone(
            tool,
            radius * (1.0 - share * 0.55),
            height * (0.24 + share * 0.10),
            height * (0.12 + share * 0.30),
            9
        )
    var mesh: ArrayMesh = tool.commit()
    mesh.surface_set_material(0, _foliage_material())
    return mesh


## A shrub: a squashed dome, which is all a metre-high plant is from any distance that matters.
static func _shrub_mesh() -> ArrayMesh:
    var traits: Dictionary = VegetationCfg.SHRUB
    var tool: SurfaceTool = SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_color(traits["foliage"] as Color)
    _add_cone(tool, float(traits["radius_m"]), float(traits["height_m"]), 0.0, 7)
    var mesh: ArrayMesh = tool.commit()
    mesh.surface_set_material(0, _foliage_material())
    return mesh


## One material for everything that grows: vertex colour carries the difference between bark and
## needles, so a whole conifer is one surface and one draw call per species stays true.
static func _foliage_material() -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.vertex_color_use_as_albedo = true
    material.roughness = 0.92
    material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
    # Both sides, because a cone seen from inside is what a camera under a tree sees.
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material


static func _add_cone(
    tool: SurfaceTool, radius: float, height: float, base_y: float, segments: int
) -> void:
    for segment: int in segments:
        var from: float = float(segment) / float(segments) * TAU
        var to: float = float(segment + 1) / float(segments) * TAU
        var a: Vector3 = Vector3(cos(from) * radius, base_y, sin(from) * radius)
        var b: Vector3 = Vector3(cos(to) * radius, base_y, sin(to) * radius)
        var tip: Vector3 = Vector3(0.0, base_y + height, 0.0)
        _add_triangle(tool, a, b, tip)
        _add_triangle(tool, b, a, Vector3(0.0, base_y, 0.0))


static func _add_cylinder(tool: SurfaceTool, radius: float, height: float, segments: int) -> void:
    for segment: int in segments:
        var from: float = float(segment) / float(segments) * TAU
        var to: float = float(segment + 1) / float(segments) * TAU
        var bottom_a: Vector3 = Vector3(cos(from) * radius, 0.0, sin(from) * radius)
        var bottom_b: Vector3 = Vector3(cos(to) * radius, 0.0, sin(to) * radius)
        var top_a: Vector3 = bottom_a + Vector3.UP * height
        var top_b: Vector3 = bottom_b + Vector3.UP * height
        _add_triangle(tool, bottom_a, bottom_b, top_b)
        _add_triangle(tool, bottom_a, top_b, top_a)


static func _add_triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
    var normal: Vector3 = (b - a).cross(c - a).normalized()
    for vertex: Vector3 in [a, b, c]:
        tool.set_normal(normal)
        tool.add_vertex(vertex)
