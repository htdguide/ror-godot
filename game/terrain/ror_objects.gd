class_name RorObjects
extends RefCounted
## Places the objects a Rigs of Rods terrain ships: its poles, its buildings, its horizon.
##
## A terrain's `.tobj` names a position, a rotation and an object definition; the definition
## names meshes; the meshes name materials; the materials name textures. Every one of those is a
## file the terrain's author shipped, and following the chain is the whole of this file.
##
## Meshes and materials are cached by name, so a hundred identical poles are a hundred transforms
## over one mesh rather than a hundred parses of the same file.
##
## **They are also drawn that way.** Placements are grouped by mesh and by tile and handed to one
## `MultiMeshInstance3D` each, so La Paz's 99 identical poles cost one draw call per tile they
## fall in rather than 99 nodes. The same terrain was measured at 135 to 202 draw calls and 18.79
## to 28.47 ms in a session window, against M2's 16.6 ms budget, which is what made this worth
## doing before anything that adds more scenery.
##
## **The tiles are not an optimisation, they are what keeps the optimisation from backfiring.** A
## single MultiMesh spanning the whole map has an axis-aligned box covering the whole map, so it
## is in frustum from everywhere and is drawn whichever way the camera points. Grouping by tile
## keeps each batch small enough in space that the renderer can still throw most of them away.
## `RorVegetation` reached the same conclusion for grass and the tiles here are the same idea at a
## larger size, because a building is rarer and bigger than a tuft of grass.
##
## What is *not* here: the collision boxes an object definition can carry, and the vegetation the
## object file asks for. Both are counted and reported rather than quietly dropped.

## Objects at the origin are the format's own way of saying "the whole map" — a horizon card, a
## ground skirt — and they are drawn like anything else. This is only the sanity bound on how far
## outside the map an object may be placed before the file is being read wrong.

## Where a surface records that its own material asked to be kept out of the scene's fog. A note
## rather than an instruction: see `_material`. It is also what marks a backdrop, because that is
## what the passes which ask for it are — see `SceneryRange`.
const ASKED_FOR_NO_FOG: StringName = &"asked_for_no_fog"
static func _descendants(node: Node) -> Array[Node]:
    var out: Array[Node] = [node]
    for child: Node in node.get_children():
        out.append_array(_descendants(child))
    return out

const MAX_OUTSIDE_M: float = 6000.0
## How big a batch is, in metres. Large enough that a tile holds several objects on a sparse map,
## small enough that a tile is a meaningful thing to cull. Grass uses 32 m; scenery is sparser and
## larger, so its tiles are too.
const TILE_M: float = 256.0
## How much of a level's own distance is spent fading into the next one.
const LOD_FADE: float = 0.1


## Builds every object in a terrain. Returns a node holding them, and never null.
static func build(terrain: RorTerrain) -> Node3D:
    var root: Node3D = Node3D.new()
    root.name = "RorObjects"
    var caches: Dictionary = state(terrain)
    # `mesh file + tile` to the transforms that want it, and a list of the keys in the order they
    # were first seen. Insertion order rather than the dictionary's own, because a gate compares
    # one run against another and a scene built in a different order is a different scene.
    var batches: Dictionary = {}
    var order: Array[String] = []
    for placement: Dictionary in placements(terrain):
        var name: String = placement["name"] as String
        var odef: Dictionary = definition(terrain, name, caches)
        if (odef.get("error", "") as String) != "":
            continue
        var at: Transform3D = transform_of(placement, odef["scale"] as Vector3)
        var tile: Vector2i = tile_of(at.origin)
        for level: Dictionary in _levels(odef):
            var key: String = "%s|%d|%d|%.0f|%.0f" % [
                level["mesh"], tile.x, tile.y, level["begin"], level["end"]
            ]
            if not batches.has(key):
                batches[key] = ([] as Array[Transform3D])
                order.append(key)
            (batches[key] as Array[Transform3D]).append(at)
    for key: String in order:
        var mesh_file: String = key.get_slice("|", 0)
        var mesh: ArrayMesh = mesh_of(terrain, mesh_file, caches)
        if mesh == null:
            continue
        root.add_child(_batch(key, mesh, batches[key] as Array[Transform3D]))
    return root


## What an object draws, and from how far away each of it is drawn.
##
## **`beginlodmesh` is the author's own distance geometry.** A block of `<distance>, <mesh>` lines
## says which mesh to draw from how far away, and Starling Island ships twelve of them across ten
## objects. Upstream's current parser reads the block and does nothing with it, so nobody has
## drawn them for years; they are the cheapest distance geometry this project can have, because
## the terrain's author already made it.
##
## The header mesh is drawn up to the first stated distance, each level from its own distance to
## the next, and the last to the horizon. A distance of zero in Godot means "no limit", which is
## what the far end of the last level wants anyway.
static func _levels(odef: Dictionary) -> Array[Dictionary]:
    var lods: Array[Dictionary] = odef.get("lods", [] as Array[Dictionary])
    var out: Array[Dictionary] = []
    var first: float = 0.0 if lods.is_empty() else lods[0]["distance"] as float
    for mesh_file: String in odef["meshes"] as PackedStringArray:
        out.append({"mesh": mesh_file, "begin": 0.0, "end": first})
    for index: int in lods.size():
        out.append({
            "mesh": lods[index]["mesh"],
            "begin": lods[index]["distance"] as float,
            "end": 0.0 if index + 1 >= lods.size() else lods[index + 1]["distance"] as float,
        })
    return out


