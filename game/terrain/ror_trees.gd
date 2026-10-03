class_name RorTrees
extends RefCounted
## The forests a terrain paints with a density map.
##
## A `trees` line names a mesh, a density map and a scatter: upstream walks a 10 m grid over the
## whole map, asks the density map how much grows at each cell, and drops that many trees inside
## it at a random yaw and scale (`TerrainObjectManager::ProcessTree`). A positive grid spacing
## means one tree per cell at its middle instead, where the density is over 0.8.
##
## **Russia asks for two fir species and got neither.** `trees` was not a keyword this project
## knew, so both lines went into the pile of lines nothing reads — six lines across the whole
## library, of which these two were the only ones that mattered. They come to 7045 trees each.
##
## **Nothing here is random.** A position decides its own tree: the same point always yields the
## same yaw and the same scale, so a terrain is identical on a second build and `no_global_random`
## has nothing to object to. The scatter within a cell is hashed from the cell and the tree's
## index in it.
##
## Batched per layer per tile, like a terrain's objects, and drawn out to the distance the line
## itself states — Russia says 800 m. A tile beyond that is culled by its own bounds.

## How big a batching tile is. Matches `RorObjects`, for the same reason: a whole map in one
## batch is one draw call that is never culled.
const TILE_M: float = 256.0
## Keeps the two species of a two-line terrain from landing on exactly the same spots.
const LAYER_SALT: int = 0x7F4A7C15
## Upstream plants one tree per cell above this density when a grid spacing is stated.
const REGULAR_DENSITY: float = 0.8
## How much of its stated distance a forest spends fading out.
const FADE: float = 0.1


## Every forest of a terrain, as one `MultiMeshInstance3D` per layer per tile.
static func build(terrain: RorTerrain) -> Node3D:
    var root: Node3D = Node3D.new()
    root.name = "RorTrees"
    var state: Dictionary = RorObjects.state(terrain)
    var dds: RefCounted = ClassDB.instantiate("DdsReader") as RefCounted
    var index: int = 0
    for line: Dictionary in lines(terrain):
        var layer: Dictionary = TreeLayer.read(line)
        index += 1
        if not TreeLayer.is_complete(layer):
            continue
        var mesh: ArrayMesh = RorObjects.mesh_of(terrain, layer["mesh"] as String, state)
        var density: Image = RorTerrainSkin.image_of(
            RorContentPath.find(layer["density_map"] as String, terrain.directory), dds
        )
        if mesh == null or density == null:
            continue
        var tiles: Dictionary = _tiles(terrain, layer, density, index)
        for key: Vector2i in tiles.keys():
            root.add_child(_batch(
                layer, mesh, key, tiles[key] as Array[Transform3D], index
            ))
    return root


## What a terrain's forests come to, counted rather than built.
static func summary(terrain: RorTerrain) -> Dictionary:
    var state: Dictionary = RorObjects.state(terrain)
    var dds: RefCounted = ClassDB.instantiate("DdsReader") as RefCounted
    var layers: int = 0
    var trees: int = 0
    var without: int = 0
    var index: int = 0
    for line: Dictionary in lines(terrain):
        var layer: Dictionary = TreeLayer.read(line)
        index += 1
        var density: Image = null
        if TreeLayer.is_complete(layer):
            density = RorTerrainSkin.image_of(
                RorContentPath.find(layer["density_map"] as String, terrain.directory), dds
            )
        if density == null or RorObjects.mesh_of(terrain, layer["mesh"] as String, state) == null:
            without += 1
            continue
        layers += 1
        for placed: Array[Transform3D] in _tiles(terrain, layer, density, index).values():
            trees += placed.size()
    return {"layers": layers, "trees": trees, "incomplete": without}


## The `trees` lines of a terrain's object files.
static func lines(terrain: RorTerrain) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for file: String in terrain.config["objects"] as PackedStringArray:
        var parsed: Dictionary = Tobj.read(terrain.directory.path_join(file))
        out.append_array(parsed["trees"] as Array[Dictionary])
    return out


