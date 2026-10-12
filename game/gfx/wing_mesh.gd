class_name WingMesh
extends RefCounted
## Draws each wing as upstream's `FlexAirfoil` meshes it: 54 vertices placed at fractions of the
## panel's edges (`airfoilpos`) — a cambered section of five bands, its control surface hinged at
## the chord point and swung by its deflection, a stabilator turned whole — in the cab's material,
## the texture coordinates the row states. A broken wing collapses to a speck, as upstream's does.
##
## Upstream's `updateVerticesPhysics` and `updateVerticesGfx`, the triangle lists of its
## constructor, its per-triangle normals; the winding reversed, as the cab's is, for Godot's.

const REFAIRFOILPOS: Array[float] = [
    0.00, 0.50, 0.00, 1.00, 0.50, 0.00, 0.00, 0.70, 0.03, 1.00, 0.70, 0.03, 0.00, 0.30, 0.03,
    1.00, 0.30, 0.03, 0.00, 0.90, 0.10, 1.00, 0.90, 0.10, 0.00, 0.10, 0.10, 1.00, 0.10, 0.10,
    0.00, 1.00, 0.25, 1.00, 1.00, 0.25, 0.00, 0.00, 0.25, 1.00, 0.00, 0.25, 0.00, 1.00, 0.50,
    1.00, 1.00, 0.50, 0.00, 0.00, 0.50, 1.00, 0.00, 0.50, 0.00, 0.75, 0.75, 1.00, 0.75, 0.75,
    0.00, 0.25, 0.75, 1.00, 0.25, 0.75, 0.00, 0.75, 0.75, 1.00, 0.75, 0.75, 0.00, 0.25, 0.75,
    1.00, 0.25, 0.75, 0.00, 0.50, 1.00, 1.00, 0.50, 1.00, 0.00, 0.50, 1.00, 1.00, 0.50, 1.00,
]
const TEX_SHARES: Array[float] = [0.0, 0.0, 0.03, 0.03, 0.03, 0.03, 0.10, 0.10, 0.10, 0.10, 0.25, 0.25, 0.25, 0.25,
        0.45, 0.45, 0.45, 0.45]


## One drawn wing per built one, children of `root`; [] when the vehicle has none.
static func build(root: Node3D, truck: TruckParser, material: Material) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for row: Dictionary in truck.links.wings:
        if row["airfoil"] == "":
            continue
        var n: PackedInt32Array = row["nodes"]
        var p: PackedVector3Array = PackedVector3Array()
        for k: int in 8:
            p.append(truck.nodes[n[k]])
        var type: String = row["type"]
        var wing: Dictionary = {
            "nodes": n, "type": type, "chord": float(row["chord_point"]), "pos": REFAIRFOILPOS.duplicate(),
            "control": not "nSTUV".contains(type), "stabilator": "STUV".contains(type), "stabil_left": type == "T" or type == "V",
            "lratio": p[0].distance_to(p[2]) / p[0].distance_to(p[4]), "rratio": p[1].distance_to(p[3]) / p[1].distance_to(p[5]),
        }
        var pos: Array = wing["pos"]
        if wing["control"]:
            var c: float = wing["chord"]
            for k: int in 4:
                pos[56 + k * 3] = c
            pos[55] = -c + 1.5
            pos[58] = -c + 1.5
            pos[61] = c - 0.5
            pos[64] = c - 0.5
            for k: int in 12:
                pos[66 + k] = pos[54 + k]
        wing["uv"] = _uvs(row, pos)
        wing["indices"] = _indices()
        var instance: MeshInstance3D = MeshInstance3D.new()
        instance.name = "Wing%d" % out.size()
        instance.mesh = ArrayMesh.new()
        instance.material_override = material
        root.add_child(instance)
        wing["instance"] = instance
        out.append(wing)
    return out


## Each wing posed from the nodes (world positions) and its state, in the vehicle's local frame.
static func apply(wings: Array[Dictionary], nodes: PackedVector3Array, to_local: Transform3D, solver: RefCounted) -> void:
    for i: int in wings.size():
        var state: Dictionary = solver.wing_state(i) if solver != null else {}
        _pose(wings[i], nodes, to_local, float(state.get("deflection", 0.0)), bool(state.get("broken", false)))


