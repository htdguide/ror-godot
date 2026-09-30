class_name DriveScenario
extends RefCounted
## Stands the hero rig at the start of a route on a terrain and drives it, for the gates that
## make PLAN M1 acceptance 7's claims.
##
## Everything a drivability gate needs that is not the route itself: the terrain, the rig, the
## spawn, and the handover to `DriveRoute`. It exists so that three gates can differ in exactly
## one thing — where they drive — and so that "it was set up differently" is never an explanation
## for why one of them behaves unlike another.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const PRESET: String = "hero_3q"
const SUBSTEP_HZ: float = 2000.0
## How high above the ground the rig is placed before it settles.
const SPAWN_CLEARANCE_M: float = 0.15


## Builds the world from `terrain_data`, spawns at `waypoints[0]` facing `waypoints[1]`, and
## drives. Returns `DriveRoute.drive`'s report, with "error" set when the setup itself could not
## be made, or "skipped" set when the machine cannot run it.
static func run(
    harness: Node, waypoints: Array[Vector2], options: Dictionary, terrain_data: RorTerrain
) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return {"skipped": "hero asset not present at %s" % MOD_DIR}
    if not ClassDB.class_exists("Terrain3D"):
        return {"skipped": "Terrain3D is not installed. Run tools/build_terrain3d.sh"}
    if waypoints.size() < 2:
        return {"error": "a route needs at least a start and a destination"}
    if terrain_data == null:
        return {"error": "a route needs a terrain to drive on"}
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return {"error": err}

    var terrain: Node3D = TerrainWorld.create()
    if terrain == null:
        return {"error": "Terrain3D is registered but would not instantiate"}
    harness.world.add_child(terrain)
    await harness.advance_frames(2, "static", "terrain")
    var built: String = TerrainWorld.populate(terrain, terrain_data)
    if built != "":
        return {"error": built}

    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.0)
    if (rig["error"] as String) != "":
        return {"error": rig["error"] as String}
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    var applied: String = TerrainWorld.give_to_solver(solver, terrain.get("data"))
    if applied != "":
        return {"error": applied}

    # The flat ground is switched on as well as the heightfield, the way every other gate that
    # stands a rig on a terrain does: `set_ground` is what arms ground contact at all, and the
    # heightfield is what it then collides against.
    solver.set_ground(0.0, true)
    solver.set_gravity(Vector3(0.0, terrain_data.gravity(), 0.0))

    var start: Vector2 = waypoints[0]
    var toward: Vector2 = (waypoints[1] - start).normalized()
    var origin: Vector3 = Vector3(start.x, 0.0, start.y)
    var aimed: String = _aim(solver, truck, origin, toward)
    if aimed != "":
        return {"error": aimed}

    var report: Dictionary = DriveRoute.drive(solver, truck, waypoints, {
        "substep_hz": SUBSTEP_HZ,
        "limit_s": float(options.get("limit_s", 180.0)),
        "target_speed_ms": float(options.get("target_speed_ms", 6.0)),
    }, terrain_data)
    report["surface_at_start"] = terrain_data.models.name_of(
        solver.surface_at(Vector3(start.x, 0.0, start.y))
    )
    return report


## Stands the rig at `origin` facing `toward`, and checks that it is.
##
## The heading `RigBuilder.place` takes is an angle about the vertical whose zero and whose sign
## are its own business, and guessing at them put the rig on the route facing the wrong way and
## drove it 431 m down the valley away from its first waypoint. So the convention is measured
## rather than assumed: place at two known headings, see what the rig's own heading does, and
## solve for the one that points it where it is going. Then check the result, because a rig that
## spawns backwards should say so rather than drive away.
##
## The 431 m it drove the wrong way was down a valley this project generated; the convention it
## established is the placement's, not that world's, so the measurement stays.
static func _aim(
    solver: RefCounted, truck: TruckParser, origin: Vector3, toward: Vector2
) -> String:
    var wanted: float = atan2(toward.x, toward.y)
    RigBuilder.place(solver, truck, origin, 0.0, SPAWN_CLEARANCE_M)
    var at_zero: float = RigBuilder.heading_of(solver.get_positions(), truck.camera_nodes)
    RigBuilder.place(solver, truck, origin, 1.0, SPAWN_CLEARANCE_M)
    var at_one: float = RigBuilder.heading_of(solver.get_positions(), truck.camera_nodes)
    var turned: float = wrapf(at_one - at_zero, -PI, PI)
    if absf(turned) < 0.5:
        return "placing the rig at two headings a radian apart turned it by %.2f rad: the" % turned \
            + " placement is not turning the rig"
    var heading: float = wrapf((wanted - at_zero) / turned, -PI, PI)
    RigBuilder.place(solver, truck, origin, heading, SPAWN_CLEARANCE_M)
    var facing: float = RigBuilder.heading_of(solver.get_positions(), truck.camera_nodes)
    var error: float = absf(wrapf(facing - wanted, -PI, PI))
    if error > 0.05:
        return "the rig spawned facing %.2f rad where the route wants %.2f" % [facing, wanted]
    return ""
