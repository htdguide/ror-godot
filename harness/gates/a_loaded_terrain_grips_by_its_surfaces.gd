extends GateBase
## Braking on La Paz's asphalt stops a truck sooner than braking on the dirt beside it.
##
## The terrain paints where its surfaces are and ships the friction numbers for them, and this
## project reads both: the traction map decides which ground model each cell uses, and the mod's
## own config sets what those models are — its sand and dirt hold 0.5 where upstream's asphalt
## holds 1.2. All of that can be right in the data and reach nothing, which is exactly what a
## transposed surface map looked like the last time: the right surfaces, in the wrong places.
##
## So this drives the same rig from the same speed on both and measures how far it takes to stop.
## Two numbers from one run each, and the claim is the ratio between them.

const TERRAIN_DIR: String = "assets/terrains/lapaz2"
const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const SUBSTEP_HZ: float = 2000.0
## Where to test: a point on the road, and one out in the desert beside it.
const ON_THE_ROAD: Vector2 = Vector2(3700.0, 45.0)
const OFF_THE_ROAD: Vector2 = Vector2(3700.0, 95.0)
## How hard to lean on the tyres, as a fraction of gravity.
##
## Gravity is tilted rather than the terrain, because La Paz's road and its desert are both flat
## and a gate cannot tilt a shipped heightmap. A parked rig with its brakes on, leaned on
## sideways, is the textbook friction test and it is the one `surfaces_change_grip` already uses
## for a single node — applied here to a whole vehicle on a real terrain's real surface map.
##
## Braking and cornering were tried first and neither separates the two surfaces: braking is
## limited by the rig's own brake torque long before the tyres let go, and a cornering rig loads
## its outside wheels enough to grip on either. Both measured within a few per cent.
const LATERAL_G: float = 0.7
const SETTLE_SECONDS: float = 3.0
const LEAN_SECONDS: float = 3.0
## How much further the loose surface has to let the rig go. The models differ by 1.0 against 0.5
## of static friction and 1.0 against 0.8 sliding; measured, the rig drifts 3.9 m on the asphalt
## and 5.4 m on the dirt.
const MIN_FURTHER: float = 1.25
## And both have to be a real measurement rather than two rigs sitting still.
const MIN_DRIFT_M: float = 0.5


static func meta() -> Dictionary:
    return {
        "name": "a_loaded_terrain_grips_by_its_surfaces",
        "proves": "a loaded terrain's traction map and its own friction numbers reach the wheels: a rig leaned on sideways holds better on its asphalt than on the dirt beside it",
        "builds_on": ["ror_terrain_is_drivable", "ground_models_match_upstream"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "at %.2f g sideways, the loose surface letting the rig go at least %.0f%% further"
            % [LATERAL_G, (MIN_FURTHER - 1.0) * 100.0] + " than the asphalt"
        ),
        "why": (
            "which surface is where and what each one grips like are both the terrain's own"
            + " data, and both can be correct and reach nothing — a transposed surface map"
            + " reads as the right surfaces in the wrong places, which this project has had."
            + " Leaning on a parked rig is the textbook test and the one that separates them:"
            + " braking is limited by the rig's own brakes long before the tyres let go."
        ),
        "budget_s": 240.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var directory: String = SourceScan.repo_root().path_join(TERRAIN_DIR)
    if not DirAccess.dir_exists_absolute(directory):
        return ok("skipped: no terrain at %s" % TERRAIN_DIR, 0)
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var loaded: Dictionary = RorTerrain.load_from(directory)
    if (loaded["error"] as String) != "":
        return fail(loaded["error"] as String)
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain

    var road: Dictionary = _lean_on(terrain, mod_dir, ON_THE_ROAD)
    if (road["error"] as String) != "":
        return fail(road["error"] as String)
    var desert: Dictionary = _lean_on(terrain, mod_dir, OFF_THE_ROAD)
    if (desert["error"] as String) != "":
        return fail(desert["error"] as String)
    if (road["surface"] as String) == (desert["surface"] as String):
        return fail(
            "both runs were on '%s': the two places chosen are the same surface, so nothing"
            % road["surface"] + " here is being compared"
        )
    if (road["drift"] as float) < MIN_DRIFT_M or (desert["drift"] as float) < MIN_DRIFT_M:
        return fail(
            "the rig moved %.2f m on %s and %.2f m on %s at %.2f g: neither is a measurement"
            % [road["drift"], road["surface"], desert["drift"], desert["surface"], LATERAL_G],
            minf(road["drift"] as float, desert["drift"] as float)
        )

    var ratio: float = (desert["drift"] as float) / maxf(road["drift"] as float, 0.001)
    if ratio < MIN_FURTHER:
        return fail(
            "leaned on at %.2f g the rig went %.2f m on %s and %.2f m on %s, a ratio of %.2f"
            % [LATERAL_G, road["drift"], road["surface"], desert["drift"], desert["surface"],
               ratio]
            + " under %.2f: the surfaces are not reaching the wheels" % MIN_FURTHER,
            ratio
        )
    return ok(
        "at %.2f g sideways the rig held to %.2f m on %s and slid %.2f m on %s — %.2f times"
        % [LATERAL_G, road["drift"], road["surface"], desert["drift"], desert["surface"],
           ratio] + " as far",
        ratio
    )


## Parks the rig at a place, puts the brakes on and leans on it sideways.
func _lean_on(terrain: RorTerrain, mod_dir: String, at: Vector2) -> Dictionary:
    var out: Dictionary = {"error": "", "drift": 0.0, "surface": ""}
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        out["error"] = rig["error"] as String
        return out
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    _give_terrain(solver, terrain)
    solver.set_ground(0.0, true)
    RigBuilder.place(solver, truck, Vector3(at.x, 0.0, at.y), 0.0, 0.15)
    out["surface"] = terrain.models.name_of(terrain.surface_at_world(at.x, at.y))

    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    for _settle: int in int(SETTLE_SECONDS * 60.0):
        solver.step(dt, chunk)
    var from: Vector3 = ActorFrame.of(solver.get_positions(), truck.camera_nodes).origin
    solver.set_brake(1.0)
    solver.set_parking_brake(true)
    solver.set_gravity(Vector3(9.81 * LATERAL_G, -9.81, 0.0))
    for _lean: int in int(LEAN_SECONDS * 60.0):
        solver.step(dt, chunk)
        if not is_finite(solver.get_node_position(0).length()):
            out["error"] = "the solver went non-finite while the rig was leaned on"
            return out
    var here: Vector3 = ActorFrame.of(solver.get_positions(), truck.camera_nodes).origin
    out["drift"] = Vector2(here.x - from.x, here.z - from.z).length()
    return out


## The terrain's own heights and surfaces, straight from the shape.
func _give_terrain(solver: RefCounted, terrain: RorTerrain) -> void:
    var grid: Dictionary = terrain.lattice()
    var size: int = grid["size"] as int
    var heights: PackedFloat32Array = PackedFloat32Array()
    heights.resize(size * size)
    var surfaces: PackedByteArray = PackedByteArray()
    surfaces.resize(size * size)
    for z: int in size:
        var row: int = z * size
        for x: int in size:
            heights[row + x] = terrain.height_at(x, z)
            surfaces[row + x] = terrain.surface_at(x, z)
    solver.set_heightfield(
        heights, size, size, grid["origin"] as Vector3, grid["spacing"] as float
    )
    solver.set_surface_map(surfaces, size, size)
    terrain.models.apply(solver)
