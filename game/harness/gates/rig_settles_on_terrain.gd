extends GateBase
## The rig lands on the terrain and stays on it, on ground that is not flat.
##
## Everything before this stands the rig on a plane at y = 0, where "on the ground" and "at
## zero" are the same statement and a solver that ignored the terrain entirely would pass.
## Here the spawn point is on a valley wall, so the two come apart: each wheel rests at a
## different height, and each has to rest at the height of the terrain underneath *it*.
##
## The oracle is the terrain's own height query, taken under each axle after the rig has
## settled. It is the same surface the renderer draws, so this is also the check that the rig
## and the visible ground are in the same place — measured per wheel rather than once for the
## whole vehicle, because a rig resting on a slope at the right average height can still have
## two wheels buried and two in the air.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const SUBSTEP_HZ: float = 2000.0
const SETTLE_SECONDS: float = 3.0
## On the valley wall, off the floor, where the ground is sloped but not steep enough for a
## parked vehicle to slide.
const SPAWN: Vector3 = Vector3(20.0, 0.0, 160.0)
const SPAWN_CLEARANCE_M: float = 0.15
## An axle sits a tyre radius above the ground, plus whatever the tyre has squashed by. The
## bound is on the error against that, not on the height itself.
const AXLE_TOLERANCE_M: float = 0.12
## The terrain under the rig has to actually be sloped, or this is the flat-plane test again.
const MIN_SLOPE_M: float = 0.15


static func meta() -> Dictionary:
    return {
        "name": "rig_settles_on_terrain",
        "proves": "the rig lands on sloped terrain with every wheel at the height of the ground beneath it, not through it and not above it",
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "each axle within %.2f m of a tyre radius above the terrain under it; the"
            % AXLE_TOLERANCE_M
            + " ground under the rig varies by at least %.2f m" % MIN_SLOPE_M
        ),
        "why": (
            "on a flat plane, resting on the ground and resting at zero are the same"
            + " measurement, so a solver that never read the terrain would pass. On a slope"
            + " they differ per wheel, and per wheel is the only way to tell a rig sitting"
            + " correctly from one sitting at the right average height with two wheels"
            + " buried."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    if not ClassDB.class_exists("Terrain3D"):
        return ok("skipped: Terrain3D is not installed. Run tools/build_terrain3d.sh", 0)
    var err: String = harness.setup_for("hero_3q")
    if err != "":
        return fail(err)

    var terrain: Node3D = ValleyTerrain.create()
    harness.world.add_child(terrain)
    await harness.advance_frames(2, "static", "terrain")
    var built: String = ValleyTerrain.populate(terrain)
    if built != "":
        return fail(built)
    var data: Object = terrain.get("data")

    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        return fail(rig["error"] as String)
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    var applied: String = TerrainHeightfield.apply(
        solver, data, TerrainCfg.ORIGIN, TerrainCfg.MAP_SIZE, TerrainCfg.MAP_SIZE,
        TerrainCfg.VERTEX_SPACING
    )
    if applied != "":
        return fail(applied)
    solver.set_ground(0.0, true)
    _place(solver, truck)

    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    for frame: int in int(SETTLE_SECONDS * 60.0):
        solver.step(dt, chunk)
        if not is_finite(solver.get_node_position(0).length()):
            return fail("the rig went non-finite %.2f s into settling" % (float(frame) / 60.0))

    var worst: float = 0.0
    var worst_wheel: int = 0
    var lowest_ground: float = INF
    var highest_ground: float = -INF
    var report: PackedStringArray = PackedStringArray()
    for index: int in truck.wheels.size():
        var wheel: Dictionary = truck.wheels[index]
        var axle: Vector3 = (
            solver.get_node_position(wheel["node1"] as int)
            + solver.get_node_position(wheel["node2"] as int)
        ) * 0.5
        var ground: float = data.call("get_height", axle) as float
        if not is_finite(ground):
            return fail("the terrain has no height under wheel %d at %v" % [index, axle])
        lowest_ground = minf(lowest_ground, ground)
        highest_ground = maxf(highest_ground, ground)
        # A wheel at rest sits a tyre radius above the surface, less its squash under load.
        var expected: float = ground + (wheel["tire_radius"] as float)
        var error: float = absf(axle.y - expected)
        if error > worst:
            worst = error
            worst_wheel = index
        report.append("%s %.3f m over %.3f m" % [wheel["side"], axle.y, ground])

    var slope: float = highest_ground - lowest_ground
    if slope < MIN_SLOPE_M:
        return fail(
            "the ground under the rig varies by only %.3f m: this is the flat-plane test"
            % slope,
            slope
        )
    if worst > AXLE_TOLERANCE_M:
        return fail(
            "wheel %d rests %.3f m from a tyre radius above the terrain under it"
            % [worst_wheel, worst]
            + " (%s)" % ", ".join(report),
            worst
        )
    return ok(
        "settled on %.2f m of slope: %s; worst axle %.0f mm from a tyre radius above ground"
        % [slope, ", ".join(report), worst * 1000.0],
        worst
    )


## Puts the rig down above the spawn point, with its lowest node just clear of the terrain.
func _place(solver: RefCounted, truck: TruckParser) -> void:
    var ground: float = solver.ground_height_at(SPAWN)
    var lowest: float = INF
    for node: Vector3 in truck.nodes:
        lowest = minf(lowest, node.y)
    var lift: Vector3 = Vector3(
        SPAWN.x, ground + SPAWN_CLEARANCE_M - lowest, SPAWN.z
    )
    for i: int in truck.nodes.size():
        solver.set_node_position(i, truck.nodes[i] + lift)
        solver.set_node_velocity(i, Vector3.ZERO)
