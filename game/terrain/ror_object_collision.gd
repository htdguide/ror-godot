class_name RorObjectCollision
extends RefCounted
## Turns a terrain's own objects into something a vehicle can hit.
##
## A terrain ships meshes, not collision shapes. An `.odef` may declare a collision box and many
## do not: La Paz declares none at all, and its roadside poles are scenery a truck drove straight
## through. The solver takes static boxes, so the question is how to get a few sensible boxes out
## of an arbitrary mesh.
##
## Columns, not a bounding box. A pole object here is a 40 m span of wire with two poles in it, so
## its own box is a wall across the desert. Instead the mesh is divided into cells on the ground
## plane, and each cell that holds geometry becomes one box as tall as the geometry in it. Two
## poles come out as two boxes; the wires between them come out as nothing, because a cell whose
## geometry is a centimetre tall is not something to crash into.
##
## That is an approximation and it is the honest kind: it can only ever be as wrong as the cell
## size, it never invents solid where the mesh has none, and what it produces is checked by
## driving into it.

## How big a cell is on the ground plane, in metres.
const CELL_M: float = 0.7
## A cell whose geometry is shorter than this is scenery rather than an obstacle: wires, cables,
## the lip of a kerb.
const MIN_HEIGHT_M: float = 0.5
## And one this thin in both directions on the ground is drawn detail rather than structure.
const MIN_FOOTPRINT_M: float = 0.05
## How many cells one object may produce. A mesh that needs more than this is a building, and a
## building wants its own collision rather than a voxel grid.
const MAX_BOXES_PER_OBJECT: int = 64
## What a terrain's objects are made of, as far as a wheel is concerned.
const SURFACE: String = "concrete"
## How coarse a cell may get once the object's own scale is applied.
##
## A terrain's own furniture is placed as an object like anything else and scaled up to cover the
## map: La Paz's ground skirt and horizon card are 100 times their mesh, so one 0.7 m cell of
## them is 70 m of solid wall across the desert. An object whose cells come out this coarse is
## not being approximated by this method at all, so it is left alone — and a horizon is not
## something to crash into anyway.
const MAX_CELL_WORLD_M: float = 3.0


## Hands every object on a terrain to a solver as static boxes. Returns how many were added.
##
## Replaces whatever obstacles the solver held: a world has one set of them, and the terrain's
## are it.
static func apply(terrain: RorTerrain, solver: RefCounted) -> int:
    solver.clear_obstacles()
    var surface: int = maxi(terrain.models.index_of(SURFACE), 0)
    var added: int = 0
    for box: Dictionary in boxes(terrain):
        solver.add_obstacle_box(
            box["transform"] as Transform3D, box["half"] as Vector3, surface
        )
        added += 1
    return added


## Every solid box on a terrain, as {"transform", "half", "name"}.
static func boxes(terrain: RorTerrain) -> Array[Dictionary]:
    # The procedural roads first. They are a surface a vehicle drives on rather than scenery it
    # hits, and they are the one part of a terrain that is not an object at all.
    var out: Array[Dictionary] = road_boxes(terrain)
    var state: Dictionary = RorObjects.state(terrain)
    var shapes: Dictionary = {}
    for placement: Dictionary in RorObjects.placements(terrain):
        var name: String = placement["name"] as String
        var definition: Dictionary = RorObjects.definition(terrain, name, state)
        if (definition.get("error", "") as String) != "":
            continue
        # The author's own boxes first, where there are any. A `beginbox` is a statement about
        # what is solid, written by the person who placed the object, and it is right where this
        # method's approximation is weakest: a road slab is flat, so its derived columns fall
        # under the obstacle threshold and it gets nothing at all, which is a visible road a
        # truck drives straight through. `road-slab.odef` says `boxcoords -5.01, 5.01, -3, 0.3,
        # -5.01, 5.01` — a 10 m slab 3.3 m thick, top 0.3 m up — and Port Starling places 189 of
        # them.
        var authored: Array[Dictionary] = _authored_boxes(placement, definition)
        if not authored.is_empty():
            out.append_array(authored)
            continue
        var local: Array[Dictionary] = _shape_of(terrain, name, definition, state, shapes)
        if local.is_empty():
            continue
        var scale: Vector3 = definition["scale"] as Vector3
        if CELL_M * maxf(absf(scale.x), absf(scale.y)) > MAX_CELL_WORLD_M:
            continue
        var frame: Transform3D = RorObjects.transform_of(placement, scale)
        for cell: Dictionary in local:
            out.append({
                "transform": frame * (cell["transform"] as Transform3D),
                # The object's own scale is in the frame, so the half extents scale with it.
                "half": (cell["half"] as Vector3) * scale.abs(),
                "name": name,
            })
    return out


