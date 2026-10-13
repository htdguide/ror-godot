class_name AirbrakeMesh
extends RefCounted
## Draws each air brake as upstream does (`Airbrake`'s constructor, `GfxActor::UpdateAirbrakes`): a
## width by length quad, both faces, in the cab's material at the row's texture coordinates,
## placed at its offset from the reference node in the frame of its x and y nodes, and turned
## about its x edge by the air brakes' step times its maximum angle.

const FACES: PackedInt32Array = [0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2]


## One drawn air brake per row, children of `root`; [] when the vehicle has none.
static func build(root: Node3D, truck: TruckParser, material: Material) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for row: Dictionary in truck.links.airbrakes:
        var w: float = row["width"]
        var l: float = row["length"]
        var t: PackedFloat32Array = row["tex"]
        var arrays: Array = []
        arrays.resize(Mesh.ARRAY_MAX)
        arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3(w, 0, 0), Vector3(w, 0, l), Vector3(0, 0, l)])
        arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
        arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(t[0], t[1]), Vector2(t[2], t[1]), Vector2(t[2], t[3]), Vector2(t[0], t[3])])
        arrays[Mesh.ARRAY_INDEX] = FACES
        var mesh: ArrayMesh = ArrayMesh.new()
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        var instance: MeshInstance3D = MeshInstance3D.new()
        instance.name = "Airbrake%d" % out.size()
        instance.mesh = mesh
        instance.material_override = material
        root.add_child(instance)
        out.append({"nodes": row["nodes"], "offset": row["offset"], "max_angle": row["max_angle"], "instance": instance})
    return out


## Each air brake placed from the nodes (world positions) and the air brakes' step (0 to 5).
static func apply(brakes: Array[Dictionary], nodes: PackedVector3Array, to_local: Transform3D, intensity: int) -> void:
    var ratio: float = PackedFloat32Array([float(intensity) / 5.0])[0]
    for brake: Dictionary in brakes:
        (brake["instance"] as Node3D).transform = to_local * frame(brake, nodes, ratio)


## Upstream's position and orientation: the normal from the y and x edges, the offset along those
## edges and the normal, the axes (x, normal, x cross normal) turned by `-ratio * max_angle` about x.
static func frame(brake: Dictionary, nodes: PackedVector3Array, ratio: float) -> Transform3D:
    var n: PackedInt32Array = brake["nodes"]
    var ref: Vector3 = nodes[n[0]]
    var x: Vector3 = nodes[n[1]] - ref
    var y: Vector3 = nodes[n[2]] - ref
    var normal: Vector3 = y.cross(x).normalized()
    var offset: Vector3 = brake["offset"]
    var position: Vector3 = ref + offset.x * x + offset.y * y + normal * offset.z
    var refx: Vector3 = x.normalized()
    var refy: Vector3 = refx.cross(normal)
    var turn: Basis = Basis(refx, deg_to_rad(-ratio * float(brake["max_angle"])))
    return Transform3D(turn * Basis(refx, normal, refy), position)
