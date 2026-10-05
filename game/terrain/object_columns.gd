class_name ObjectColumns
extends RefCounted
## How one mesh becomes a set of boxes.
##
## Split out of `RorObjectCollision` when growing the cell took that file over its source cap.
## What is here is the geometry: a mesh in, boxes out, in the mesh's own space. What is there is
## everything about a terrain — which objects exist, where they stand, what they are made of, and
## which of them this method should not be used on at all.
##
## **Cells on the ground plane, not a bounding box.** A pole object is a 40 m span of wire with two
## poles in it, and its own box is a wall across the desert. The mesh is divided into cells, and
## each cell that holds geometry becomes one box as tall as the geometry in it. Two poles come out
## as two boxes; the wire between them comes out as nothing.
##
## An approximation, and the honest kind: it can only be as wrong as the cell, it never invents
## solid where the mesh has none, and what it produces is checked by driving into it.

## How big a cell is on the ground plane, in metres.
const CELL_M: float = 0.7
## How thick a slab is made of a surface that has no thickness of its own.
##
## **A flat thing is still something to stand on.** A cell's geometry used to have to be half a
## metre tall to count, on the grounds that a wire is not an obstacle — and that threw away every
## horizontal surface in the library. `largedockasphalt.mesh` is a 50 by 30 m quay pad, the hero
## truck spawns on one, and it had nothing solid in it at all. Reported from a window as "it
## spawns on a block which doesn't have collision so wheels are half way in the texture".
const MIN_SLAB_M: float = 0.2
## How tall an object may be and still count as flat, and be taken as one slab of its own bounds.
const FLAT_M: float = 1.0
## How coarse a cell may become while an object is being made to fit under the cap.
const MAX_GROWN_CELL_M: float = 4.0
## A box thinner than this in both directions on the ground is drawn detail rather than structure,
## and a box with no width at all is one a solver cannot push out of.
const MIN_FOOTPRINT_M: float = 0.05
## How many boxes one object may come to.
##
## **A cap that truncates is worse than a coarse cell.** The boxes are emitted in sorted cell
## order, so an object over the cap used to get its first 4096 and nothing after: `hospital`
## covered 43.7% of its own footprint with its boxes' centre 25.58 m from the mesh's, which a
## session reviewing the overlay reported as "only pillars collision, not the house". The cell
## grows instead, and the cap is what stops the growth being unbounded.
const MAX_BOXES_PER_OBJECT: int = 4096


## Every box one mesh comes to, in the mesh's own space, as `{"transform", "half", "cell"}`.
##
## `cell` is what the mesh was approximated at, for the caller to judge against the object's own
## scale: a cell that is three metres across in the world is not an approximation of anything.
static func of(points: PackedVector3Array) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    if points.is_empty():
        return out
    var low: Vector3 = Vector3.INF
    var high: Vector3 = -Vector3.INF
    for at: int in points.size():
        low = low.min(points[at])
        high = high.max(points[at])
    # A flat object may be approximated coarsely; a tall one may not.
    # **A flat object is one slab.** A 50 by 30 m quay pad is 3053 cells at `CELL_M` and the cap
    # keeps 64 of them, so the hero truck spawns on a corner of its own collision and sinks
    # through the rest — reported from a window as "it spawns on a block which doesn't have
    # collision so wheels are half way in the texture". A grid buys nothing on something with no
    # height to vary: its own bounds are exact where the object fills them and the only error is
    # at a notch in its outline.
    if (high.z - low.z) <= FLAT_M:
        var middle: Vector3 = (low + high) * 0.5
        return [{
            "transform": Transform3D(Basis.IDENTITY, middle),
            "half": Vector3(
                maxf((high.x - low.x) * 0.5, MIN_FOOTPRINT_M),
                maxf((high.y - low.y) * 0.5, MIN_FOOTPRINT_M),
                maxf((high.z - low.z) * 0.5, MIN_SLAB_M * 0.5)
            ),
            # Its own bounds, exactly: nothing was approximated, so nothing is too coarse.
            "cell": CELL_M,
        }]
    # **A cap that truncates keeps one side of a building and throws the rest away.** The boxes
    # are emitted in sorted cell order, so an object with more cells than the cap gets its first
    # 4096 and nothing after: `hospital` covered 43.7% of its own footprint with its boxes'
    # centre 25.58 m from the mesh's, and `warehouse01`, `policedepartment` and two dock corners
    # sat exactly on the cap the same way. Reported from a window as "only pillars collision, not
    # the house".
    #
    # So the cell grows until the object fits, which is the right answer now and was not before:
    # a coarser cell used to mean a fatter box, and now that each box hugs the geometry inside
    # its own cell it only means fewer of them. The bound on growth is what stops a cell
    # bridging the inside of a building.
    var cell: float = CELL_M
    var cells: Dictionary = _raster(points, cell)
    while cells.size() > MAX_BOXES_PER_OBJECT and cell < MAX_GROWN_CELL_M:
        cell = minf(cell * 2.0, MAX_GROWN_CELL_M)
        cells = _raster(points, cell)
    return _boxes_of(cells, cell)


