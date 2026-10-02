class_name RorVegetation
extends Node3D
## Grows a loaded terrain's own vegetation, in tiles around whoever is looking at it.
##
## A terrain's vegetation is a density and a density map: La Paz asks for 1.5 plants per square
## metre over 16 square kilometres, which is twenty-four million plants. Upstream draws them with
## paged geometry — a ring of tiles around the camera, built and dropped as it moves — and this is
## the same idea with a MultiMesh per tile.
##
## What grows where is decided by the terrain's own density map and by a hash of the position, so
## a tile built twice is identical and no run differs from another. There is no RNG anywhere in
## this project's world building for that reason.
##
## Grass is drawn as crossed quads, which is upstream's own default technique: two vertical cards
## through the same point, so a plant reads from any angle without facing the camera.

## How big a tile is, and how many rings of them are kept around the focus.
const TILE_M: float = 32.0
## How far vegetation is drawn by default, whatever the terrain asks for. La Paz asks for 300 m,
## which at its own density is two million plants in view. A session can move this — the panel's
## "Grass distance" — and pay for it.
const MAX_RANGE_M: float = 220.0
## The last stretch of that distance is faded rather than cut, so the ring's edge is a haze
## rather than a wall of grass appearing as the driver arrives.
const FADE_M: float = 40.0
## The most plants one tile may hold, so a density map's brightest corner cannot stall a frame.
const MAX_PER_TILE: int = 4000
## How far the focus moves before the ring is worked out again.
const REBUILD_AFTER_M: float = TILE_M * 0.5
## How many tiles may be built in one call. A full ring is sixty-odd tiles and several thousand
## plants; built in one frame that is a visible hitch every time the driver crosses a tile, so
## the ring fills in over the following frames instead.
const TILES_PER_CALL: int = 6
## Placement hash, the same shape the valley's trees use: position in, one deterministic number
## out, no RNG.
const HASH_SALT: int = 0x9E3779B9
## How a plant is built and lit.
const FOLIAGE_SHADER: String = "res://game/shaders/foliage.gdshader"
const CARDS_PER_PLANT: int = 3
const SWAY_M: float = 0.10
const SWAY_SPEED: float = 1.4
## How much a plant's colour varies from its neighbours. A field of one colour is half of what
## reads as fake, and the variation is hashed from the position like everything else here.
const TINT_VARIATION: float = 0.18

var _terrain: RorTerrain = null
var _layers: Array[Dictionary] = []
var _meshes: Array[Mesh] = []
var _tiles: Dictionary = {}
var _range_limit_m: float = MAX_RANGE_M
var _focus: Vector3 = Vector3(INF, 0.0, INF)
## The ring the focus asks for, which may still be filling in.
var _wanted: Dictionary = {}


## Grows a terrain's vegetation. Returns "" when there is something to grow, or a reason there is
## not — a terrain with no vegetation lines is not a fault.
## The sway phase every plant is drawn at, or negative to sway with the wall clock.
##
## A window wants the wall clock; anything that captures a frame and measures it wants a number,
## because a frame that animates with wall-clock time is a different frame every time it is
## taken. Set it before `setup`.
var wind_phase: float = -1.0


func setup(terrain: RorTerrain) -> String:
    _terrain = terrain
    name = "RorVegetation"
    var dds: RefCounted = ClassDB.instantiate("DdsReader") as RefCounted
    var materials: Dictionary = OgreMaterial.read_directory(terrain.directory)
    for line: Dictionary in _grass_lines(terrain):
        var layer: Dictionary = GrassLayer.read(line)
        layer["density_image"] = _image(terrain, layer["density_map"] as String)
        _layers.append(layer)
        _meshes.append(_card(terrain, layer, materials, dds))
    if _layers.is_empty():
        return "the terrain asks for no vegetation"
    return ""


## Builds the tiles around a point, dropping the ones that are now out of range. Called with the
## camera or the vehicle; cheap when nothing has moved far.
func focus_on(at: Vector3) -> void:
    if _layers.is_empty():
        return
    if Vector2(at.x - _focus.x, at.z - _focus.z).length() >= REBUILD_AFTER_M:
        _focus = at
        _wanted = _ring(at)
        for key: Vector2i in _tiles.keys():
            if _wanted.has(key):
                continue
            var node: Node = _tiles[key] as Node
            if node != null:
                node.queue_free()
            _tiles.erase(key)
    var built: int = 0
    for key: Vector2i in _wanted.keys():
        if _tiles.has(key):
            continue
        _build_tile(key)
        built += 1
        if built >= TILES_PER_CALL:
            return


## Fills the whole ring at once, however many tiles that is. What a gate and a photograph want:
## nobody is waiting for frames.
func fill() -> void:
    if _layers.is_empty():
        return
    for key: Vector2i in _wanted.keys():
        if not _tiles.has(key):
            _build_tile(key)