## Where one layer's trees stand, grouped by tile.
static func _tiles(
    terrain: RorTerrain, layer: Dictionary, density: Image, salt: int
) -> Dictionary:
    var out: Dictionary = {}
    var span_x: float = terrain.geometry["world_x"] as float
    var span_z: float = terrain.geometry["world_z"] as float
    var grid: float = TreeLayer.grid_metres(layer)
    var regular: bool = TreeLayer.is_regular(layer)
    var high: float = layer["high_density"] as float
    var x: float = 0.0
    while x < span_x:
        var z: float = 0.0
        while z < span_z:
            var share: float = _density_at(density, x, z, span_x, span_z)
            var count: int = 1 if regular else int(high * share)
            if regular and share < REGULAR_DENSITY:
                count = 0
            for which: int in count:
                var at: Transform3D = _stand(terrain, layer, x, z, grid, which, salt, regular)
                var key: Vector2i = Vector2i(
                    int(floor(at.origin.x / TILE_M)), int(floor(at.origin.z / TILE_M))
                )
                if not out.has(key):
                    out[key] = ([] as Array[Transform3D])
                (out[key] as Array[Transform3D]).append(at)
            z += grid
        x += grid
    return out


## One tree, standing on the ground, turned and scaled by where it is.
static func _stand(
    terrain: RorTerrain, layer: Dictionary, x: float, z: float, grid: float,
    which: int, salt: int, regular: bool
) -> Transform3D:
    var seed_value: int = _hash(x, z, which * 7 + salt * LAYER_SALT)
    var at_x: float = x + grid * (0.5 if regular else _unit(seed_value, 1))
    var at_z: float = z + grid * (0.5 if regular else _unit(seed_value, 2))
    var yaw: float = lerpf(
        layer["yaw_from"] as float, layer["yaw_to"] as float, _unit(seed_value, 3)
    )
    var scale: float = lerpf(
        layer["scale_from"] as float, layer["scale_to"] as float, _unit(seed_value, 4)
    )
    var basis: Basis = Basis(Vector3.UP, deg_to_rad(yaw)).scaled(Vector3.ONE * scale)
    return Transform3D(
        basis, Vector3(at_x, terrain.height_at_world(at_x, at_z), at_z)
    )


## One tile of one layer, drawn out to the distance the line states.
static func _batch(
    layer: Dictionary, mesh: ArrayMesh, key: Vector2i, at: Array[Transform3D], index: int
) -> MultiMeshInstance3D:
    var multimesh: MultiMesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = at.size()
    for which: int in at.size():
        multimesh.set_instance_transform(which, at[which])
    var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
    node.name = "Trees%d_%d_%d" % [index, key.x, key.y]
    node.set_meta("mesh_file", layer["mesh"])
    node.multimesh = multimesh
    node.visibility_range_end = layer["max_distance"] as float
    node.visibility_range_end_margin = node.visibility_range_end * FADE
    if node.visibility_range_end > 0.0:
        node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
    return node


## How much of its stated density the map allows at a world position.
static func _density_at(
    image: Image, x: float, z: float, span_x: float, span_z: float
) -> float:
    var px: int = clampi(
        int(x / span_x * float(image.get_width())), 0, image.get_width() - 1
    )
    var pz: int = clampi(
        int(z / span_z * float(image.get_height())), 0, image.get_height() - 1
    )
    return image.get_pixel(px, pz).r


## A hash of a cell and an index: the same tree always comes out the same, and no run differs.
static func _hash(x: float, z: float, salt: int) -> int:
    var ix: int = int(floor(x * 16.0))
    var iz: int = int(floor(z * 16.0))
    var value: int = (ix * 73856093) ^ (iz * 19349663) ^ salt
    value = (value ^ (value >> 13)) * 1274126177
    return value & 0x7FFFFFFF


## One of several independent numbers in 0..1 from the same hash.
static func _unit(hash_value: int, index: int) -> float:
    var mixed: int = (hash_value * (index * 2 + 1) + index * 374761393) & 0x7FFFFFFF
    mixed = (mixed ^ (mixed >> 15)) & 0x7FFFFFFF
    return float(mixed % 65536) / 65536.0
