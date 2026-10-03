class_name RorProceduralRoad
extends RefCounted
## The roads a terrain describes as a line of points rather than as placed objects.
##
## A `begin_procedural_roads` block is a list of cross-sections: a position, a rotation, a
## carriageway width, and a border width and height. Upstream sweeps the cross-section along the
## line and builds one mesh out of it — `ProceduralRoad::addBlock`, `computePoints`, `addQuad` —
## drawn with the single material `road2`, whose texture is an atlas with a band for each part of
## the section. This project read the points as object placements and drew nothing: 374 of Port
## Starling's 1502 lines are road points, which is most of its road network.
##
## **Eight points make a cross-section**, in the point's own frame, and the road runs along its
## local x while the section spans its local z. Outer to outer:
##
##     0  the far shoulder's foot          4  the carriageway's right edge
##     1  the far shoulder's top           5  the near kerb's top
##     2  the near kerb's top (far side)   6  the near shoulder's top
##     3  the carriageway's left edge      7  the near shoulder's foot
##
## Where a shoulder's foot is depends on the ground: `baseOf` puts it on the heightmap, or just
## under the road where the road is already below ground, so a road laid over a dip closes itself
## against the terrain instead of floating.
##
## **What is built here and what is not.** Flat, left-kerbed, right-kerbed and both-kerbed roads
## are built. `bridge` and `monorail` carry pillars, an underside and their own wall fits, and are
## left for the work that does them properly — they are counted and reported rather than drawn
## wrong. `automatic` is resolved the way upstream resolves it, by asking the terrain how far the
## ground falls away either side.

## The road material. One for the whole mesh, with the section's parts cut from bands of it.
const MATERIAL: String = "road2"
## Upstream's own bands of that atlas, as `TEXFIT_*` in `ProceduralRoad::textureFit`.
const BAND_ROAD: Vector2 = Vector2(0.072, 0.423)
const BAND_SIDE_FAR_LEFT: Vector2 = Vector2(0.001, 0.036)
const BAND_SIDE_LEFT: Vector2 = Vector2(0.036, 0.072)
const BAND_SIDE_RIGHT: Vector2 = Vector2(0.423, 0.458)
const BAND_SIDE_FAR_RIGHT: Vector2 = Vector2(0.458, 0.493)
## A wall's coordinates come from its height rather than from a band.
const WALL_V: float = 0.746
const WALL_SCALE: float = 0.25 / 4.5
## How many metres of road one repeat of the atlas covers along the way.
const METRES_PER_REPEAT: float = 10.0
## What `automatic` compares the drop either side against, from `ProceduralRoad::addBlock`.
const AUTOMATIC_WIDTH_M: float = 10.0
const AUTOMATIC_BORDER_W_M: float = 1.4
const AUTOMATIC_BORDER_H_M: float = 0.2
const AUTOMATIC_MAX_DROP_M: float = 4.0
## How far under the ground a shoulder's foot is sunk, so it never z-fights the terrain.
const FOOT_SINK_M: float = 0.01
## The kinds this builds. Everything else is reported.
const BUILT_KINDS: Array[String] = ["flat", "left", "right", "both", "automatic"]


## Every procedural road of a terrain, as one `MeshInstance3D` per block. Null children are not
## produced: a block with fewer than two points describes no road.
static func build(terrain: RorTerrain, material: Material = null) -> Node3D:
    var root: Node3D = Node3D.new()
    root.name = "RorProceduralRoads"
    var drawn: Material = material if material != null else _material(terrain)
    for group: Array[Dictionary] in groups(terrain):
        var mesh: ArrayMesh = _mesh(terrain, group, drawn)
        if mesh == null:
            continue
        var node: MeshInstance3D = MeshInstance3D.new()
        node.name = "Road%d" % root.get_child_count()
        node.mesh = mesh
        root.add_child(node)
    return root


## What a terrain's road points come to, counted rather than built: how many points, how many
## blocks, and how many of them this does not draw yet.
static func summary(terrain: RorTerrain) -> Dictionary:
    var points: int = 0
    var blocks: int = 0
    var unbuilt: Dictionary = {}
    for group: Array[Dictionary] in groups(terrain):
        blocks += 1
        points += group.size()
        for point: Dictionary in group:
            var kind: String = point["kind"] as String
            if not BUILT_KINDS.has(kind):
                unbuilt[kind] = (unbuilt.get(kind, 0) as int) + 1
    return {"points": points, "blocks": blocks, "unbuilt": unbuilt}


## The blocks, in the order the file states them. A point placed as an object stands alone.
static func groups(terrain: RorTerrain) -> Array[Array]:
    var by_group: Dictionary = {}
    var order: Array[int] = []
    var loose: int = -1
    for file: String in terrain.config["objects"] as PackedStringArray:
        var parsed: Dictionary = Tobj.read(terrain.directory.path_join(file))
        for point: Dictionary in parsed["roads"] as Array[Dictionary]:
            var key: int = point["group"] as int
            if key < 0:
                # An odef-placed road is its own one-point block and sweeps nothing.
                loose -= 1
                key = loose
            if not by_group.has(key):
                by_group[key] = ([] as Array[Dictionary])
                order.append(key)
            (by_group[key] as Array[Dictionary]).append(point)
    var out: Array[Array] = []
    for key: int in order:
        out.append(by_group[key] as Array[Dictionary])
    return out