## Which tiles a focus asks for.
func _ring(at: Vector3) -> Dictionary:
    var range_m: float = minf(_range_m(), _range_limit_m)
    var tiles: int = int(ceil(range_m / TILE_M))
    var centre: Vector2i = Vector2i(int(floor(at.x / TILE_M)), int(floor(at.z / TILE_M)))
    var out: Dictionary = {}
    for dz: int in range(-tiles, tiles + 1):
        for dx: int in range(-tiles, tiles + 1):
            if Vector2(float(dx), float(dz)).length() > float(tiles):
                continue
            out[centre + Vector2i(dx, dz)] = true
    return out


## How far vegetation is drawn now, and a way to change it while a session runs.
## Takes every tile down. A session changing maps keeps the vegetation object and refills it from
## the new terrain, because the layers, the ranges and the budget belong to the session rather
## than to the map it happens to be showing.
func clear() -> void:
    for key: Vector2i in _tiles.keys():
        var node: Node = _tiles[key] as Node
        if node != null and is_instance_valid(node):
            node.queue_free()
    _tiles.clear()


func range_m() -> float:
    return minf(_range_m(), _range_limit_m)


func set_range(metres: float) -> void:
    _range_limit_m = maxf(metres, 0.0)
    # Force the ring to be worked out again from where the focus already is.
    var focus: Vector3 = _focus
    _focus = Vector3(INF, 0.0, INF)
    if is_finite(focus.x):
        focus_on(focus)


## How many plants are standing, which is what a gate counts.
func planted() -> int:
    var total: int = 0
    for key: Vector2i in _tiles.keys():
        for child: Node in (_tiles[key] as Node).get_children():
            var instance: MultiMeshInstance3D = child as MultiMeshInstance3D
            if instance != null and instance.multimesh != null:
                total += instance.multimesh.instance_count
    return total


## The layers this terrain asked for, as read.
func layers() -> Array[Dictionary]:
    return _layers


## --- Tiles ------------------------------------------------------------------------------------


func _build_tile(key: Vector2i) -> void:
    var tile: Node3D = Node3D.new()
    tile.name = "Tile%d_%d" % [key.x, key.y]
    for index: int in _layers.size():
        var instance: MultiMeshInstance3D = _tile_layer(key, index)
        if instance != null:
            tile.add_child(instance)
    add_child(tile)
    _tiles[key] = tile


## One layer's plants in one tile, as a MultiMesh.
func _tile_layer(key: Vector2i, index: int) -> MultiMeshInstance3D:
    var layer: Dictionary = _layers[index]
    var mesh: Mesh = _meshes[index]
    if mesh == null:
        return null
    var transforms: Array[Transform3D] = _plants(key, layer)
    if transforms.is_empty():
        return null
    var multimesh: MultiMesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.use_colors = true
    multimesh.mesh = mesh
    multimesh.instance_count = transforms.size()
    for at: int in transforms.size():
        multimesh.set_instance_transform(at, transforms[at])
        # A little lighter or darker than its neighbours, hashed from where it stands.
        var shade: float = 1.0 - TINT_VARIATION * 0.5 + TINT_VARIATION * _unit(
            _hash(Vector2(transforms[at].origin.x, transforms[at].origin.z)), 5
        )
        multimesh.set_instance_color(at, Color(shade, shade, shade, 1.0))
    var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
    instance.multimesh = multimesh
    # Vegetation casts shadows: a bush with no shadow sits on the ground like a sticker, which
    # is most of what makes a card of grass look like a card of grass.
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
    # And fades out at the edge of the ring rather than being cut off there.
    instance.visibility_range_end = range_m()
    instance.visibility_range_end_margin = FADE_M
    instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
    return instance


## Where one layer's plants stand in one tile: a grid of candidate points, each kept or dropped
## by the terrain's own density map, each jittered and sized by a hash of where it is.
func _plants(key: Vector2i, layer: Dictionary) -> Array[Transform3D]:
    var out: Array[Transform3D] = []
    var density: float = maxf(layer["density"] as float, 0.0)
    if density <= 0.0:
        return out
    # One candidate per square metre at most: beyond that a lawn is a wall of cards.
    var step: float = maxf(1.0 / sqrt(maxf(density, 0.05)), 0.5)
    var origin: Vector2 = Vector2(float(key.x), float(key.y)) * TILE_M
    var across: int = int(TILE_M / step)
    for iz: int in across:
        for ix: int in across:
            if out.size() >= MAX_PER_TILE:
                return out
            var at: Vector2 = origin + Vector2(float(ix) + 0.5, float(iz) + 0.5) * step
            var hash_value: int = _hash(at)
            var jitter: Vector2 = Vector2(
                _unit(hash_value, 0) - 0.5, _unit(hash_value, 1) - 0.5
            ) * step
            var point: Vector2 = at + jitter
            if _unit(hash_value, 2) > _density_at(layer, point):
                continue
            var height: float = _terrain.height_at_world(point.x, point.y)
            if not GrassLayer.grows_at(layer, height):
                continue
            var size: Vector2 = (layer["min_size"] as Vector2).lerp(
                layer["max_size"] as Vector2, _unit(hash_value, 3)
            )
            var basis: Basis = Basis(Vector3.UP, _unit(hash_value, 4) * TAU)
            out.append(Transform3D(
                basis.scaled(Vector3(size.x, size.y, size.x)),
                Vector3(point.x, height, point.y)
            ))
    return out


