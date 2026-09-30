extends GateBase
## A shipped Rigs of Rods terrain reaches the screen and the solver, and the hero truck drives away
## from the spawn its author wrote.
##
## `ror_terrain_matches_its_files` checks the terrain against its own configs, on the CPU, with no
## renderer and no vehicle. This is the other half: the heightmap through Terrain3D's import, out
## again through the collision bridge, under a real rig that is asked to drive.
##
## Three things can go wrong between those two gates and nothing else catches any of them. The
## import can land the terrain at the wrong scale, because Terrain3D's vertex spacing is a property
## of the node rather than of the data. The regions can tile somewhere other than where the terrain
## was asked to go, which is silent until something is stood on it. And the surfaces can arrive
## transposed, which has happened here once already and reads as a terrain that grips like a
## different terrain.
##
## The measurement is the drive. A rig that spawns at the author's own start position, settles, and
## covers ground under its own power has resolved every one of those wirings correctly.

const TERRAIN_DIR: String = "assets/terrains/lapaz2"
const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const PRESET: String = "hero_3q"
const SUBSTEP_HZ: float = 2000.0
const SETTLE_SECONDS: float = 2.5
const DRIVE_SECONDS: float = 6.0
const THROTTLE: float = 0.7
## How far the drawn terrain and the loaded heightmap may differ, sampled off the grid. Both sides
## interpolate the same lattice bilinearly, so this is the wiring — spacing, origin, row order —
## and not interpolation error.
const HEIGHT_TOLERANCE_M: float = 0.02
const HEIGHT_SAMPLES: int = 200
## Where the rig has to be after settling: resting on the ground, not sunk into it or thrown off.
const MAX_SETTLE_RISE_M: float = 2.5
const MAX_SETTLE_SINK_M: float = 0.5
## And what the drive has to cover. A gentle figure: the point is that the rig is on ground that
## holds it and that the wheels bite, not that this terrain has a drag strip on it.
const MIN_DISTANCE_M: float = 20.0


static func meta() -> Dictionary:
    return {
        "name": "ror_terrain_is_drivable",
        "proves": "a shipped Rigs of Rods terrain imports into Terrain3D at its own scale, comes back out through the collision bridge unchanged, and the hero truck settles and drives on it from the spawn its author wrote",
        # the terrain has to read correctly before it is imported, and the rig has to drive on a
        # generated world before it is asked to drive on someone else's.
        "builds_on": ["ror_terrain_matches_its_files", "terrain_collision_agreement"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "drawn and loaded heights within %.0f mm over %d off-grid samples, the rig resting"
            % [HEIGHT_TOLERANCE_M * 1000.0, HEIGHT_SAMPLES]
            + " within %.1f m of the ground, and at least %.0f m driven"
            % [MAX_SETTLE_RISE_M, MIN_DISTANCE_M]
        ),
        "why": (
            "between reading a terrain and driving on it are three silent wirings: Terrain3D's"
            + " vertex spacing is a property of the node rather than of the data, its regions tile"
            + " wherever they are asked to, and a surface map can arrive transposed — which has"
            + " happened in this project and reads as a terrain that grips like a different one."
            + " A rig that drives away from the author's own spawn has resolved all three."
        ),
        "budget_s": 180.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var directory: String = SourceScan.repo_root().path_join(TERRAIN_DIR)
    if not DirAccess.dir_exists_absolute(directory):
        return ok("skipped: no terrain at %s" % TERRAIN_DIR, 0)
    if not ClassDB.class_exists("Terrain3D"):
        return ok("skipped: Terrain3D is not installed. Run tools/build_terrain3d.sh", 0)
    var loaded: Dictionary = RorTerrain.load_from(directory)
    if (loaded["error"] as String) != "":
        return fail(loaded["error"] as String)
    var terrain_data: RorTerrain = loaded["terrain"] as RorTerrain

    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)
    var terrain: Node3D = TerrainWorld.create()
    harness.world.add_child(terrain)
    await harness.advance_frames(2, "static", "terrain")
    var built: String = harness.terrain.populate(terrain, terrain_data)
    if built != "":
        return fail(built)
    await harness.advance_frames(1, "static", "terrain")
    var data: Object = terrain.get("data")
    if data == null:
        return fail("the terrain has no data object after populating")

    var drawn: Dictionary = _drawn_matches_loaded(data, terrain_data)
    if (drawn["error"] as String) != "":
        return fail(drawn["error"] as String, drawn["value"] as float)

    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok(
            "the terrain draws and its heights round-trip within %.1f mm; skipped the drive: the"
            % ((drawn["value"] as float) * 1000.0) + " hero asset is not present",
            drawn["value"]
        )
    var driven: Dictionary = _drive(mod_dir, data, terrain_data, harness.terrain)
    if (driven["error"] as String) != "":
        return fail(driven["error"] as String, driven["value"] as float)
    return ok(
        "%s: heights round-trip within %.1f mm, the rig settled %.2f m above the ground on %s and"
        % [terrain_data.name, (drawn["value"] as float) * 1000.0, driven["rest"] as float,
           driven["surface"] as String]
        + " drove %.1f m at up to %.1f m/s" % [driven["value"] as float, driven["speed"] as float],
        driven["value"]
    )


