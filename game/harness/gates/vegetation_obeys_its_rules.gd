extends GateBase
## Everything that grows stands on the ground, out of the water, off the road and off the test
## track — and the conifer stand is a stand rather than a scattering.
##
## Vegetation is placed by a pure function of position, so the interesting failures are not
## crashes: they are a forest standing a metre above the hillside, a tree in the middle of the
## ford, a hedge across the road the switchback shots are of, or a "stand" that is the same
## density as the rest of the valley and therefore not a stand. Each of those renders perfectly
## well and is wrong.
##
## Every instance is checked, not a sample: the placement is 20,000 plants and the rules are
## cheap, and a rule that holds for 99% of a forest is a rule that does not hold.

## How far a plant may sit from the terrain under it. Not zero: the pose is built from the same
## height query, so this is float noise and nothing else.
const GROUND_TOLERANCE_M: float = 0.001
## A stand is denser than the scattering around it by at least this much, or it is not a stand.
const MIN_STAND_RATIO: float = 3.0
## And there has to be a forest at all. Below this the valley reads as bare ground from the ridge.
const MIN_CONIFERS: int = 1200
## Above this the placement is dense enough to be worth a second look: 20,000 multimesh instances
## is cheap, 200,000 is a frame-rate decision nobody took deliberately.
const MAX_PLANTS: int = 60000


static func meta() -> Dictionary:
    return {
        "name": "vegetation_obeys_its_rules",
        "proves": "every plant stands on the terrain, clear of the water, the road and the test track, and the conifer stand is denser than the valley around it",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "every instance within %.0f mm of the ground, none inside the road clearance, none"
            % (GROUND_TOLERANCE_M * 1000.0)
            + " below the lake, none on the test track; stand at least %.0fx the background"
            % MIN_STAND_RATIO
            + " density; %d to %d plants" % [MIN_CONIFERS, MAX_PLANTS]
        ),
        "why": (
            "the ways placement goes wrong all render: a forest floating over the hillside, a"
            + " tree in the ford, a hedge across the road the switchback shots are of, a stand"
            + " no denser than the scattering around it. None of them crash and none of them"
            + " show up in a frame that nobody framed that way."
        ),
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var placements: Dictionary = ValleyVegetation.place()
    var conifers: Array[Transform3D] = (
        placements[ValleyVegetation.CONIFER_ID] as Array[Transform3D]
    )
    var shrubs: Array[Transform3D] = placements[ValleyVegetation.SHRUB_ID] as Array[Transform3D]
    var total: int = conifers.size() + shrubs.size()
    if conifers.size() < MIN_CONIFERS:
        return fail(
            "%d conifers grew, under %d: the valley is bare" % [conifers.size(), MIN_CONIFERS],
            conifers.size()
        )
    if total > MAX_PLANTS:
        return fail(
            "%d plants grew, over %d: that is a frame-rate decision, not a placement"
            % [total, MAX_PLANTS],
            total
        )

    var broken: String = _check_rules(conifers + shrubs)
    if broken != "":
        return fail(broken)

    var density: Dictionary = _stand_density(conifers)
    var ratio: float = density["ratio"] as float
    if ratio < MIN_STAND_RATIO:
        return fail(
            "the stand holds %.1f conifers a hectare against %.1f outside it, only %.1fx:"
            % [density["inside"] as float, density["outside"] as float, ratio]
            + " it is a scattering with a name",
            ratio
        )
    return ok(
        "%d conifers and %d shrubs, every one on the ground; the stand holds %.0f a hectare"
        % [conifers.size(), shrubs.size(), density["inside"] as float]
        + " against %.1f outside it (%.1fx)" % [density["outside"] as float, ratio],
        ratio
    )