## The collision boxes an object definition declares, placed in the world.
##
## **A box is not in the mesh's frame.** Upstream turns the visual node by the placement's
## rotation and then pitches it -90 degrees because object meshes are authored Z-up
## (`TerrainObjectManager::LoadTerrainObject`); the box gets the placement's rotation and **no
## pitch** (`Collisions::addCollisionBox`), so `boxcoords` is read Y-up. `road-slab`'s
## `-3 .. 0.3` is its thickness, which only makes sense that way round.
##
## The scale multiplies the coordinates in the box's own axes before the rotation — upstream's
## `coll_box.relo = l * sc` — which is the same thing a scene node's local scale does.
##
## A `virtual` box is an event zone: upstream gates every solid response on `!cbox->virt`.
static func _authored_boxes(
    placement: Dictionary, definition: Dictionary
) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var scale: Vector3 = definition["scale"] as Vector3
    var degrees: Vector3 = placement["rotation"] as Vector3
    var frame: Basis = (
        Basis(Vector3.RIGHT, deg_to_rad(degrees.x))
        * Basis(Vector3.UP, deg_to_rad(degrees.y))
        * Basis(Vector3.BACK, deg_to_rad(degrees.z))
    )
    for box: Dictionary in definition["boxes"] as Array[Dictionary]:
        if box["virtual"] as bool:
            continue
        var low: Vector3 = (box["min"] as Vector3) * scale
        var high: Vector3 = (box["max"] as Vector3) * scale
        var half: Vector3 = ((high - low) * 0.5).abs()
        if half.x <= 0.0 or half.y <= 0.0 or half.z <= 0.0:
            continue
        var self_rotation: Vector3 = box["rotation"] as Vector3
        var spun: Basis = (
            Basis(Vector3.RIGHT, deg_to_rad(self_rotation.x))
            * Basis(Vector3.UP, deg_to_rad(self_rotation.y))
            * Basis(Vector3.BACK, deg_to_rad(self_rotation.z))
        )
        var centre: Vector3 = (low + high) * 0.5
        out.append({
            "transform": Transform3D(
                frame * spun, (placement["position"] as Vector3) + frame * centre
            ),
            "half": half,
            "name": placement["name"],
        })
    return out


## How thick a carriageway is made for the solver. A road is a surface and the solver takes
## boxes, so the box hangs below the surface: deep enough that a wheel at speed cannot step
## through it in one tick, and the part of it under the ground costs nothing.
const ROAD_THICKNESS_M: float = 1.0


## The carriageway as something a vehicle can drive on: one box per segment, lying along it.
##
## An approximation, and the honest kind. The four corners of a segment's tarmac need not be
## coplanar — the road banks and climbs between its points — so the box is built on the segment's
## own axes and sized to it, which can only ever be as wrong as one segment is long. The kerbs,
## shoulders and walls are not made solid: they are centimetres tall beside a carriageway metres
## wide, and a box per quad would be four times the count for scenery a wheel rides over anyway.
static func road_boxes(terrain: RorTerrain) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for group: Array[Dictionary] in RorProceduralRoad.groups(terrain):
        for index: int in range(1, group.size()):
            var here: Dictionary = RorProceduralRoad.resolved(terrain, group[index])
            var last: Dictionary = RorProceduralRoad.resolved(terrain, group[index - 1])
            if not RorProceduralRoad.BUILT_KINDS.has(here["kind"]) or not RorProceduralRoad.BUILT_KINDS.has(last["kind"]):
                continue
            var box: Dictionary = _road_segment_box(
                RorProceduralRoad.section(terrain, here), RorProceduralRoad.section(terrain, last)
            )
            if not box.is_empty():
                out.append(box)
    return out