static func _pose(wing: Dictionary, nodes: PackedVector3Array, to_local: Transform3D, deflection: float, broken: bool) -> void:
    var n: PackedInt32Array = wing["nodes"]
    var pos: Array = wing["pos"]
    if wing["control"]:
        var radius: float = 1.0 - float(wing["chord"])
        pos[82] = 0.5 + radius * sin(deflection / 57.0) / float(wing["rratio"])
        pos[79] = 0.5 + radius * sin(deflection / 57.0) / float(wing["lratio"])
        pos[83] = float(wing["chord"]) + radius * cos(deflection / 57.0)
        pos[80] = pos[83]
        pos[89] = pos[83]
        pos[88] = pos[82]
        pos[86] = pos[80]
        pos[85] = pos[79]
    var center: Vector3 = nodes[n[0]]
    var vx: Vector3 = nodes[n[1]] - center
    var vyl: Vector3 = nodes[n[2]] - center
    var vzl: Vector3 = nodes[n[4]] - center
    var vyr: Vector3 = nodes[n[3]] - nodes[n[1]]
    var vzr: Vector3 = nodes[n[5]] - nodes[n[1]]
    if broken:
        vx = Vector3(0.01, 0, 0)
        vyl = Vector3(0, 0.01, 0)
        vzl = Vector3(0, 0, 0.01)
        vyr = vyl
        vzr = vzl
    var v: PackedVector3Array = PackedVector3Array()
    v.resize(54)
    for k: int in 30:
        var y: Vector3 = vyr if k % 2 else vyl
        var z: Vector3 = vzr if k % 2 else vzl
        v[k] = vx * pos[k * 3] + y * pos[k * 3 + 1] + z * pos[k * 3 + 2]
        if k < 22:
            v[k + 30] = v[k]
    v[52] = v[28]
    v[53] = v[29]
    if wing["stabilator"]:
        var a: int = 3 if wing["stabil_left"] else 2
        var down: int = 1 if wing["stabil_left"] else 0
        var back: int = 7 if wing["stabil_left"] else 6
        var back_down: int = 5 if wing["stabil_left"] else 4
        var rcent: Vector3 = ((nodes[n[a]] + nodes[n[back_down]]) / 2.0 + (nodes[n[a]] - nodes[n[back]]) / 4.0) - center
        var raxis: Vector3 = (nodes[n[a]] - nodes[n[down]]).cross(nodes[n[a]] - nodes[n[back]]).normalized()
        for k: int in 54:
            v[k] = rcent + (v[k] - rcent).rotated(raxis, deg_to_rad(deflection))
    var local: PackedVector3Array = PackedVector3Array()
    for k: int in 54:
        local.append(to_local * (center + v[k]))
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = local
    arrays[Mesh.ARRAY_NORMAL] = _normals(local, wing["indices"], to_local.basis * (vx.normalized()))
    arrays[Mesh.ARRAY_TEX_UV] = wing["uv"]
    arrays[Mesh.ARRAY_INDEX] = wing["indices"]
    var mesh: ArrayMesh = (wing["instance"] as MeshInstance3D).mesh
    mesh.clear_surfaces()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## Upstream's normals: each band and control-surface triangle's added to its corners, then the
## section's ends facing along the span. Read with the winding as upstream wrote it.
static func _normals(v: PackedVector3Array, indices: PackedInt32Array, span: Vector3) -> PackedVector3Array:
    var out: PackedVector3Array = PackedVector3Array()
    out.resize(54)
    # Indices after the 60 of the faces are the band's and the control surface's, reversed for Godot.
    for t: int in range(60, indices.size(), 3):
        var a: int = indices[t]
        var b: int = indices[t + 2]
        var c: int = indices[t + 1]
        var normal: Vector3 = (v[b] - v[a]).cross(v[c] - v[a]).normalized()
        out[a] += normal
        out[b] += normal
        out[c] += normal
    for k: int in 30:
        out[k] = out[k].normalized()
    for k: int in 24:
        out[k + 30] = span if k % 2 else -span
    return out


static func _uvs(row: Dictionary, pos: Array) -> PackedVector2Array:
    var lf: Vector2 = Vector2(0, 0)
    var rf: Vector2 = Vector2(0, 0)
    var lb: Vector2 = Vector2(0, 0)
    var rb: Vector2 = Vector2(0, 0)
    var tex: PackedFloat32Array = row.get("tex", PackedFloat32Array([0, 0, 1, 0, 0, 1, 1, 1]))
    lf = Vector2(tex[0], tex[1])
    rf = Vector2(tex[2], tex[3])
    lb = Vector2(tex[4], tex[5])
    rb = Vector2(tex[6], tex[7])
    var uv: PackedVector2Array = PackedVector2Array()
    uv.resize(54)
    for k: int in 18:
        uv[k] = (lf + (lb - lf) * TEX_SHARES[k]) if k % 2 == 0 else (rf + (rb - rf) * TEX_SHARES[k])
    for k: int in range(18, 22):
        uv[k] = (lf + (lb - lf) * float(pos[56])) if k % 2 == 0 else (rf + (rb - rf) * float(pos[56]))
    for k: int in range(22, 26):
        uv[k] = uv[k - 4]
    uv[26] = lb
    uv[27] = rb
    uv[28] = lb
    uv[29] = rb
    for k: int in 24:
        uv[k + 30] = uv[k]
    return uv


## Upstream's triangle lists — the faces, the band, the control surface up and down — in one
## list, each triangle's winding reversed.
static func _indices() -> PackedInt32Array:
    var face: PackedInt32Array = PackedInt32Array()
    face.resize(60)
    var band: PackedInt32Array = PackedInt32Array([0, 2, 1, 2, 3, 1, 0, 1, 4, 4, 1, 5])
    band.resize(60)
    for i: int in 5:
        var v: int = i * 4 + 2
        if i != 4:
            var b: Array = [v, v + 4, v + 1, v + 4, v + 5, v + 1, v + 2, v + 3, v + 6, v + 6, v + 3, v + 7]
            for k: int in 12:
                band[i * 12 + 12 + k] = b[k]
        var f: Array = [30, 30 + v + 4, 30 + v, 30, 30 + v + 2, 30 + v + 6, 31, 30 + v + 1, 30 + v + 5, 31, 30 + v + 7, 30 + v + 3]
        if i == 4:
            f = [30, 30 + v + 2, 30 + v, 30 + v + 4, 30 + v, 30 + v + 2, 31, 30 + v + 1, 30 + v + 3, 30 + v + 5, 30 + v + 3, 30 + v + 1]
        for k: int in 12:
            face[i * 12 + k] = f[k]
    var all: PackedInt32Array = face + band + PackedInt32Array([22, 26, 23, 26, 27, 23, 24, 25, 29, 24, 29, 28])
    for t: int in range(0, all.size(), 3):
        var swap: int = all[t + 1]
        all[t + 1] = all[t + 2]
        all[t + 2] = swap
    return all