## The rules every plant obeys, checked one plant at a time. Returns "" or the first breach, named
## with the position that broke it.
func _check_rules(plants: Array[Transform3D]) -> String:
    var water: float = ValleyShape.lake_water_y() + VegetationCfg.SHORE_CLEARANCE_M
    for pose: Transform3D in plants:
        var at: Vector3 = pose.origin
        var ground: float = ValleyShape.height_at_world(at.x, at.z)
        if absf(at.y - ground) > GROUND_TOLERANCE_M:
            return (
                "a plant at %v stands %.3f m off the ground, which is at %.3f m"
                % [at, at.y - ground, ground]
            )
        if at.y < water:
            return "a plant at %v is standing in the lake, whose surface is %.2f m" % [at, water]
        if absf(at.z) < VegetationCfg.MIN_ABS_Z_M:
            return (
                "a plant at %v is on the test track, inside %.0f m of the centre line"
                % [at, VegetationCfg.MIN_ABS_Z_M]
            )
        var road: float = ValleyShape.road_distance(at.x, at.z)
        if road <= VegetationCfg.ROAD_CLEARANCE_M:
            return "a plant at %v is %.1f m from the road's centre line" % [at, road]
        if ValleyVegetation.slope_at(at.x, at.z) > VegetationCfg.MAX_SLOPE:
            return (
                "a plant at %v is on ground at %.0f%%, steeper than the %.0f%% limit"
                % [at, ValleyVegetation.slope_at(at.x, at.z) * 100.0,
                   VegetationCfg.MAX_SLOPE * 100.0]
            )
    return ""


## How dense the stand is against the rest of the valley, in conifers per hectare.
##
## The background is everything outside the stand that is *allowed* to grow trees, not the whole
## map: comparing against 4 km² of lake, road and test track would make any stand look dense.
func _stand_density(conifers: Array[Transform3D]) -> Dictionary:
    var inside: int = 0
    for pose: Transform3D in conifers:
        var at: Vector3 = pose.origin
        if (at.x >= ValleyLayout.STAND_WEST_M and at.x <= ValleyLayout.STAND_EAST_M
                and at.z <= ValleyLayout.STAND_NEAR_Z_M and at.z >= ValleyLayout.STAND_FAR_Z_M):
            inside += 1
    var stand_hectares: float = (
        absf(ValleyLayout.STAND_EAST_M - ValleyLayout.STAND_WEST_M)
        * absf(ValleyLayout.STAND_NEAR_Z_M - ValleyLayout.STAND_FAR_Z_M)
    ) / 10000.0
    var plantable: float = _plantable_hectares() - stand_hectares
    var outside: float = float(conifers.size() - inside) / maxf(plantable, 0.01)
    var inside_density: float = float(inside) / maxf(stand_hectares, 0.01)
    return {
        "inside": inside_density,
        "outside": outside,
        "ratio": inside_density / maxf(outside, 0.01),
    }


## How much of the valley the rules allow anything to grow on, in hectares, sampled on a grid
## coarser than the placement's own.
func _plantable_hectares() -> float:
    var half: float = 0.5 * float(TerrainCfg.MAP_SIZE) * TerrainCfg.VERTEX_SPACING
    var step: float = 24.0
    var columns: int = int(2.0 * half / step)
    var allowed: int = 0
    var water: float = ValleyShape.lake_water_y() + VegetationCfg.SHORE_CLEARANCE_M
    for column: int in columns:
        var x: float = -half + (float(column) + 0.5) * step
        for row: int in columns:
            var z: float = -half + (float(row) + 0.5) * step
            if absf(z) < VegetationCfg.MIN_ABS_Z_M:
                continue
            var surface: String = GroundModels.name_of(ValleyShape.surface_at_world(x, z))
            if not VegetationCfg.SURFACES.has(surface):
                continue
            if ValleyShape.height_at_world(x, z) < water:
                continue
            if ValleyVegetation.slope_at(x, z) > VegetationCfg.MAX_SLOPE:
                continue
            allowed += 1
    return float(allowed) * step * step / 10000.0
