extends Node
## The harness: the project's only autoload, and its only eyes.
##
## Owns argument parsing, determinism, the run loop, capture, metrics and the exit
## code. Nothing else. Systems are built and owned by whoever needs them, so that a
## gate can construct one in isolation.
##
## Usage (see docs/guides/harness.md):
##   godot --path game -- --gate smoke
##   godot --path game -- --shot diag_origin --out artifacts/adhoc
##   godot --path game -- --play

const EXIT_OK: int = 0
const EXIT_FAIL: int = 1
const EXIT_USAGE: int = 2
const GATE_DIR: String = "res://harness/gates"

var args: HarnessArgs
var metrics: HarnessMetrics
var rng: RandomNumberGenerator
var world: Node3D
var camera: Camera3D
## The terrain world this run builds into. One instance, owned here rather than reached through
## the class, so that the terrain built last is a property of this run and not of the process —
## see `TerrainWorld`'s own header. D0's containers hand each gate a fresh one.
var terrain: TerrainWorld = TerrainWorld.new()
var frame_index: int = 0
var preset_name: String = ""
var preset: Dictionary = {}
## The weather this run is rendering under, for a gate that wants to build something of its own
## with the same light.
var weather_name: String = "noon_clear"
## The vehicle loaded by --vehicle, as VehicleBuilder returned it. Kept so a human session
## can drive the same built vehicle rather than building a second one.
var vehicle: Dictionary = {}

var _main: Node
var _run_started: bool = false
## The gate container currently open, or null outside gate mode. A gate's world lives inside it
## and nothing a gate builds reaches the next one -- see `GateContainer`.
var container: GateContainer = null
## What the window shows: the container that is running. One window for the whole suite, which is
## the point of D0, and a session can watch a gate build its world in place.
var _screen: TextureRect = null


func begin(main: Node) -> void:
    _main = main
    args = HarnessArgs.new(OS.get_cmdline_user_args())
    if args.error != "":
        _die(EXIT_USAGE, "argument error: " + args.error)
        return
    if args.has_flag("list"):
        _print_inventory()
        _quit(EXIT_OK)
        return
    if args.has_flag("chain"):
        _print_chain()
        _quit(EXIT_OK)
        return
    _apply_determinism()
    if args.values.has("gate"):
        # `--gate a,b,c` runs three gates in one window, each in its own container. One name is
        # the same path with a list of one, so there is no separate single-gate mode to keep
        # honest. `GateRunner` owns the loop and the containers.
        _run_suite(args.get_string("gate", "").split(",", false))
        return
    _run_capture()


## --------------------------------------------------------------------------------
## Setup


func _apply_determinism() -> void:
    var tick: int = args.get_int("tick", HarnessCfg.TICK_HZ)
    Engine.physics_ticks_per_second = tick
    Engine.max_physics_steps_per_frame = 1
    rng = RandomNumberGenerator.new()
    rng.seed = args.get_int("seed", HarnessCfg.SEED)


## What weather a run uses when nothing asks for one: the preset's own in a gate, and the hour a
## session wants to look at in a window.
func _default_weather() -> String:
    if args.has_flag("play"):
        return DriveCfg.DEFAULT_WEATHER
    return preset.get("weather", "noon_clear") as String


func _build_world(scenario: String, weather: String) -> String:
    weather_name = weather
    if not Scenarios.has(scenario):
        return "unknown scenario '%s'; known: %s" % [scenario, Scenarios.names()]
    if not WeatherCfg.has(weather):
        return "unknown weather preset '%s'" % weather
    # Clouds in a window, the stated gradient in a gate: see `BlockoutWorld._clouds`.
    world = BlockoutWorld.build(
        WeatherCfg.get_preset(weather),
        bool(preset.get("props", true)),
        args.has_flag("play")
    )
    # In gate mode the world belongs to the container, which is what keeps one gate's lights,
    # environment and probes out of the next one's frame.
    var host: Node = container.viewport if container != null else _main
    host.add_child(world)
    camera = _build_camera(preset)
    world.add_child(camera)
    if container != null:
        container.world = world
        container.camera = camera
    metrics = HarnessMetrics.new()
    metrics.begin(render_viewport())
    return ""


## The camera is physical: depth of field then follows from the lens instead of being
## dialled by hand, and exposure is comparable between weather presets.
func _build_camera(from_preset: Dictionary) -> Camera3D:
    var attributes: CameraAttributesPhysical = CameraAttributesPhysical.new()
    attributes.frustum_focal_length = float(from_preset.get("focal_mm", 35.0))
    attributes.exposure_aperture = float(from_preset.get("f_stop", 8.0))
    attributes.exposure_shutter_speed = 1.0 / maxf(float(from_preset.get("shutter_s", 0.008)), 0.000001)
    attributes.auto_exposure_enabled = false
    var cam: Camera3D = Camera3D.new()
    cam.name = "HarnessCamera"
    cam.attributes = attributes
    cam.position = from_preset.get("pos", Vector3.ZERO) as Vector3
    cam.look_at_from_position(
        from_preset.get("pos", Vector3.ZERO) as Vector3,
        from_preset.get("look_at", Vector3.ZERO) as Vector3,
        Vector3.UP
    )
    return cam


