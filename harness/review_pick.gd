class_name ReviewPick
extends RefCounted
## Which surface of an object the mouse is over, and a bright copy of it to draw on top.
##
## **A surface, not a triangle.** "The roof has no texture" is a statement about a roof, and a
## roof is forty triangles. The pick finds the triangle under the cursor and then hands back the
## whole connected run of triangles that touch it and look the same way — `ObjectWinding`'s own
## notion of a surface, the one its winding test votes on — so what lights up under the cursor is
## the thing a person means.
##
## The ray is `ObjectWinding.hit_distance`, the same arithmetic the winding test counts crossings
## with. A second copy of ray-triangle intersection would be a second thing to get wrong.

## What the highlight is painted. Unshaded, so it reads the same against any surface and at any
## angle, and nothing in a terrain's own palette is this colour.
const HOVER: Color = Color(1.0, 0.85, 0.1)
const MARKED: Color = Color(1.0, 0.25, 0.6)
## How far the highlight is pushed towards the camera so it is not in a fight with the surface it
## is copying, as a share of the object's own size.
const LIFT: float = 0.0015

var _faces: Array[Dictionary] = []
var _surfaces: Array[Array] = []
var _span: float = 1.0


## Reads a mesh's surfaces once, so that hovering does not re-derive them every frame.
func study(submeshes: Array) -> void:
    _span = ObjectWinding.span_of(submeshes)
    _faces = ObjectWinding.faces_of(submeshes)
    _surfaces = ObjectWinding.surfaces_of(_faces, _span) if _span > 0.0 else []


## Which surface the cursor is over, as an index into `_surfaces`, or -1.
##
## The object's own transform is undone rather than the mesh being transformed: one ray moved
## into mesh space costs nothing, and moving every triangle into world space costs the mesh.
func under(at: Transform3D, camera: Camera3D, mouse: Vector2) -> int:
    if _surfaces.is_empty():
        return -1
    var inverse: Transform3D = at.affine_inverse()
    var from: Vector3 = inverse * camera.project_ray_origin(mouse)
    var along: Vector3 = (inverse.basis * camera.project_ray_normal(mouse)).normalized()
    var nearest: float = INF
    var found: int = -1
    for index: int in _surfaces.size():
        for face: Dictionary in _surfaces[index]:
            var corners: Array = face["corners"] as Array
            var distance: float = ObjectWinding.hit_distance(
                from, along,
                corners[0] as Vector3, corners[1] as Vector3, corners[2] as Vector3
            )
            if distance > 0.0 and distance < nearest:
                nearest = distance
                found = index
    return found


## A mesh of one surface's triangles alone, to draw over the object in a colour.
func overlay(index: int, colour: Color) -> ArrayMesh:
    if index < 0 or index >= _surfaces.size():
        return null
    var points: PackedVector3Array = PackedVector3Array()
    for face: Dictionary in _surfaces[index]:
        var corners: Array = face["corners"] as Array
        var lift: Vector3 = (face["out"] as Vector3) * _span * LIFT
        for corner: Vector3 in corners:
            points.append((corner as Vector3) + lift)
    if points.is_empty():
        return null
    var arrays: Array = []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = points
    var mesh: ArrayMesh = ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = colour
    # Both sides: a surface the person is complaining about is often one they can only see the
    # back of, which is the whole reason they are complaining.
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    mesh.surface_set_material(0, material)
    return mesh


## What is worth writing down about a marked surface: enough to find it again in the file.
func describe(index: int) -> Dictionary:
    if index < 0 or index >= _surfaces.size():
        return {}
    var surface: Array = _surfaces[index]
    var first: Dictionary = surface[0] as Dictionary
    var area: float = 0.0
    var direction: Vector3 = Vector3.ZERO
    for face: Dictionary in surface:
        area += face["area"] as float
        direction += (face["out"] as Vector3) * (face["area"] as float)
    return {
        "submesh": first["submesh"],
        "triangle": first["triangle"],
        "triangles": surface.size(),
        "area_m2": snappedf(area, 0.01),
        "faces": _axis(direction.normalized() if direction.length() > 0.0 else Vector3.ZERO),
    }


## Which way a surface mostly looks, in the object's own axes, written the way a person reads it.
func _axis(normal: Vector3) -> String:
    if normal == Vector3.ZERO:
        return "nowhere"
    var axis: Vector3 = normal.abs()
    if axis.x >= axis.y and axis.x >= axis.z:
        return "+X" if normal.x > 0.0 else "-X"
    if axis.y >= axis.z:
        return "+Y" if normal.y > 0.0 else "-Y"
    return "+Z" if normal.z > 0.0 else "-Z"
