class_name SubmeshRows
extends RefCounted
## The `submesh` sections of a vehicle file: the body panels a truck draws from its own nodes.
##
## A `submesh` opens one panel group. The `texcoords` lines that follow give a texture coordinate
## per node, the `cab` lines give triangles over those nodes, and a bare `backmesh` says the panel
## is drawn from both sides. Upstream keeps each group separately and builds a `FlexObj` from it;
## this project kept one flat list of triangles for collision and drew none of it.
##
## **Which vehicles this is.** 18 of the 18 in this library declare submeshes, and 14 of them draw
## something else as well — so for most it is bodywork missing from a vehicle that otherwise looks
## built. For four it is everything they have: NhelensGrass's bridge and monorail and the Daf
## pack's two semi trailers draw nothing at all without it.
##
## The hero truck and the Mazda declare `cab` triangles and **no** `texcoords`, which is why their
## cabs have always been collision-only: there is nothing to draw them with, and a panel with no
## texture coordinates is not a panel anybody meant to see.
##
## A node may carry different coordinates in different groups, so each group keeps its own and the
## geometry is built per group rather than per node.


## `{"nodes", "uvs", "triangles", "backmesh"}` per group, in file order.
var groups: Array[Dictionary] = []
## Every cab triangle in the file, flat, in node indices. The solver takes the cab as one surface
## and does not care which panel a triangle came from.
var cab_triangles: PackedInt32Array = PackedInt32Array()
## Every texture coordinate in the file, flat, with the node each belongs to beside it.
var texcoord_nodes: PackedInt32Array = PackedInt32Array()
var texcoords: PackedVector2Array = PackedVector2Array()


## Reads one `texcoords` line. Returns an error, or "".
func read_texcoord(fields: PackedStringArray, id_to_index: Dictionary) -> String:
    var row: Dictionary = CabRows.texcoord(fields, id_to_index)
    if (row["error"] as String) != "":
        return row["error"] as String
    texcoord_nodes.append(row["node"] as int)
    texcoords.append(row["uv"] as Vector2)
    texcoord(row["node"] as int, row["uv"] as Vector2)
    return ""


## Reads one `cab` line. Returns an error, or "".
func read_cab(fields: PackedStringArray, id_to_index: Dictionary) -> String:
    var row: Dictionary = CabRows.triangle(fields, id_to_index)
    if (row["error"] as String) != "":
        return row["error"] as String
    cab_triangles.append_array(row["nodes"] as PackedInt32Array)
    triangle(row["nodes"] as PackedInt32Array)
    return ""


## Opens a group. Called for every `submesh` header.
func begin() -> void:
    groups.append({
        "nodes": PackedInt32Array(),
        "uvs": PackedVector2Array(),
        "triangles": PackedInt32Array(),
        "backmesh": false,
    })


## Records a texture coordinate for a node in the open group.
func texcoord(node: int, uv: Vector2) -> void:
    var group: Dictionary = _open()
    var nodes: PackedInt32Array = group["nodes"] as PackedInt32Array
    var uvs: PackedVector2Array = group["uvs"] as PackedVector2Array
    nodes.append(node)
    uvs.append(uv)
    group["nodes"] = nodes
    group["uvs"] = uvs


## Records a triangle in the open group.
func triangle(nodes: PackedInt32Array) -> void:
    var group: Dictionary = _open()
    var triangles: PackedInt32Array = group["triangles"] as PackedInt32Array
    triangles.append_array(nodes)
    group["triangles"] = triangles


## Marks the open group as drawn from both sides.
func backmesh() -> void:
    if not groups.is_empty():
        groups[groups.size() - 1]["backmesh"] = true


## How many groups carry both coordinates and triangles, and so can be drawn.
func drawable() -> int:
    var count: int = 0
    for group: Dictionary in groups:
        if (group["uvs"] as PackedVector2Array).size() > 0 and (
            group["triangles"] as PackedInt32Array
        ).size() >= 3:
            count += 1
    return count


## The group being filled. A file may put `texcoords` before its first `submesh` header, and
## upstream reads those into the submesh it is already building, so one is opened to receive them.
func _open() -> Dictionary:
    if groups.is_empty():
        begin()
    return groups[groups.size() - 1]
