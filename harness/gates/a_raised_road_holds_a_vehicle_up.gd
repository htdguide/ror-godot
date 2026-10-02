extends GateBase
## A road the terrain draws above the ground is a road a vehicle rests on.
##
## **The oracle is the object definition's own collision box.** `road-slab.odef`, in Rigs of Rods'
## base content:
##
##     road-slab.mesh
##     1, 1, 1
##     beginbox
##     boxcoords -5.01, 5.01, -3, 0.3, -5.01, 5.01
##     endbox
##
## Six numbers paired by axis — `minx, maxx, miny, maxy, minz, maxz` — so that is a 10 m slab
## 3.3 m thick whose top is 0.3 m above the object's origin. The author wrote down what is solid
## and where its surface is.
##
## **This project counted those boxes and never built them.** Collision for a terrain's scenery
## was derived by voxelising the visual mesh into columns, and a column shorter than half a metre
## is discarded as drawn detail rather than structure — which is right for wires and kerb lips and
## exactly wrong for a road, whose whole shape is flat. So every raised road on every map was
## drawn and not solid: reported from a session as "visible road has no collision". Port Starling
## places `road-slab` 189 times and `road-park` 139.
##
## **The box is not in the mesh's frame.** Upstream turns an object's visual node by its placement
## rotation and then pitches it -90 degrees, because object meshes are authored Z-up
## (`TerrainObjectManager::LoadTerrainObject`). The collision box gets the placement rotation and
## no pitch (`Collisions::addCollisionBox`), so `boxcoords` reads Y-up. `road-slab`'s `-3 .. 0.3`
## is its thickness, which only makes sense that way round.
##
## **The test is a drop, not a crash, and it is measured against the rig itself.** The gate finds
## the placement in the terrain's own object file whose box top stands furthest above the
## heightmap, puts the hero truck a little above it, and lets go. How high a resting truck's
## lowest node sits is the truck's business — tyre radius, suspension, how far the wheels sink —
## so the gate measures that on open ground first and then requires the same figure on the slab.
## Nothing here is a clearance this project decided a vehicle should have, and the alternative
## outcome is metres lower.

## The terrain to drop on, and the vehicle to drop.
const TERRAIN_DIR: String = "assets/terrains/Starling-Island"
const TERRN2: String = "starling-port"
const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
## Below this clearance there is nothing to tell apart: the slab and the ground are the same place.
const MIN_CLEARANCE_M: float = 2.0
## How much box there has to be either side of its centre for a truck to sit on it.
const MIN_HALF_WIDTH_M: float = 3.0
## How far above the slab to let go from, and how long to let it settle.
const DROP_M: float = 0.5
const SETTLE_FRAMES: int = 240
const SUBSTEP_HZ: float = 2000.0
## How far the rig's rest on the slab may differ from its rest on open ground. A hand's width:
## the two surfaces are flat and the alternative outcome is metres lower.
const REST_TOLERANCE_M: float = 0.15


static func meta() -> Dictionary:
    return {
        "name": "a_raised_road_holds_a_vehicle_up",
        "proves": "an object's own collision box is built and solid, so a road drawn above the ground holds a vehicle up instead of letting it fall through",
        "builds_on": ["a_terrains_own_scenery_is_solid"],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "the rig rests on the declared box top within %.2f m of how it rests on open ground,"
            % REST_TOLERANCE_M + " rather than on the ground metres below"
        ),
        "why": (
            "collision was derived by voxelising the visual mesh, and a column under half a metre"
            + " is discarded as drawn detail — right for wires, exactly wrong for a road, whose"
            + " whole shape is flat. Every raised road on every map was drawn and not solid."
        ),
        "budget_s": 240.0,
        "needs_gpu": false,
        "milestone": "C2",
    }