## What share of the stated density grows at a point, from the terrain's own density map.
func _density_at(layer: Dictionary, at: Vector2) -> float:
    var image: Image = layer["density_image"] as Image
    if image == null:
        return 1.0
    var span_x: float = _terrain.geometry["world_x"] as float
    var span_z: float = _terrain.geometry["world_z"] as float
    if at.x < 0.0 or at.y < 0.0 or at.x > span_x or at.y > span_z:
        return 0.0
    var x: int = clampi(int(at.x / span_x * float(image.get_width())), 0, image.get_width() - 1)
    var y: int = clampi(int(at.y / span_z * float(image.get_height())), 0, image.get_height() - 1)
    return image.get_pixel(x, y).r


## --- The plant itself ---------------------------------------------------------------------------


## One plant, as crossed quads a metre square, scaled per instance.
##
## Three quads rather than upstream's two: the third costs almost nothing in a MultiMesh and
## takes the silhouette from a cross to something with a mass to it, which is most of what stops
## a plant flickering between two flat cards as the camera goes round it.
##
## The material is `shaders/foliage.gdshader` — rounded normals, translucency, wind and
## alpha-to-coverage — because a card with a flat normal and a hard alpha cut is what reads as
## flat and outdated however good the texture is.
func _card(
    terrain: RorTerrain, layer: Dictionary, materials: Dictionary, dds: RefCounted
) -> Mesh:
    var material: ShaderMaterial = _foliage_material(terrain, layer, materials, dds)
    var mesh: ArrayMesh = ArrayMesh.new()
    var vertices: PackedVector3Array = PackedVector3Array()
    var normals: PackedVector3Array = PackedVector3Array()
    var uvs: PackedVector2Array = PackedVector2Array()
    var indices: PackedInt32Array = PackedInt32Array()
    for card: int in CARDS_PER_PLANT:
        var turn: float = PI * float(card) / float(CARDS_PER_PLANT)
        var along: Vector3 = Vector3(cos(turn), 0.0, sin(turn)) * 0.5
        var face: Vector3 = Vector3(-sin(turn), 0.0, cos(turn))
        var base: int = vertices.size()
        vertices.append_array([
            -along, along, along + Vector3.UP, -along + Vector3.UP,
        ])
        for _corner: int in 4:
            normals.append(face)
        uvs.append_array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
        indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_INDEX] = indices
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    mesh.surface_set_material(0, material)
    return mesh


## The foliage material for one layer, wearing the terrain's own texture.
func _foliage_material(
    terrain: RorTerrain, layer: Dictionary, materials: Dictionary, dds: RefCounted
) -> ShaderMaterial:
    var material: ShaderMaterial = ShaderMaterial.new()
    material.shader = load(FOLIAGE_SHADER) as Shader
    var declared: Dictionary = materials.get(layer["material"] as String, {}) as Dictionary
    if not declared.is_empty():
        var files: PackedStringArray = declared["textures"] as PackedStringArray
        if files.size() > 0:
            var texture: Texture2D = RorTerrainSkin.texture_of(
                terrain.directory.path_join(files[0]), dds
            )
            if texture != null:
                material.set_shader_parameter("albedo_texture", texture)
    material.set_shader_parameter("sway_m", SWAY_M)
    material.set_shader_parameter("sway_speed", SWAY_SPEED)
    material.set_shader_parameter("wind_phase", wind_phase)
    return material


## --- Reading ------------------------------------------------------------------------------------


func _grass_lines(terrain: RorTerrain) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for file: String in terrain.config["objects"] as PackedStringArray:
        var parsed: Dictionary = Tobj.read(terrain.directory.path_join(file))
        out.append_array(parsed["grass"] as Array[Dictionary])
    return out


func _image(terrain: RorTerrain, file: String) -> Image:
    if file.is_empty():
        return null
    return RorTerrainSkin.image_of(
        terrain.directory.path_join(file), ClassDB.instantiate("DdsReader") as RefCounted
    )


func _range_m() -> float:
    var out: float = 0.0
    for layer: Dictionary in _layers:
        out = maxf(out, layer["range_m"] as float)
    return out


## A hash of a position: the same point always gives the same number, and no run differs.
func _hash(at: Vector2) -> int:
    var x: int = int(floor(at.x * 16.0))
    var z: int = int(floor(at.y * 16.0))
    var value: int = (x * 73856093) ^ (z * 19349663) ^ HASH_SALT
    value = (value ^ (value >> 13)) * 1274126177
    return value & 0x7FFFFFFF


## One of several independent numbers in 0..1 from the same hash.
func _unit(hash_value: int, index: int) -> float:
    var mixed: int = (hash_value * (index * 2 + 1) + index * 374761393) & 0x7FFFFFFF
    mixed = (mixed ^ (mixed >> 15)) & 0x7FFFFFFF
    return float(mixed % 65536) / 65536.0
