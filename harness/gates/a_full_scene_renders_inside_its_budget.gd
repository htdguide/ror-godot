extends GateBase
## What the scene M2 is aimed at actually costs to draw: one terrain, its objects, and one vehicle.
##
## **This is a budget, not an oracle, and the difference matters.** Every other number this project
## checks is a fact about light or geometry that something outside it supplies. A frame time is a
## property of this machine on this afternoon, so no threshold here can certify anything — the dev
## Mac's answer is not the answer. What a gate can do is three things worth doing: render the scene
## the milestone names rather than a stage, report the cost in the suite's own log so a regression
## has a previous number to be noticed against, and fail when the frame has collapsed rather than
## merely slipped.
##
## So the numbers are reported and the failure bound is half of sixty frames a second. M2's target
## is 16.6 ms and it is stated in the report, passed or missed, for a person to read.
##
## **Draw calls and primitives are reported with it and they are not machine-dependent at all.**
## Those counts are what the renderer was asked to do, identical on any hardware, and they are the
## first place a regression shows: a material that stopped batching, a mesh split into surfaces it
## does not need, an object drawn once per light.
##
## **The frame cost is wall-clock, because this build will not report a GPU one.**
## `RenderingServer.viewport_get_measured_render_time_gpu` returns 0.000 on Metal in Godot 4.7 —
## its CPU companion works and reads 0.415 ms, which is the main loop's own work and says nothing
## about a scene that is drawn on the GPU. So the clock is read either side of a rendered frame,
## with vsync turned off for the measurement: left on, every frame costs exactly one refresh and
## the number means nothing at all.

const MAP: String = "lapaz"
const PRESET: String = "hero_3q"
const WEATHER: String = "noon_clear"
const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
## Frames rendered before anything is read, and frames read after that. The first frames of a scene
## pay for shader compilation, texture upload and a radiance map, and none of that is the frame
## cost of a scene that is running.
const WARM_FRAMES: int = 40
const MEASURED_FRAMES: int = 60
## M2's own target, reported rather than enforced.
const TARGET_MS: float = 16.6
## Where the frame has collapsed rather than slipped: half of sixty frames a second. A wall-clock
## number on one machine cannot certify the target, and it can certainly catch a scene that has
## stopped being interactive.
const COLLAPSED_MS: float = 33.3


static func meta() -> Dictionary:
    return {
        "name": "a_full_scene_renders_inside_its_budget",
        "proves": "the milestone's own scene — a terrain, its objects and a vehicle — draws in a time that is reported with its draw calls, and has not collapsed below thirty frames a second",
        "builds_on": ["vehicle_renders", "ror_terrain_objects_are_placed"],
        "oracle": GateBase.ORACLE_NONE,
        "threshold": (
            "median frame under %.1f ms, with %.1f ms reported as the target"
            % [COLLAPSED_MS, TARGET_MS]
        ),
        "why": (
            "a frame time is a property of the machine measuring it, so this cannot certify the"
            + " milestone's 16.6 ms — what it can do is render the scene the milestone names"
            + " rather than a stage, write the cost and the draw calls into the suite's log where"
            + " a regression has something to be noticed against, and catch a frame that has"
            + " stopped being interactive at all."
        ),
        "budget_s": 60.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var loaded: Dictionary = RorTerrainLibrary.load_named(MAP)
    if (loaded.get("error", "") as String) != "":
        return ok("skipped: %s is not in this checkout" % MAP, 0)
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain
    var err: String = harness.setup_for(PRESET, WEATHER)
    if err != "":
        return fail(err)

    var ground: Node3D = TerrainWorld.create()
    if ground == null:
        return ok("skipped: Terrain3D is not installed", 0)
    harness.world.add_child(ground)
    await harness.advance_frames(2, "static", "terrain")
    var built: String = harness.terrain.populate(ground, terrain)
    if built != "":
        return fail(built)
    var blockout: Node3D = harness.world.get_node_or_null(^"Ground") as Node3D
    if blockout != null:
        blockout.visible = false
    harness.world.add_child(RorObjects.build(terrain))
    harness.world.add_child(RorWater.build(terrain, 3.0))

    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    var vehicle_said: String = "no vehicle in this checkout"
    if DirAccess.dir_exists_absolute(mod_dir):
        var result: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
        if (result.get("error", "") as String) != "":
            return fail(result["error"] as String)
        var vehicle: Node3D = result["root"] as Node3D
        harness.world.add_child(vehicle)
        vehicle.position = terrain.start_position() + Vector3(0.0, 1.0, 0.0)
        vehicle_said = "%d flexbodies and %d wheels" % [
            int(result["built"]), int(result["wheels"])
        ]
        # Framed on the vehicle where it stands, which is the shot the milestone is aimed at.
        harness.camera.look_at_from_position(
            vehicle.position + Vector3(4.2, 1.9, 4.6), vehicle.position + Vector3(0.0, 0.9, 0.0),
            Vector3.UP
        )

    var viewport: Viewport = harness.render_viewport()
    var rid: RID = viewport.get_viewport_rid()
    RenderingServer.viewport_set_measure_render_time(rid, true)
    var was_vsync: int = DisplayServer.window_get_vsync_mode()
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    await harness.advance_frames(WARM_FRAMES, "static", "warm")

    var wall: PackedFloat32Array = PackedFloat32Array()
    var cpu: PackedFloat32Array = PackedFloat32Array()
    for _frame: int in MEASURED_FRAMES:
        var began: int = Time.get_ticks_usec()
        await harness.advance_frames(1, "static", "measure")
        wall.append(float(Time.get_ticks_usec() - began) / 1000.0)
        cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
    var draw_calls: int = int(RenderingServer.get_rendering_info(
        RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
    ))
    var primitives: int = int(RenderingServer.get_rendering_info(
        RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
    ))
    var objects: int = int(RenderingServer.get_rendering_info(
        RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME
    ))
    RenderingServer.viewport_set_measure_render_time(rid, false)
    DisplayServer.window_set_vsync_mode(was_vsync as DisplayServer.VSyncMode)

    var size: Vector2 = viewport.get_visible_rect().size
    var middle_wall: float = _median(wall)
    var middle_cpu: float = _median(cpu)
    if middle_wall <= 0.0:
        return fail("the scene reported no frame time at all", 0)
    var said: String = (
        "%.2f ms a frame, of which %.2f ms is the main loop, at %dx%d, median of %d frames;"
        % [middle_wall, middle_cpu, size.x, size.y, MEASURED_FRAMES]
        + " %d draw calls," % draw_calls
        + " %d objects, %d primitives; %s, %s" % [objects, primitives, MAP, vehicle_said]
    )
    if middle_wall > COLLAPSED_MS:
        return fail(
            "%s — over the %.1f ms this gate calls a collapsed frame, against a %.1f ms target"
            % [said, COLLAPSED_MS, TARGET_MS],
            middle_wall
        )
    return ok(
        "%s. M2's %.1f ms target: %s"
        % [said, TARGET_MS, "met" if middle_wall <= TARGET_MS else "missed"],
        middle_wall
    )


func _median(values: PackedFloat32Array) -> float:
    if values.is_empty():
        return 0.0
    var sorted: Array[float] = []
    for value: float in values:
        sorted.append(value)
    sorted.sort()
    return sorted[sorted.size() / 2]