## Which tile a point falls in. Floored, so the tile a point belongs to does not depend on which
## side of zero it sits.
static func tile_of(at: Vector3) -> Vector2i:
    return Vector2i(int(floor(at.x / TILE_M)), int(floor(at.z / TILE_M)))


## One mesh, drawn once for every transform that wants it.
static func _batch(key: String, mesh: ArrayMesh, at: Array[Transform3D]) -> MultiMeshInstance3D:
    # **The batch stands where its instances are.** A visibility range is measured from the
    # camera to the *node*, not to the instance, so a batch left at the world origin with its
    # instances scattered across the map is judged by how far the camera is from (0, 0, 0). On a
    # 3 km map that is hundreds of metres from anywhere, and every batch carrying a range
    # disappeared the moment distance meshes were added: the buildings with a `beginlodmesh`
    # chain were invisible from everywhere except the corner of the map. Reported from a window
    # as "some of the buildings are still missing", and no gate saw it, because the gate checked
    # that the range was the one the definition states and not that it was measured from
    # anywhere sensible.
    var centre: Vector3 = Vector3.ZERO
    for frame: Transform3D in at:
        centre += frame.origin
    centre /= maxf(float(at.size()), 1.0)
    var multimesh: MultiMesh = MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = at.size()
    for index: int in at.size():
        multimesh.set_instance_transform(
            index, Transform3D(at[index].basis, at[index].origin - centre)
        )
    var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
    node.position = centre
    node.name = key.get_slice("|", 0).get_basename()
    # The distances the object's own definition states, with a margin either side so a building
    # fades between its levels instead of snapping.
    node.visibility_range_begin = key.get_slice("|", 3).to_float()
    node.visibility_range_end = key.get_slice("|", 4).to_float()
    node.visibility_range_begin_margin = node.visibility_range_begin * LOD_FADE
    node.visibility_range_end_margin = node.visibility_range_end * LOD_FADE
    if node.visibility_range_begin > 0.0 or node.visibility_range_end > 0.0:
        node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
    # And the file it came from, written down rather than left to be read back off the node.
    # One mesh is one batch per tile, so several siblings carry the same name and Godot renames
    # the duplicates — `@MultiMeshInstance3D@3` is what a screenshot's sidecar called a La Paz
    # pole when it trusted `name`. The meta survives whatever the scene tree does to the name.
    node.set_meta("mesh_file", key.get_slice("|", 0))
    node.multimesh = multimesh
    return node


## Every object the terrain's object files ask for, as {"position", "rotation", "name"}.
static func placements(terrain: RorTerrain) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for file: String in terrain.config["objects"] as PackedStringArray:
        var parsed: Dictionary = Tobj.read(terrain.directory.path_join(file))
        if (parsed["error"] as String) != "":
            push_warning(parsed["error"] as String)
            continue
        out.append_array(parsed["objects"] as Array[Dictionary])
    return out


## What a terrain asks for beyond the objects this builds, as a line for a gate or a session to
## report. Not all of it is unbuilt any more: vegetation is grown by `RorVegetation`, collision
## boxes by `RorObjectCollision` and road points by `RorProceduralRoad`. Only actor spawns and
## lines nothing reads are still nothing at all.
static func unbuilt(terrain: RorTerrain) -> Dictionary:
    var grass: int = 0
    var unread: int = 0
    var roads: int = 0
    var actors: int = 0
    for file: String in terrain.config["objects"] as PackedStringArray:
        var parsed: Dictionary = Tobj.read(terrain.directory.path_join(file))
        grass += (parsed["grass"] as Array[Dictionary]).size()
        unread += (parsed["unread"] as PackedStringArray).size()
        roads += (parsed["roads"] as Array[Dictionary]).size()
        actors += (parsed["actors"] as Array[Dictionary]).size()
    var boxes: int = 0
    var caches: Dictionary = state(terrain)
    for placement: Dictionary in placements(terrain):
        var odef: Dictionary = definition(terrain, placement["name"] as String, caches)
        boxes += (odef["boxes"] as Array[Dictionary]).size()
    return {
        "grass": grass, "collision_boxes": boxes, "unread_lines": unread,
        "road_points": roads, "actor_spawns": actors,
    }





## The caches one build shares: definitions, meshes and the directory's materials. Shared with
## whatever else has to follow the same chain — the collision builder walks it too, and parsing
## a hundred poles twice is a hundred parses too many.
static func state(terrain: RorTerrain) -> Dictionary:
    return {
        "definitions": {},
        "meshes": {},
        "materials": RorContentPath.materials(terrain.directory),
        "textures": {},
        "reader": ClassDB.instantiate("OgreMeshReader") as RefCounted,
        "dds": ClassDB.instantiate("DdsReader") as RefCounted,
    }


