class_name CabBody
extends RefCounted
## Builds the body panels a vehicle draws from its own nodes.
##
## A `submesh` group is geometry with no mesh file behind it: its vertices **are** nodes, its
## triangles are `cab` lines over them, and its texture coordinates come from `texcoords` lines.
## Upstream builds a `FlexObj` per group and draws it with the material the `globals` line names.
##
## Nothing here is rigid. A panel deforms with the truck because its vertices are the truck, so it
## goes through the same skinning path a flexbody does — one bone per locator triad, every vertex
## bound to the triad around the node it sits on. That it lands on a node exactly is what makes
## the binding trivial: the vertex is the node, so the triad it binds to is the one that holds it.
##
## **`backmesh` means both sides.** Upstream draws a second copy of the group with its winding
## reversed, because a panel is a single sheet and a truck is looked at from inside as well as
## outside. Drawn one-sided, the Daf trailers' walls vanish from within the load bed. The reversed
## copy is a second surface on the same mesh rather than a second instance, so it costs one draw
## call and deforms with the first.

## A group with fewer coordinates than this cannot describe a panel.
const MIN_TEXCOORDS: int = 3


## Builds every drawable group of `truck` under `root`. Returns the parts, which the caller poses.
static func build(
    root: Node3D,
    truck: TruckParser,
    actor: Transform3D,
    mod_dir: String,
    dds_reader: RefCounted,
    textures: Dictionary,
    scripts: Dictionary
) -> Array[SkinnedFlexbody]:
    var out: Array[SkinnedFlexbody] = []
    var material: Material = MeshAssembler.material_for(
        truck.cab_material, truck, mod_dir, dds_reader, textures, scripts
    )
    for index: int in truck.submeshes.groups.size():
        var part: SkinnedFlexbody = _build_group(
            root, truck, truck.submeshes.groups[index], material, actor, index
        )
        if part != null:
            out.append(part)
    return out


## One group, or null when it describes nothing drawable.
static func _build_group(
    root: Node3D,
    truck: TruckParser,
    group: Dictionary,
    material: Material,
    actor: Transform3D,
    index: int
) -> SkinnedFlexbody:
    var uv_of: Dictionary = {}
    var nodes: PackedInt32Array = group["nodes"] as PackedInt32Array
    var uvs: PackedVector2Array = group["uvs"] as PackedVector2Array
    for i: int in mini(nodes.size(), uvs.size()):
        uv_of[nodes[i]] = uvs[i]
    if uv_of.size() < MIN_TEXCOORDS:
        # The hero truck and the Mazda declare cab triangles and no coordinates at all. There is
        # nothing to draw such a panel with, and upstream does not draw one either.
        return null
    var triangles: PackedInt32Array = group["triangles"] as PackedInt32Array
    if triangles.size() < 3:
        return null

    # One vertex per node the group uses, so a node carrying different coordinates in two groups
    # keeps both.
    var vertex_of: Dictionary = {}
    var vertices: PackedVector3Array = PackedVector3Array()
    var vertex_uvs: PackedVector2Array = PackedVector2Array()
    var used: PackedInt32Array = PackedInt32Array()
    var indices: PackedInt32Array = PackedInt32Array()
    for node: int in triangles:
        if node < 0 or node >= truck.nodes.size() or not uv_of.has(node):
            # A triangle over a node with no coordinates cannot be textured, and half a panel is
            # worse than none.
            return null
        if not vertex_of.has(node):
            vertex_of[node] = vertices.size()
            vertices.append(truck.nodes[node])
            vertex_uvs.append(uv_of[node] as Vector2)
            used.append(node)
        indices.append(vertex_of[node] as int)
    if vertices.size() < 3:
        return null
    # Upstream's cab winding is the reverse of what Godot draws front-facing, the same way a
    # mesh file's is -- see the note in `OgreMeshReader::read_submesh`.
    _reverse(indices)
    if group["backmesh"] as bool:
        indices.append_array(_reversed(indices))

    var part: SkinnedFlexbody = SkinnedFlexbody.new()
    var error: String = part.build(
        root, truck.nodes, used, vertices, indices, material, vertex_uvs,
        _normals(vertices, indices)
    )
    if error != "":
        return null
    part.mesh_instance.name = "Cab%d" % index
    part.set_pose(truck.nodes, actor, false)
    return part


## Flips every triangle's winding in place.
static func _reverse(indices: PackedInt32Array) -> void:
    for i: int in range(0, indices.size() - 2, 3):
        var swap: int = indices[i + 1]
        indices[i + 1] = indices[i + 2]
        indices[i + 2] = swap


## A reversed copy, for the back of a one-sided panel.
static func _reversed(indices: PackedInt32Array) -> PackedInt32Array:
    var out: PackedInt32Array = indices.duplicate()
    _reverse(out)
    return out


## Flat normals accumulated per vertex. A cab has none of its own: the file says which nodes make
## a triangle and nothing about which way it faces.
static func _normals(
    vertices: PackedVector3Array, indices: PackedInt32Array
) -> PackedVector3Array:
    var out: PackedVector3Array = PackedVector3Array()
    out.resize(vertices.size())
    for i: int in range(0, indices.size() - 2, 3):
        var a: Vector3 = vertices[indices[i]]
        var b: Vector3 = vertices[indices[i + 1]]
        var c: Vector3 = vertices[indices[i + 2]]
        var face: Vector3 = (b - a).cross(c - a)
        for corner: int in 3:
            out[indices[i + corner]] += face
    for i: int in out.size():
        out[i] = out[i].normalized() if out[i].length_squared() > 0.0 else Vector3.UP
    return out
