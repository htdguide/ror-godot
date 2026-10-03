class_name RestDrop
extends RefCounted
## Drops the hero vehicle onto something and reports where it comes to rest.
##
## **The expectation is the rig's own.** How high a resting truck's lowest node sits above what
## it is resting on is the truck's business — tyre radius, suspension travel, how far the wheels
## sink — and none of it is written down anywhere a gate could read. So a drop is always measured
## twice: once on the terrain's open ground, which is the answer, and once on the thing under
## test, which has to match it. Nothing here is a clearance this project decided a vehicle should
## have.
##
## Shared because two gates want it: one asks whether the collision box an object definition
## declares is solid, the other whether a swept road is. They differ only in where they drop.

const SUBSTEP_HZ: float = 2000.0
const SETTLE_FRAMES: int = 240
## How far above the surface to let go from.
const DROP_M: float = 0.5


## Returns `{"error", "on_ground", "on_surface"}`, both offsets in metres above the surface each
## was dropped onto. `at` is where on the map to drop, `surface` the height it should land on.
static func measure(
    terrain: RorTerrain, mod_dir: String, truck_file: String, at: Vector3, surface: float
) -> Dictionary:
    var out: Dictionary = {"error": "", "on_ground": 0.0, "on_surface": 0.0}
    var rig: Dictionary = RigBuilder.from_file(mod_dir, truck_file, 0.0)
    if (rig["error"] as String) != "":
        out["error"] = rig["error"] as String
        return out
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    give_terrain(solver, terrain)
    RorObjectCollision.apply(terrain, solver)
    solver.set_ground(0.0, true)

    var start: Vector3 = terrain.start_position()
    out["on_ground"] = _rest(
        solver, truck, Vector3(start.x, 0.0, start.z), DROP_M,
        terrain.height_at_world(start.x, start.z)
    )
    if not is_finite(out["on_ground"] as float):
        out["error"] = "the rig would not settle on open ground, so there is nothing to compare to"
        return out
    # `place` measures its drop from the heightfield, which is what the surface stands over, so
    # the clearance it is given is the whole way up.
    var clearance: float = surface - terrain.height_at_world(at.x, at.z) + DROP_M
    out["on_surface"] = _rest(
        solver, truck, Vector3(at.x, 0.0, at.z), clearance, surface
    )
    if not is_finite(out["on_surface"] as float):
        out["error"] = "the solver went non-finite while the rig settled"
    return out


## Hands a terrain's own heights to a solver.
static func give_terrain(solver: RefCounted, terrain: RorTerrain) -> void:
    var grid: Dictionary = terrain.lattice()
    var size: int = grid["size"] as int
    var heights: PackedFloat32Array = PackedFloat32Array()
    heights.resize(size * size)
    for z: int in size:
        var row: int = z * size
        for x: int in size:
            heights[row + x] = terrain.height_at(x, z)
    solver.set_heightfield(
        heights, size, size, grid["origin"] as Vector3, grid["spacing"] as float
    )


## Where the rig's lowest node comes to rest above `surface`. INF when it never settles.
static func _rest(
    solver: RefCounted, truck: TruckParser, origin: Vector3, clearance: float, surface: float
) -> float:
    RigBuilder.place(solver, truck, origin, 0.0, clearance)
    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    for _frame: int in SETTLE_FRAMES:
        solver.step(dt, chunk)
    var lowest: float = INF
    for index: int in truck.nodes.size():
        var node: Vector3 = solver.get_node_position(index)
        if not is_finite(node.y):
            return INF
        lowest = minf(lowest, node.y)
    return lowest - surface