func _resolve_preset(name: String) -> String:
    if not CameraCfg.has(name):
        return "unknown camera preset '%s'; known: %s" % [name, CameraCfg.names()]
    preset_name = name
    preset = CameraCfg.get_preset(name)
    return ""


## --------------------------------------------------------------------------------
## Capture mode: render N frames, save a PNG plus its manifest, exit.


func _run_capture() -> void:
    var shot: String = args.get_string("shot", "diag_origin")
    var err: String = _resolve_preset(shot)
    if err != "":
        _die(EXIT_USAGE, err)
        return
    var scenario: String = args.get_string("scenario", preset.get("scenario", "static") as String)
    var weather: String = args.get_string("weather", preset.get("weather", "noon_clear") as String)
    err = _build_world(scenario, weather)
    if err != "":
        _die(EXIT_USAGE, err)
        return
    var vehicle_path: String = args.get_string("vehicle", "")
    if vehicle_path != "":
        var loaded: String = _load_vehicle(vehicle_path)
        if loaded != "":
            _die(EXIT_USAGE, loaded)
            return

    if args.has_flag("play"):
        var rig: PlayRig = PlayRig.new()
        rig.name = "PlayRig"
        add_child(rig)
        rig.setup(camera, world, weather, vehicle)
        print("HARNESS_PLAY interactive mode; press Esc or close the window to exit")
        return
    var out_dir: String = args.get_string("out", "adhoc")
    var converge: int = args.get_int("converge", HarnessCfg.CONVERGE_FRAMES)
    var result: Dictionary = await capture_shot(out_dir, scenario, converge)
    if result["error"] != "":
        _die(EXIT_FAIL, result["error"] as String)
        return
    print("HARNESS_SHOT " + JSON.stringify(result))
    _quit(EXIT_OK)


## Renders `converge` warm-up frames, then captures. Returns
## {"error": String, "png": String, "manifest": String}.
func capture_shot(out_dir: String, scenario: String, converge: int) -> Dictionary:
    var dir: String = HarnessCapture.resolve_dir(out_dir)
    var png_path: String = "%s/%s.png" % [dir, preset_name]
    var manifest_path: String = "%s/%s.json" % [dir, preset_name]
    await advance_frames(converge, scenario, "converge")
    var err: String = HarnessCapture.capture_png(render_viewport(), png_path)
    if err != "":
        return {"error": err, "png": "", "manifest": ""}
    var summary: Dictionary = metrics.summarize({"preset": preset_name})
    err = HarnessCapture.write_manifest(
        manifest_path,
        {
            "preset": preset_name,
            "scenario": scenario,
            "weather": args.get_string("weather", preset.get("weather", "noon_clear") as String),
            "seed": args.get_int("seed", HarnessCfg.SEED),
            "tick_hz": args.get_int("tick", HarnessCfg.TICK_HZ),
            "converge_frames": converge,
            "resolution": "%dx%d" % [
                render_viewport().get_visible_rect().size.x,
                render_viewport().get_visible_rect().size.y,
            ],
            "summary": summary,
        }
    )
    if err != "":
        return {"error": err, "png": "", "manifest": ""}
    return {"error": "", "png": png_path, "manifest": manifest_path}


## The viewport a gate renders into and captures from: its container's, or the window's when
## there is no container. Never `get_viewport()` directly in gate code — that is the window, and
## in gate mode the window only *displays* the container.
func render_viewport() -> Viewport:
    return container.viewport if container != null else get_viewport()


## Renders exactly `count` frames, sampling metrics on each. Frame-accurate: gates
## depend on the frame index, so this must never skip or coalesce a frame.
func advance_frames(count: int, scenario: String, tag: String) -> void:
    for _i: int in count:
        if frame_index >= HarnessCfg.MAX_FRAMES:
            push_error("frame cap %d reached; gate hung" % HarnessCfg.MAX_FRAMES)
            return
        Scenarios.tick(scenario, frame_index, world)
        await RenderingServer.frame_post_draw
        metrics.sample(frame_index, tag)
        frame_index += 1


## --------------------------------------------------------------------------------
## Gate mode


