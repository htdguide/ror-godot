class_name TerrainHeightfield
extends RefCounted
## Copies a terrain's heights out in bulk, for the solver to stand on.
##
## The solver cannot ask the terrain a question per node per substep: at 2 kHz with hundreds
## of nodes that is millions of calls a second across the scripting boundary, and the terrain
## would cost more than the simulation. So the heights are read once into a flat array and
## sampled in C++.
##
## This is the seam PLAN §0.6 describes as the collision bridge. It deliberately knows nothing
## about how the terrain was built or what is drawing it — it takes a `Terrain3DData` and
## gives back a grid — so the same bridge serves a generated valley, an imported DEM, or a
## legacy Rigs of Rods terrain on its own path.


## Reads a `width` x `depth` grid of heights starting at `origin`, every `spacing` metres.
## Returns {"heights": PackedFloat32Array, "width", "depth", "origin", "spacing"}.
static func read(
    data: Object, origin: Vector3, width: int, depth: int, spacing: float
) -> Dictionary:
    var heights: PackedFloat32Array = PackedFloat32Array()
    heights.resize(width * depth)
    for z: int in depth:
        var row: int = z * width
        for x: int in width:
            var world: Vector3 = Vector3(
                origin.x + float(x) * spacing, 0.0, origin.z + float(z) * spacing
            )
            var height: float = data.call("get_height", world) as float
            # Terrain3D reports NaN for a hole or a position outside every region. A hole is
            # not a height, and handing one to the solver puts a node's position beyond
            # recovery on the next step.
            heights[row + x] = height if is_finite(height) else 0.0
    return {
        "heights": heights,
        "width": width,
        "depth": depth,
        "origin": Vector3(origin.x, 0.0, origin.z),
        "spacing": spacing,
    }


## Reads the terrain and hands it to the solver in one step. Returns "" on success.
static func apply(solver: RefCounted, data: Object, origin: Vector3, width: int, depth: int,
        spacing: float) -> String:
    if data == null:
        return "the terrain has no data object: it has not finished entering the tree"
    var field: Dictionary = read(data, origin, width, depth, spacing)
    var accepted: bool = solver.set_heightfield(
        field["heights"] as PackedFloat32Array,
        field["width"] as int,
        field["depth"] as int,
        field["origin"] as Vector3,
        field["spacing"] as float
    )
    if not accepted:
        return "the solver rejected a %dx%d heightfield at %.2f m spacing" % [width, depth, spacing]
    return ""
