extends GateBase
## A road swept from a line of points is a road a vehicle rests on.
##
## Building the geometry and making it solid are different jobs, and this project did the first
## one first: 15,904 triangles of carriageway appeared across the library and a truck drove
## through all of it. Upstream registers a collision triangle per quad; this project's solver
## takes boxes, so the carriageway becomes one box per segment lying along it.
##
## **The oracle is the road's own highest point and the rig's own resting height.** Port Starling
## carries a jetty whose deck stands 14 m over the seabed, which the terrain's files say and
## nothing here chose. The gate drops the hero truck there and requires it to rest exactly as it
## rests on open ground — a figure measured in the same run, because how high a resting truck's
## lowest node sits is the truck's business and is written down nowhere.
##
## Resting on the deck and falling to the ground below are 14 m apart, so the verdict does not
## turn on a tolerance.

const TERRAIN_DIR: String = "assets/terrains/Starling-Island"
const TERRN2: String = "starling-port"
const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
## Below this clearance the deck and the ground are the same place and there is nothing to tell
## apart.
const MIN_CLEARANCE_M: float = 2.0
## How far the rest on the road may differ from the rest on open ground.
const REST_TOLERANCE_M: float = 0.15


static func meta() -> Dictionary:
    return {
        "name": "a_swept_road_is_solid",
        "proves": "the carriageway swept from a terrain's road points is solid, so a vehicle rests on a raised road instead of falling through it",
        "builds_on": ["a_road_of_points_is_swept_into_a_road"],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "the rig rests on the road within %.2f m of how it rests on open ground"
            % REST_TOLERANCE_M
        ),
        "why": (
            "the geometry was built before it was made solid, so 15,904 triangles of road"
            + " appeared across the library and a truck drove through all of it."
        ),
        "budget_s": 240.0,
        "needs_gpu": false,
        "milestone": "C2",
    }


func run(_harness: Node) -> Dictionary:
    var directory: String = SourceScan.repo_root().path_join(TERRAIN_DIR)
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(directory) or not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: this checkout has no swept road to drop onto", 0)
    var loaded: Dictionary = RorTerrain.load_from(directory, TERRN2)
    if (loaded["error"] as String) != "":
        return fail(loaded["error"] as String)
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain

    var spot: Dictionary = _highest_deck(terrain)
    if spot.is_empty():
        return ok("skipped: this terrain sweeps no road clear of the ground", 0)
    var clearance: float = (spot["top"] as float) - (spot["ground"] as float)
    if clearance < MIN_CLEARANCE_M:
        return ok(
            "skipped: the clearest road stands %.1f m over the ground, under %.1f"
            % [clearance, MIN_CLEARANCE_M], clearance
        )

    var measured: Dictionary = RestDrop.measure(
        terrain, mod_dir, TRUCK, spot["at"] as Vector3, spot["top"] as float
    )
    if (measured["error"] as String) != "":
        return fail(measured["error"] as String)
    var difference: float = (measured["on_surface"] as float) - (measured["on_ground"] as float)
    if absf(difference) > REST_TOLERANCE_M:
        return fail(
            "resting on open ground the rig's lowest node sits %.2f m above it; dropped onto a"
            % measured["on_ground"]
            + " road deck at %.2f m over ground at %.2f, it sits %.2f m above the deck — %.2f m"
            % [spot["top"], spot["ground"], measured["on_surface"], difference]
            + " out, so it is on the ground %.1f m below instead" % clearance,
            difference
        )
    return ok(
        "dropped onto a road deck standing %.1f m clear of the ground, the rig settled %.2f m"
        % [clearance, measured["on_surface"]]
        + " above it, against %.2f m on open ground" % measured["on_ground"],
        difference
    )


## The road **segment** whose middle stands furthest above the heightmap, from the terrain's own
## files. The map decides where this is tested.
##
## A segment rather than a point, because a point is only a cross-section: a block's outermost
## point, or one whose neighbours are kinds this does not build, has no carriageway through it at
## all. A first draft picked the highest point and landed on a jetty's end 135 m from the nearest
## road, then reported the road as not solid.
func _highest_deck(terrain: RorTerrain) -> Dictionary:
    var best: Dictionary = {}
    var clearest: float = -INF
    for group: Array[Dictionary] in RorProceduralRoad.groups(terrain):
        for index: int in range(1, group.size()):
            var here: Dictionary = RoadSection.resolved(terrain, group[index])
            var last: Dictionary = RoadSection.resolved(terrain, group[index - 1])
            if not RoadSection.KINDS.has(here["kind"]):
                continue
            if not RoadSection.KINDS.has(last["kind"]):
                continue
            var at: Vector3 = (
                (here["position"] as Vector3) + (last["position"] as Vector3)
            ) * 0.5
            var ground: float = terrain.height_at_world(at.x, at.z)
            if at.y - ground <= clearest:
                continue
            clearest = at.y - ground
            best = {"at": at, "top": at.y, "ground": ground}
    return best