## Every cell a triangle soup crosses at this size, as
## `cell -> [bottom, top, left, right, near, far]` — the box the geometry in that cell actually
## occupies, not the cell.
##
## **The cell decides where a box is, not how big it is.** A cell used to contribute its own full
## width, so a 0.1 m lamp post came out as a 0.7 m column: seven times too thick, reported from a
## window in exactly those words. What is kept instead is the extent of the geometry inside the
## cell, clipped to the cell so that a triangle crossing four of them does not make all four as
## wide as itself. A surface that fills its cell still gets the whole cell; a post gets a post.
##
## Narrow boxes are only safe because `RorObstacles::contact` picks the face a node can actually
## leave by. Before that, a tall thin box was a trap: a node pushed into one left through whatever
## face the velocity suggested, and on a thin box that is usually the wrong one.
static func _raster(points: PackedVector3Array, cell: float) -> Dictionary:
    var cells: Dictionary = {}
    for first: int in range(0, points.size() - 2, 3):
        var a: Vector3 = points[first]
        var b: Vector3 = points[first + 1]
        var c: Vector3 = points[first + 2]
        var low: Vector3 = a.min(b).min(c)
        var high: Vector3 = a.max(b).max(c)
        for x: int in range(int(floor(low.x / cell)), int(floor(high.x / cell)) + 1):
            for y: int in range(int(floor(low.y / cell)), int(floor(high.y / cell)) + 1):
                var key: Vector2i = Vector2i(x, y)
                # The part of this triangle's own box that lies in this cell.
                var left: float = maxf(low.x, float(x) * cell)
                var right: float = minf(high.x, float(x + 1) * cell)
                var near: float = maxf(low.y, float(y) * cell)
                var far: float = minf(high.y, float(y + 1) * cell)
                var span: PackedFloat32Array = cells.get(
                    key, PackedFloat32Array([INF, -INF, INF, -INF, INF, -INF])
                ) as PackedFloat32Array
                cells[key] = PackedFloat32Array([
                    minf(span[0], low.z), maxf(span[1], high.z),
                    minf(span[2], left), maxf(span[3], right),
                    minf(span[4], near), maxf(span[5], far),
                ])
    return cells


## One box per cell, each the box the geometry in that cell occupies.
static func _boxes_of(cells: Dictionary, cell: float) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    var keys: Array = cells.keys()
    # Sorted, so one mesh always produces the same boxes in the same order.
    keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
        return a.x < b.x if a.x != b.x else a.y < b.y
    )
    for key: Vector2i in keys:
        if out.size() >= MAX_BOXES_PER_OBJECT:
            break
        var span: PackedFloat32Array = cells[key] as PackedFloat32Array
        var height: float = maxf(span[1] - span[0], MIN_SLAB_M)
        # A box no thinner than the detail it stands for: a wire or a panel edge is a plane in
        # one direction, and a box with no width at all is a box a solver cannot push out of.
        var across: float = maxf(span[3] - span[2], MIN_FOOTPRINT_M)
        var along: float = maxf(span[5] - span[4], MIN_FOOTPRINT_M)
        out.append({
            "transform": Transform3D(Basis.IDENTITY, Vector3(
                (span[2] + span[3]) * 0.5, (span[4] + span[5]) * 0.5,
                (span[0] + span[1]) * 0.5
            )),
            "half": Vector3(across * 0.5, along * 0.5, height * 0.5),
            # What this object was approximated at, for the caller to judge whether that is
            # fine enough to mean anything once the object's own scale is applied.
            "cell": cell,
        })
    return out
