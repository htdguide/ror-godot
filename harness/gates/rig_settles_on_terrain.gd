extends GateBase
## The rig lands on the terrain and stays on it, on ground that is not flat.
##
## Everything before this stands the rig on a plane at y = 0, where "on the ground" and "at
## zero" are the same statement and a solver that ignored the terrain entirely would pass.
## Here the spawn is on a hillside of a terrain somebody else authored, so the two come apart:
## each wheel rests at a different height, and each has to rest at the height of the terrain
## underneath *it*.
##
## The oracle is the terrain's own height query, taken under each axle after the rig has
## settled. It is the same surface the renderer draws, so this is also the check that the rig
## and the visible ground are in the same place — measured per wheel rather than once for the
## whole vehicle, because a rig resting on a slope at the right average height can still have
## two wheels buried and two in the air.
##
## The spawn is searched for rather than written down. A hardcoded point is a point that means
## something on one map and nothing on the next, and this gate used to hold a coordinate on a
## valley wall this project generated itself. So the terrain is scanned in a fixed order for the
## first place whose relief across a vehicle is in range — enough slope for the wheels to
## disagree, not enough for a parked truck to slide — and the gate reports where it went.

const TERRAIN_DIR: String = "assets/terrains/lapaz2"
const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const SUBSTEP_HZ: float = 2000.0
const SETTLE_SECONDS: float = 3.0
const SPAWN_CLEARANCE_M: float = 0.15
## How the spawn is looked for: a coarse grid over the map, in a fixed order, taking the first
## cell whose relief over a vehicle's footprint is in range.
const SEARCH_STEP_M: float = 64.0
const SEARCH_MARGIN_M: float = 128.0
const FOOTPRINT_M: float = 3.0
const WANTED_RELIEF_MIN_M: float = 0.30
const WANTED_RELIEF_MAX_M: float = 1.20
## An axle sits a tyre radius above the ground, plus whatever the tyre has squashed by. The
## bound is on the error against that, not on the height itself.
const AXLE_TOLERANCE_M: float = 0.12
## The terrain under the rig has to actually be sloped, or this is the flat-plane test again.
## Below what the search asks for, because the search measures a square footprint and the rig's
## own wheels sit inside it.
const MIN_SLOPE_M: float = 0.15


static func meta() -> Dictionary:
    return {
        "name": "rig_settles_on_terrain",
        "proves": "the rig lands on sloped terrain with every wheel at the height of the ground beneath it, not through it and not above it",
        # the rig settles on a built Terrain3D valley at the same rate and for longer than the flat-
        # ground settle.
        "builds_on": ["solver_settles_vehicle", "terrain3d_available"],
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
    var directory: String = SourceScan.repo_root().path_join(TERRAIN_DIR)
    if not DirAccess.dir_exists_absolute(directory):
        return ok("skipped: no terrain at %s" % TERRAIN_DIR, 0)
    if not ClassDB.class_exists("Terrain3D"):
        return ok("skipped: Terrain3D is not installed. Run tools/build_terrain3d.sh", 0)
    var loaded: Dictionary = RorTerrain.load_from(directory)
    if (loaded["error"] as String) != "":
        return fail(loaded["error"] as String)
    var terrain_data: RorTerrain = loaded["terrain"] as RorTerrain
    var spawn: Vector3 = _sloped_spawn(terrain_data)
    if spawn == Vector3.INF:
        return fail(
            "no cell of %s has between %.2f m and %.2f m of relief across %.0f m: there is"
            % [terrain_data.name, WANTED_RELIEF_MIN_M, WANTED_RELIEF_MAX_M, FOOTPRINT_M]
            + " nowhere on this map to test a slope"
        )
    var err: String = harness.setup_for("hero_3q")
    if err != "":
        return fail(err)

    var terrain: Node3D = TerrainWorld.create()
    harness.world.add_child(terrain)
    await harness.advance_frames(2, "static", "terrain")
    var built: String = harness.terrain.populate(terrain, terrain_data)
    if built != "":
        return fail(built)
    var data: Object = terrain.get("data")

    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        return fail(rig["error"] as String)
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    var applied: String = harness.terrain.give_to_solver(solver, data)
    if applied != "":
        return fail(applied)
    solver.set_ground(0.0, true)
    _place(solver, truck, spawn)

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
        "settled on %s at %.0f, %.0f, on %.2f m of slope: %s; worst axle %.0f mm from a tyre"
        % [terrain_data.name, spawn.x, spawn.z, slope, ", ".join(report), worst * 1000.0]
        + " radius above ground",
        worst
    )


## The first place on the terrain with enough relief across a vehicle to make the wheels
## disagree, and not so much that a parked truck slides off it.
##
## Scanned in a fixed order over a coarse grid, so the answer is the same on every machine and
## every run. Returns `Vector3.INF` when the map has nowhere like that.
func _sloped_spawn(terrain_data: RorTerrain) -> Vector3:
    var grid: Dictionary = terrain_data.lattice()
    var span: float = float((grid["size"] as int) - 1) * (grid["spacing"] as float)
    var half: float = FOOTPRINT_M * 0.5
    var at: float = SEARCH_MARGIN_M
    while at < span - SEARCH_MARGIN_M:
        var across: float = SEARCH_MARGIN_M
        while across < span - SEARCH_MARGIN_M:
            var lowest: float = INF
            var highest: float = -INF
            for corner: Vector2 in [
                Vector2(-half, -half), Vector2(half, -half),
                Vector2(-half, half), Vector2(half, half),
            ]:
                var height: float = terrain_data.height_at_world(
                    across + corner.x, at + corner.y
                )
                lowest = minf(lowest, height)
                highest = maxf(highest, height)
            var relief: float = highest - lowest
            if relief >= WANTED_RELIEF_MIN_M and relief <= WANTED_RELIEF_MAX_M:
                return Vector3(across, 0.0, at)
            across += SEARCH_STEP_M
        at += SEARCH_STEP_M
    return Vector3.INF


## Puts the rig down above the spawn point, with its lowest node just clear of the terrain.
func _place(solver: RefCounted, truck: TruckParser, spawn: Vector3) -> void:
    var ground: float = solver.ground_height_at(spawn)
    var lowest: float = INF
    for node: Vector3 in truck.nodes:
        lowest = minf(lowest, node.y)
    var lift: Vector3 = Vector3(
        spawn.x, ground + SPAWN_CLEARANCE_M - lowest, spawn.z
    )
    for i: int in truck.nodes.size():
        solver.set_node_position(i, truck.nodes[i] + lift)
        solver.set_node_velocity(i, Vector3.ZERO)