## One segment as a box, or empty when the segment has no length.
##
## **Across the whole section, not just the carriageway.** 107 of Port Starling's road lines
## state a width of 0 with a 2 m border either side: upstream's cross-section collapses the
## carriageway to a line and draws two 2 m strips, which is a footpath. Built from points 3 and 4
## the box has no width at all and the path is not solid — which is how this was found, with the
## drop test landing 14 m below a deck it should have rested on. Points 1 and 6 are the section's
## outer edges and span the carriageway and its kerbs together.
##
## The top sits at the carriageway's own height rather than the kerbs': a kerb is something a
## wheel rides over, and a box as tall as one would hold a vehicle up at its lip.
static func _road_segment_box(a: PackedVector3Array, b: PackedVector3Array) -> Dictionary:
    var near: Vector3 = (a[3] + a[4]) * 0.5
    var far: Vector3 = (b[3] + b[4]) * 0.5
    var along: Vector3 = far - near
    if along.length_squared() <= 0.0:
        return {}
    var length: float = along.length()
    along = along / length
    var across: Vector3 = a[1] - a[6]
    if across.length_squared() <= 0.0:
        return {}
    var width: float = (a[1].distance_to(a[6]) + b[1].distance_to(b[6])) * 0.5
    across = across.normalized()
    var up: Vector3 = across.cross(along).normalized()
    if up.y < 0.0:
        up = -up
        across = -across
    var surface: Vector3 = (near + far) * 0.5
    return {
        "transform": Transform3D(
            Basis(along, up, across), surface - up * (ROAD_THICKNESS_M * 0.5)
        ),
        "half": Vector3(length * 0.5, ROAD_THICKNESS_M * 0.5, width * 0.5),
        "name": "road",
    }


## The boxes one object definition is worth, in its own frame. Worked out once per definition.
static func _shape_of(
    terrain: RorTerrain,
    name: String,
    definition: Dictionary,
    state: Dictionary,
    shapes: Dictionary
) -> Array[Dictionary]:
    if shapes.has(name):
        return shapes[name] as Array[Dictionary]
    var points: PackedVector3Array = PackedVector3Array()
    # The hull the author shipped, where there is one. An `.odef`'s `beginmesh` block is a
    # collision mesh — upstream puts it in `collision_meshes` and never draws it — so Starling
    # Island's `firehousebox.mesh` and `haus5Kol.mesh` are a statement about what is solid, made
    # by the person who built the building. Falling back to the visual mesh is this project's own
    # addition and the reason it exists: La Paz declares neither a box nor a hull for anything, and
    # its roadside poles were scenery a truck drove through.
    var from: PackedStringArray = definition["collision_meshes"] as PackedStringArray
    if from.is_empty():
        from = definition["meshes"] as PackedStringArray
    for file: String in from:
        var mesh: ArrayMesh = RorObjects.mesh_of(terrain, file, state)
        if mesh == null:
            continue
        for surface: int in mesh.get_surface_count():
            points.append_array(
                mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array
            )
    var cells: Array[Dictionary] = _columns(points)
    shapes[name] = cells
    return cells


## The occupied columns of a point cloud, as boxes in the same frame.
##
## The mesh is z-up in its own frame — every object in this library is, which is why upstream
## pitches them all by -90 degrees when it places them — so the ground plane here is x/y and the
## height is z.
static func _columns(points: PackedVector3Array) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    if points.is_empty():
        return out
    var cells: Dictionary = {}
    for point: Vector3 in points:
        var key: Vector2i = Vector2i(
            int(floor(point.x / CELL_M)), int(floor(point.y / CELL_M))
        )
        var bounds: Vector4 = cells.get(
            key, Vector4(point.x, point.y, point.z, point.z)
        ) as Vector4
        # x and y hold the cell's own middle as it fills in; z and w its height range.
        cells[key] = Vector4(
            minf(bounds.x, point.x),
            minf(bounds.y, point.y),
            minf(bounds.z, point.z),
            maxf(bounds.w, point.z)
        )
    for key: Vector2i in cells.keys():
        if out.size() >= MAX_BOXES_PER_OBJECT:
            break
        var bounds: Vector4 = cells[key] as Vector4
        var height: float = bounds.w - bounds.z
        if height < MIN_HEIGHT_M:
            continue
        var low: Vector2 = Vector2(float(key.x), float(key.y)) * CELL_M
        var half: Vector3 = Vector3(
            maxf(CELL_M * 0.5, MIN_FOOTPRINT_M),
            maxf(CELL_M * 0.5, MIN_FOOTPRINT_M),
            height * 0.5
        )
        var centre: Vector3 = Vector3(
            low.x + CELL_M * 0.5, low.y + CELL_M * 0.5, bounds.z + height * 0.5
        )
        out.append({"transform": Transform3D(Basis.IDENTITY, centre), "half": half})
    return out