## What Terrain3D draws against what the terrain's own files say, off the grid on both axes.
func _drawn_matches_loaded(data: Object, terrain_data: RorTerrain) -> Dictionary:
    var out: Dictionary = {"error": "", "value": 0.0}
    var grid: Dictionary = terrain_data.lattice()
    var span: float = float((grid["size"] as int) - 2) * (grid["spacing"] as float)
    var rng: RandomNumberGenerator = RandomNumberGenerator.new()
    rng.seed = HarnessCfg.SEED
    var worst: float = 0.0
    var worst_at: Vector2 = Vector2.ZERO
    var relief: float = 0.0
    var lowest: float = INF
    for _sample: int in HEIGHT_SAMPLES:
        var at: Vector2 = Vector2(rng.randf_range(4.0, span), rng.randf_range(4.0, span))
        var theirs: float = data.call("get_height", Vector3(at.x, 0.0, at.y)) as float
        var ours: float = terrain_data.height_at_world(at.x, at.y)
        if not is_finite(theirs):
            out["error"] = "Terrain3D reports no height at %v: the regions do not cover the map" % at
            return out
        var off: float = absf(theirs - ours)
        if off > worst:
            worst = off
            worst_at = at
        relief = maxf(relief, ours)
        lowest = minf(lowest, ours)
    out["value"] = worst
    if worst > HEIGHT_TOLERANCE_M:
        out["error"] = (
            "the drawn terrain is %.3f m from the heightmap at %v: the import is not at the"
            % [worst, worst_at] + " terrain's own scale or origin"
        )
        return out
    if relief - lowest < 1.0:
        out["error"] = (
            "the sampled terrain is flat to %.3f m: agreeing about a flat plane proves nothing"
            % (relief - lowest)
        )
    return out


## Spawns the hero truck where the terrain says and asks it to drive.
func _drive(
    mod_dir: String, data: Object, terrain_data: RorTerrain, world: TerrainWorld
) -> Dictionary:
    var out: Dictionary = {"error": "", "value": 0.0, "rest": 0.0, "speed": 0.0, "surface": ""}
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        out["error"] = rig["error"] as String
        return out
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    var applied: String = world.give_to_solver(solver, data)
    if applied != "":
        out["error"] = applied
        return out
    # Ground contact is a flag as well as a heightfield: with it off the solver resolves nothing
    # under the wheels and the rig free-falls past a terrain that is loaded correctly.
    solver.set_ground(0.0, true)
    solver.set_gravity(Vector3(0.0, terrain_data.gravity(), 0.0))
    var start: Vector3 = terrain_data.start_position()
    out["surface"] = terrain_data.models.name_of(
        terrain_data.surface_at_world(start.x, start.z)
    )
    RigBuilder.place(solver, truck, Vector3(start.x, 0.0, start.z), 0.0, DriveCfg.SPAWN_HEIGHT_M)

    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    for _frame: int in int(SETTLE_SECONDS * 60.0):
        solver.step(dt, chunk)
    var settled: Vector3 = ActorFrame.of(solver.get_positions(), truck.camera_nodes).origin
    if not is_finite(settled.length()):
        out["error"] = "the solver went non-finite while the rig settled"
        return out
    var ground: float = terrain_data.height_at_world(settled.x, settled.z)
    out["rest"] = settled.y - ground
    if settled.y - ground > MAX_SETTLE_RISE_M:
        out["error"] = (
            "the rig settled %.2f m above the ground at %v: the heightfield and the drawn terrain"
            % [settled.y - ground, settled] + " are not the same surface"
        )
        return out
    if ground - settled.y > MAX_SETTLE_SINK_M:
        out["error"] = (
            "the rig sank %.2f m into the ground at %v: it is falling through the terrain"
            % [ground - settled.y, settled]
        )
        return out

    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(THROTTLE)
    var fastest: float = 0.0
    for frame: int in int(DRIVE_SECONDS * 60.0):
        solver.step(dt, chunk)
        fastest = maxf(fastest, absf(solver.road_speed()))
        if not is_finite(solver.get_node_position(0).length()):
            out["error"] = "the solver went non-finite %.2f s into the drive" % (
                float(frame) / 60.0)
            return out
    var finished: Vector3 = ActorFrame.of(solver.get_positions(), truck.camera_nodes).origin
    var travelled: float = Vector2(finished.x - settled.x, finished.z - settled.z).length()
    out["value"] = travelled
    out["speed"] = fastest
    if travelled < MIN_DISTANCE_M:
        out["error"] = (
            "%.1f s of throttle moved the rig %.1f m across the terrain, under %.0f: it is not"
            % [DRIVE_SECONDS, travelled, MIN_DISTANCE_M] + " driving on this ground"
        )
    return out