## One block's mesh, or null when it describes nothing.
static func _mesh(
    terrain: RorTerrain, group: Array[Dictionary], material: Material
) -> ArrayMesh:
    if group.size() < 2:
        return null
    var vertices: PackedVector3Array = PackedVector3Array()
    var uvs: PackedVector2Array = PackedVector2Array()
    var indices: PackedInt32Array = PackedInt32Array()
    for index: int in range(1, group.size()):
        var here: Dictionary = resolved(terrain, group[index])
        var last: Dictionary = resolved(terrain, group[index - 1])
        if not BUILT_KINDS.has(here["kind"]) or not BUILT_KINDS.has(last["kind"]):
            continue
        _sweep(terrain, here, last, vertices, uvs, indices)
    if indices.is_empty():
        return null
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_NORMAL] = _normals(vertices, indices)
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh: ArrayMesh = ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    mesh.surface_set_material(0, material)
    return mesh


## The quads between two cross-sections: the carriageway, the kerbs either side of it, the
## shoulders beyond them, and the walls down to the ground.
static func _sweep(
    terrain: RorTerrain,
    here: Dictionary,
    last: Dictionary,
    vertices: PackedVector3Array,
    uvs: PackedVector2Array,
    indices: PackedInt32Array
) -> void:
    var a: PackedVector3Array = section(terrain, here)
    var b: PackedVector3Array = section(terrain, last)
    var at: Vector3 = here["position"] as Vector3
    var from: Vector3 = last["position"] as Vector3
    var flat: bool = (here["kind"] as String) == "flat" and (last["kind"] as String) == "flat"
    _quad(a[4], b[4], b[3], a[3], BAND_ROAD, at, from, vertices, uvs, indices)
    _quad(
        a[5], b[5], b[4], a[4],
        BAND_SIDE_RIGHT if flat else BAND_ROAD, at, from, vertices, uvs, indices
    )
    _quad(
        a[3], b[3], b[2], a[2],
        BAND_SIDE_LEFT if flat else BAND_ROAD, at, from, vertices, uvs, indices
    )
    _quad(
        a[6], b[6], b[5], a[5],
        BAND_SIDE_FAR_RIGHT if flat else BAND_ROAD, at, from, vertices, uvs, indices
    )
    _quad(
        a[2], b[2], b[1], a[1],
        BAND_SIDE_FAR_LEFT if flat else BAND_ROAD, at, from, vertices, uvs, indices
    )
    _wall(a[1], b[1], b[0], a[0], at, from, vertices, uvs, indices)
    _wall(b[6], a[6], a[7], b[7], at, from, vertices, uvs, indices)


## The eight points of one cross-section, in world space.
static func section(terrain: RorTerrain, point: Dictionary) -> PackedVector3Array:
    var at: Vector3 = point["position"] as Vector3
    var degrees: Vector3 = point["rotation"] as Vector3
    var basis: Basis = (
        Basis(Vector3.RIGHT, deg_to_rad(degrees.x))
        * Basis(Vector3.UP, deg_to_rad(degrees.y))
        * Basis(Vector3.BACK, deg_to_rad(degrees.z))
    )
    var width: float = point["width"] as float
    var bw: float = point["bwidth"] as float
    var bh: float = point["bheight"] as float
    var kind: String = point["kind"] as String
    # A kerb rises by its own height; a shoulder falls away by it. Which side does which is what
    # the kind names.
    var left_up: bool = kind == "both" or kind == "right"
    var right_up: bool = kind == "both" or kind == "left"
    var out: PackedVector3Array = PackedVector3Array()
    out.resize(8)
    out[1] = at + basis * Vector3(0.0, bh if left_up else -bh, bw + width * 0.5)
    out[2] = at + basis * Vector3(
        0.0, bh if left_up else -bh * 0.25,
        width * 0.5 if left_up else bw / 3.0 + width * 0.5
    )
    out[3] = at + basis * Vector3(0.0, 0.0, width * 0.5)
    out[4] = at + basis * Vector3(0.0, 0.0, -width * 0.5)
    out[5] = at + basis * Vector3(
        0.0, bh if right_up else -bh * 0.25,
        -width * 0.5 if right_up else -bw / 3.0 - width * 0.5
    )
    out[6] = at + basis * Vector3(0.0, bh if right_up else -bh, -bw - width * 0.5)
    out[0] = _foot(terrain, out[1])
    out[7] = _foot(terrain, out[6])
    return out


## Where a shoulder meets the ground: the heightmap, or just under the road where the road is
## already below it.
static func _foot(terrain: RorTerrain, p: Vector3) -> Vector3:
    var y: float = terrain.height_at_world(p.x, p.z) - FOOT_SINK_M
    if y > p.y:
        y = p.y - FOOT_SINK_M
    return Vector3(p.x, y, p.z)


