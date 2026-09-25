extends GateBase
## The ground the solver collides against is the ground Terrain3D draws.
##
## PLAN §1 M1 acceptance 6. A mismatch between the surface a renderer shows and the surface a
## simulation resolves against is the classic "wheels floating, wheels sunk" bug, and it is
## invisible in any check that only looks at one of the two. It has to be a number.
##
## The comparison is taken *off* the grid, at positions on neither side's vertices. Sampled
## only on the grid this would pass with the heightfield transposed.
##
## What it measures is the wiring — origin, spacing, row order, units — and not interpolation
## error. The solver's grid is copied from the terrain's own lattice and both sides then
## interpolate bilinearly, so when the wiring is right they agree exactly, and the measured
## worst case over 400 samples is 0.0 mm. The tolerance is therefore set near zero rather
## than at some plausible-looking slack: at 50 mm this gate passed a heightfield offset by
## half a cell, which is a 0.5 m horizontal shift of the whole world and precisely the fault
## it exists to catch.

const SAMPLES: int = 400
## Generous headroom over the 0.0 mm this measures when correct, and tight enough that a
## half-cell offset — which reads 41.9 mm — fails loudly.
const TOLERANCE_M: float = 0.002
## And the surfaces must actually have shape, or agreeing about a flat plane proves nothing.
const MIN_RELIEF_M: float = 5.0


static func meta() -> Dictionary:
    return {
        "name": "terrain_collision_agreement",
        "proves": "the height the solver collides against and the height Terrain3D draws agree across the terrain, between grid vertices as well as on them",
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "%d samples off the grid within %.1f mm; terrain relief at least %.0f m"
            % [SAMPLES, TOLERANCE_M * 1000.0, MIN_RELIEF_M]
        ),
        "why": (
            "a visual-versus-collision mismatch puts the wheels above or below the ground"
            + " and looks like a suspension fault, a tyre-radius fault or a spawn fault"
            + " depending on which one you check first. Terrain3D's own height query is the"
            + " outside oracle here: it is what the renderer uses, and the solver's copy has"
            + " to match it."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    if not ClassDB.class_exists("Terrain3D"):
        return ok("skipped: Terrain3D is not installed. Run tools/build_terrain3d.sh", 0)
    var err: String = harness.setup_for("hero_3q")
    if err != "":
        return fail(err)

    var terrain: Node3D = ValleyTerrain.create()
    if terrain == null:
        return fail("Terrain3D is registered but would not instantiate")
    harness.world.add_child(terrain)
    # Terrain3D finishes building only once it is inside a World3D, which is a frame away.
    await harness.advance_frames(2, "static", "terrain")
    var built: String = ValleyTerrain.populate(terrain)
    if built != "":
        return fail(built)
    await harness.advance_frames(1, "static", "terrain")

    var data: Object = terrain.get("data")
    var size: int = TerrainCfg.MAP_SIZE
    var spacing: float = TerrainCfg.VERTEX_SPACING
    var solver: RefCounted = ClassDB.instantiate("RorSolver") as RefCounted
    if solver == null:
        return fail("RorSolver is not registered: the GDExtension did not load")
    var applied: String = TerrainHeightfield.apply(
        solver, data, TerrainCfg.ORIGIN, size, size, spacing
    )
    if applied != "":
        return fail(applied)

    # Off the grid on both axes, and away from the region edge where Terrain3D's own
    # interpolation runs out of neighbours.
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = HarnessCfg.SEED
    var worst: float = 0.0
    var worst_at: Vector3 = Vector3.ZERO
    var lowest: float = INF
    var highest: float = -INF
    var margin: float = 4.0 * spacing
    for _i: int in SAMPLES:
        var position: Vector3 = Vector3(
            TerrainCfg.ORIGIN.x + rng.randf_range(margin, float(size) * spacing - margin),
            0.0,
            TerrainCfg.ORIGIN.z + rng.randf_range(margin, float(size) * spacing - margin)
        )
        var drawn: float = data.call("get_height", position) as float
        var collided: float = solver.ground_height_at(position)
        if not is_finite(drawn) or not is_finite(collided):
            return fail("height at %v is not finite: drawn %f, collided %f" % [
                position, drawn, collided])
        lowest = minf(lowest, drawn)
        highest = maxf(highest, drawn)
        var difference: float = absf(drawn - collided)
        if difference > worst:
            worst = difference
            worst_at = position
    var relief: float = highest - lowest
    if relief < MIN_RELIEF_M:
        return fail(
            "the terrain is only %.2f m from its lowest sample to its highest: agreeing"
            % relief
            + " about a flat surface proves nothing",
            relief
        )
    if worst > TOLERANCE_M:
        return fail(
            "at %v the terrain draws %.3f m and the solver collides at %.3f m, %.3f m apart"
            % [
                worst_at,
                data.call("get_height", worst_at),
                solver.ground_height_at(worst_at),
                worst,
            ],
            worst
        )
    return ok(
        "%d samples off the grid over %.1f m of relief: worst disagreement %.1f mm at %v"
        % [SAMPLES, relief, worst * 1000.0, worst_at],
        worst
    )