## Runs the named gates, each in its own container, and exits with the suite's verdict.
func _run_suite(names: PackedStringArray) -> void:
    var runner: GateRunner = GateRunner.new()
    var outcome: Dictionary = await runner.run(self, names)
    if (outcome["usage_error"] as bool):
        _quit(EXIT_USAGE)
        return
    _quit(EXIT_OK if int(outcome["failed"]) == 0 else EXIT_FAIL)


## --------------------------------------------------------------------------------
## Plumbing


## Puts the world into a state where numbers encoded into pixels survive to the capture:
## linear tonemapping, a black background and no ambient light.
##
## Both parts matter. A tonemapper desaturates and lifts, so a value written into one
## channel is not the value read back. And a lit background puts bright pixels all over
## the frame, which a threshold test counts as though they were geometry — the sky alone
## produced nearly two hundred thousand false positives before this existed.
func use_measurement_environment() -> void:
    var holder: WorldEnvironment = world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    if holder == null or holder.environment == null:
        return
    var environment: Environment = holder.environment
    environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    environment.tonemap_exposure = 1.0
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color.BLACK
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color.BLACK
    environment.ambient_light_energy = 0.0
    var ground: MeshInstance3D = world.get_node_or_null(^"Ground") as MeshInstance3D
    if ground != null:
        ground.visible = false


## Loads a vehicle into the current world, for human sessions and ad-hoc shots. The path
## is a mod directory and a vehicle file, separated by a colon.
func _load_vehicle(spec: String) -> String:
    var parts: PackedStringArray = spec.split(":")
    if parts.size() != 2:
        return "expected --vehicle <mod dir>:<truck file>, got '%s'" % spec
    var mod_dir: String = parts[0]
    if not mod_dir.is_absolute_path():
        mod_dir = SourceScan.repo_root().path_join(mod_dir)
    # The blockout scale props exist to give an empty frame something to measure. With a
    # vehicle loaded they are just obstacles for it to sit inside.
    for prop: Node in world.get_children():
        if str(prop.name).begins_with("Box") or str(prop.name) == "Sphere":
            prop.queue_free()

    var built: Dictionary = VehicleBuilder.build(mod_dir, parts[1])
    if (built.get("error", "") as String) != "":
        return built["error"] as String
    var root: Node3D = built["root"] as Node3D
    world.add_child(root)
    var bounds: AABB = VehicleBuilder.world_bounds(root)
    # Stand it on the ground, where a person expects to find it. A driving session skips
    # this: the solver spawns the rig above the ground itself and every pose after that
    # carries the rig's own position, so shifting it here would offset it twice.
    if not args.has_flag("play"):
        root.position += Vector3(
            -bounds.get_center().x, -bounds.position.y, -bounds.get_center().z
        )
    vehicle = built
    print("HARNESS_VEHICLE " + JSON.stringify({
        "parts": int(built["built"]), "wheels": int(built["wheels"]),
        "size": "%.2f x %.2f x %.2f" % [bounds.size.x, bounds.size.y, bounds.size.z],
    }))
    return ""


## Builds the world a gate asked for. Gates never construct scenes themselves.
## Builds the world a gate asks for. `weather` overrides the preset's own, for a gate whose
## claim is about a particular light — a lamp is not worth measuring at noon.
func setup_for(shot: String, weather: String = "") -> String:
    var err: String = _resolve_preset(shot)
    if err != "":
        return err
    return _build_world(
        args.get_string("scenario", preset.get("scenario", "static") as String),
        weather if weather != "" else args.get_string(
            "weather", _default_weather()
        )
    )


## --------------------------------------------------------------------------------
## Plumbing


## The gate graph, for the runner to schedule from: which gates build on which, and what tier
## that puts each one in. Printed rather than computed in the runner because the edges are
## declared in the gates themselves and nothing outside the engine can read them.
func _print_chain() -> void:
    var graph: Dictionary = GateChain.load_graph()
    print("HARNESS_CHAIN " + JSON.stringify({
        "gates": graph,
        "order": GateChain.order(graph),
        "roots": GateChain.roots(graph),
        "problems": GateChain.problems(graph),
    }))


func _print_inventory() -> void:
    var gates: PackedStringArray = PackedStringArray()
    var dir: DirAccess = DirAccess.open(GATE_DIR)
    if dir != null:
        for file: String in dir.get_files():
            if file.ends_with(".gd"):
                gates.append(file.get_basename())
    print("HARNESS_INVENTORY " + JSON.stringify({
        "gates": gates,
        "presets": CameraCfg.names(),
        "scenarios": Scenarios.names(),
    }))


func _die(code: int, message: String) -> void:
    printerr("HARNESS_ERROR " + message)
    _quit(code)


func _quit(code: int) -> void:
    if _run_started:
        return
    _run_started = true
    get_tree().quit(code)