## `automatic` resolved the way upstream resolves it: by how far the ground falls away either
## side of where the road would go.
static func resolved(terrain: RorTerrain, point: Dictionary) -> Dictionary:
    if (point["kind"] as String) != "automatic":
        return point
    var out: Dictionary = point.duplicate()
    out["width"] = AUTOMATIC_WIDTH_M
    out["bwidth"] = AUTOMATIC_BORDER_W_M
    out["bheight"] = AUTOMATIC_BORDER_H_M
    var at: Vector3 = point["position"] as Vector3
    var reach: float = AUTOMATIC_BORDER_W_M + AUTOMATIC_WIDTH_M * 0.5
    var left: float = at.y - terrain.height_at_world(at.x, at.z + reach)
    var right: float = at.y - terrain.height_at_world(at.x, at.z - reach)
    var lip: float = AUTOMATIC_BORDER_H_M + 0.1
    var left_clear: bool = left >= lip and left < AUTOMATIC_MAX_DROP_M
    var right_clear: bool = right >= lip and right < AUTOMATIC_MAX_DROP_M
    if left < lip and right < lip:
        out["kind"] = "flat"
    elif left < lip and right_clear:
        out["kind"] = "left"
    elif left_clear and right < lip:
        out["kind"] = "right"
    elif left_clear and right_clear:
        out["kind"] = "both"
    else:
        # Upstream builds a bridge here, which this does not build yet.
        out["kind"] = "bridge"
    return out


## One quad, with its coordinates taken from a band of the atlas along the way travelled.
static func _quad(
    p1: Vector3, p2: Vector3, p3: Vector3, p4: Vector3, band: Vector2,
    at: Vector3, from: Vector3,
    vertices: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array
) -> void:
    var along: Vector3 = from - at
    along.y = 0.0
    if along.length_squared() <= 0.0:
        return
    along = along.normalized()
    var base: int = vertices.size()
    var corners: Array[Vector3] = [p1, p2, p3, p4]
    for index: int in 4:
        var flat: Vector3 = corners[index] - at
        flat.y = 0.0
        vertices.append(corners[index])
        uvs.append(Vector2(
            along.dot(flat) / METRES_PER_REPEAT,
            band.x if index < 2 else band.y
        ))
    _triangles(base, indices)


## A wall, whose coordinates come from how high up it a corner is rather than from a band.
static func _wall(
    p1: Vector3, p2: Vector3, p3: Vector3, p4: Vector3, at: Vector3, from: Vector3,
    vertices: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array
) -> void:
    var along: Vector3 = from - at
    along.y = 0.0
    if along.length_squared() <= 0.0:
        return
    along = along.normalized()
    var base: int = vertices.size()
    for corner: Vector3 in [p1, p2, p3, p4] as Array[Vector3]:
        vertices.append(corner)
        uvs.append(Vector2(
            along.dot(Vector3(corner.x - at.x, 0.0, corner.z - at.z)) / METRES_PER_REPEAT,
            minf(WALL_V - (corner.y - at.y) * WALL_SCALE, 1.0)
        ))
    _triangles(base, indices)


## Two triangles over four corners, wound the way Godot draws a front face.
static func _triangles(base: int, indices: PackedInt32Array) -> void:
    indices.append_array(PackedInt32Array([
        base, base + 1, base + 2,
        base, base + 2, base + 3,
    ]))


## Flat normals accumulated per vertex.
static func _normals(
    vertices: PackedVector3Array, indices: PackedInt32Array
) -> PackedVector3Array:
    var out: PackedVector3Array = PackedVector3Array()
    out.resize(vertices.size())
    for i: int in range(0, indices.size() - 2, 3):
        var face: Vector3 = (
            vertices[indices[i + 1]] - vertices[indices[i]]
        ).cross(vertices[indices[i + 2]] - vertices[indices[i]])
        for corner: int in 3:
            out[indices[i + corner]] += face
    for i: int in out.size():
        out[i] = out[i].normalized() if out[i].length_squared() > 0.0 else Vector3.UP
    return out


## The road material, from the terrain's own scripts or the game's.
static func _material(terrain: RorTerrain) -> StandardMaterial3D:
    var out: StandardMaterial3D = StandardMaterial3D.new()
    out.albedo_color = Color(0.45, 0.45, 0.46)
    var declared: Dictionary = RorContentPath.materials(terrain.directory).get(
        MATERIAL, {}
    ) as Dictionary
    if declared.is_empty():
        return out
    var files: PackedStringArray = declared["textures"] as PackedStringArray
    if files.is_empty():
        return out
    var texture: Texture2D = RorTerrainSkin.texture_of(
        RorContentPath.find(files[0], terrain.directory),
        ClassDB.instantiate("DdsReader") as RefCounted
    )
    if texture != null:
        out.albedo_texture = texture
        out.albedo_color = Color.WHITE
    return out