func run(_harness: Node) -> Dictionary:
    var directory: String = SourceScan.repo_root().path_join(TERRAIN_DIR)
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(directory) or not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: this checkout has no raised road to drop onto", 0)
    var loaded: Dictionary = RorTerrain.load_from(directory, TERRN2)
    if (loaded["error"] as String) != "":
        return fail(loaded["error"] as String)
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain

    var spot: Dictionary = _highest_slab(terrain)
    if spot.is_empty():
        return ok("skipped: no object here declares a collision box clear of the ground", 0)
    var clearance: float = (spot["top"] as float) - (spot["ground"] as float)
    if clearance < MIN_CLEARANCE_M:
        return ok(
            "skipped: the clearest declared box stands %.1f m over the ground, under %.1f"
            % [clearance, MIN_CLEARANCE_M], clearance
        )

    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        return fail(rig["error"] as String)
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    _give_terrain(solver, terrain)
    var solid: int = RorObjectCollision.apply(terrain, solver)
    solver.set_ground(0.0, true)

    # What resting looks like, measured on this terrain's own open ground with the same rig. The
    # answer is the truck's, not this gate's: a tyre's radius and how far the suspension settles
    # under its own weight decide how high the lowest node ends up, and neither is written down
    # anywhere this gate could read.
    var start: Vector3 = terrain.start_position()
    var on_ground: float = _rest_offset(
        solver, truck, Vector3(start.x, 0.0, start.z), DROP_M,
        terrain.height_at_world(start.x, start.z)
    )
    if not is_finite(on_ground):
        return fail("the rig would not settle on open ground, so there is nothing to compare to")

    var at: Vector3 = spot["at"] as Vector3
    # Let go from just above the slab. `place` measures its drop from the heightfield, which is
    # what the slab stands over, so the clearance it is given is the whole way up.
    var on_slab: float = _rest_offset(
        solver, truck, Vector3(at.x, 0.0, at.z), clearance + DROP_M, spot["top"] as float
    )
    if not is_finite(on_slab):
        return fail("the solver went non-finite while the rig settled on the slab")
    var difference: float = on_slab - on_ground
    if absf(difference) > REST_TOLERANCE_M:
        return fail(
            "resting on open ground the rig's lowest node sits %.2f m above it; dropped onto %s,"
            % [on_ground, spot["name"]]
            + " whose own box top is at %.2f m over ground at %.2f, it sits %.2f m above the box"
            % [spot["top"], spot["ground"], on_slab]
            + " — %.2f m out, so it is resting on the ground %.1f m below instead"
            % [difference, clearance],
            difference
        )
    return ok(
        "%d solid boxes; dropped onto %s standing %.1f m clear of the ground, the rig settled"
        % [solid, spot["name"], clearance]
        + " %.2f m above the box top its definition declares, against %.2f m on open ground"
        % [on_slab, on_ground],
        difference
    )


## Where the rig's lowest node comes to rest above `surface`, dropped from `clearance` over the
## heightfield at `origin`. INF when it never settles.
func _rest_offset(
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


## The declared collision box standing furthest above the heightmap that a truck could sit on.
##
## Chosen from the terrain's own files rather than named here, so the map decides where this is
## tested. Three conditions, each for a reason:
##
## - **Unrotated**, both the placement and the box, so that where the box's top face is needs no
##   arithmetic this gate could get wrong. Enough of them are.
## - **Wider than the truck in both directions**, because the drop lands on the box's own centre
##   and a rig hanging over an edge tips off it. A first version dropped on the placement origin
##   instead, which on a crane whose box starts a metre away put most of the truck over the side
##   and read as 0.91 m of penetration.
## - **Clear of the ground**, which is the whole question.
func _highest_slab(terrain: RorTerrain) -> Dictionary:
    var state: Dictionary = RorObjects.state(terrain)
    var best: Dictionary = {}
    var clearest: float = -INF
    for placement: Dictionary in RorObjects.placements(terrain):
        if not (placement["rotation"] as Vector3).is_zero_approx():
            continue
        var name: String = placement["name"] as String
        var definition: Dictionary = RorObjects.definition(terrain, name, state)
        if (definition.get("error", "") as String) != "":
            continue
        var scale: Vector3 = definition["scale"] as Vector3
        for box: Dictionary in definition["boxes"] as Array[Dictionary]:
            if (box["virtual"] as bool) or not (box["rotation"] as Vector3).is_zero_approx():
                continue
            var low: Vector3 = (box["min"] as Vector3) * scale
            var high: Vector3 = (box["max"] as Vector3) * scale
            var half: Vector3 = ((high - low) * 0.5).abs()
            if half.x < MIN_HALF_WIDTH_M or half.z < MIN_HALF_WIDTH_M:
                continue
            var centre: Vector3 = (placement["position"] as Vector3) + (low + high) * 0.5
            var top: float = centre.y + half.y
            var ground: float = terrain.height_at_world(centre.x, centre.z)
            if top - ground <= clearest:
                continue
            clearest = top - ground
            best = {"name": name, "at": centre, "top": top, "ground": ground}
    return best


## The terrain's own heights, straight from the shape.
func _give_terrain(solver: RefCounted, terrain: RorTerrain) -> void:
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