## One placed object, or null when its definition or meshes cannot be read.
static func _place(terrain: RorTerrain, placement: Dictionary, state: Dictionary) -> Node3D:
    var name: String = placement["name"] as String
    var odef: Dictionary = definition(terrain, name, state)
    if (odef.get("error", "") as String) != "":
        return null
    var node: Node3D = Node3D.new()
    node.name = name
    node.transform = transform_of(placement, odef["scale"] as Vector3)
    var drawn: int = 0
    for mesh_file: String in odef["meshes"] as PackedStringArray:
        var mesh: ArrayMesh = mesh_of(terrain, mesh_file, state)
        if mesh == null:
            continue
        var instance: MeshInstance3D = MeshInstance3D.new()
        instance.name = mesh_file.get_basename()
        instance.mesh = mesh
        node.add_child(instance)
        drawn += 1
    if drawn == 0:
        node.queue_free()
        return null
    return node


## Where an object stands.
##
## Upstream builds the rotation about x, then y, then z, in degrees — and then pitches the node
## another -90 degrees about its own x axis, unconditionally, for every object on every terrain
## (`TerrainObjectManager::LoadTerrainObject`). That last turn is the whole convention: object
## meshes in this library are authored z-up, and without it La Paz's roadside poles lie on their
## sides in the ground, which is how this was found — 99 poles, 6 m of mesh along z, and nothing
## visible above the surface.
##
## The scale is a local scale, as a scene node's is: applied in the object's own axes before the
## rotation, not to the world box it ends up occupying. It only shows on an object scaled
## unevenly, and La Paz has one — its sky dome, at 101 by 25 by 101.
static func transform_of(placement: Dictionary, scale: Vector3) -> Transform3D:
    var degrees: Vector3 = placement["rotation"] as Vector3
    var basis: Basis = (
        Basis(Vector3.RIGHT, deg_to_rad(degrees.x))
        * Basis(Vector3.UP, deg_to_rad(degrees.y))
        * Basis(Vector3.BACK, deg_to_rad(degrees.z))
        * Basis(Vector3.RIGHT, deg_to_rad(-90.0))
    )
    return Transform3D(basis.scaled_local(scale), placement["position"] as Vector3)


## An object definition, read once per name.
static func definition(terrain: RorTerrain, name: String, state: Dictionary) -> Dictionary:
    var cache: Dictionary = state["definitions"] as Dictionary
    if cache.has(name):
        return cache[name] as Dictionary
    # Through the content path, not the terrain's own folder. An object definition is content
    # like any other and a terrain may name one it does not ship: Port Starling places
    # `road-slab` 189 times, `road-park` 139, and signs, traffic lights and dock sections besides,
    # every one of them in `resources/meshes` and none of them in the pack. Looked for only
    # beside the terrain, 835 of its 1502 placements -- 56% of the map -- drew nothing at all,
    # which is most of its roads.
    var parsed: Dictionary = Odef.read(
        RorContentPath.find("%s.odef" % name, terrain.directory)
    )
    cache[name] = parsed
    return parsed


## A mesh, read once per file, with its materials resolved.
static func mesh_of(terrain: RorTerrain, file: String, state: Dictionary) -> ArrayMesh:
    var cache: Dictionary = state["meshes"] as Dictionary
    if cache.has(file):
        return cache[file] as ArrayMesh
    var path: String = RorContentPath.find(file, terrain.directory)
    var read: Dictionary = (state["reader"] as RefCounted).read_file(path)
    if (read.get("error", "") as String) != "":
        push_warning("%s: %s" % [file, read.get("error", "")])
        cache[file] = null
        return null
    var mesh: ArrayMesh = ArrayMesh.new()
    # Which triangles, if any, this file draws back to front. A plan rather than a per-mesh
    # verdict: `haus4.mesh` has its roof right and its gable ends wrong, and turning the mesh
    # turns the roof with it.
    var turn: Array[PackedInt32Array] = ObjectWinding.plan(read["submeshes"] as Array)
    var at: int = -1
    for submesh: Dictionary in read["submeshes"] as Array:
        at += 1
        # A submesh whose indices run past its own vertices cannot be drawn: Godot rejects the
        # surface and every measurement over it reads off the end of an array. They appear where
        # the reader resynchronises past a chunk length that lies — the index buffer survives and
        # the vertex buffer does not — and dropping them costs nothing that could have been shown.
        if not _indices_fit(submesh):
            continue
        var arrays: Array = ObjectWinding.arrays(submesh, turn[at])
        if arrays.is_empty():
            continue
        mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
        mesh.surface_set_material(
            mesh.get_surface_count() - 1,
            RorObjectMaterial.of(terrain, submesh["material"] as String, state)
        )
    if mesh.get_surface_count() == 0:
        cache[file] = null
        return null
    cache[file] = mesh
    return mesh


## Whether every index of a submesh names a vertex it actually has.
static func _indices_fit(submesh: Dictionary) -> bool:
    var points: int = (submesh["positions"] as PackedVector3Array).size()
    for index: int in submesh["indices"] as PackedInt32Array:
        if index < 0 or index >= points:
            return false
    return true



