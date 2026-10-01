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
## Extra frames after switching the render target to HDR. Reallocating it is not instant and a
## capture taken too early comes from the old target, which is the 8-bit one.
const HDR_SETTLE_FRAMES: int = 4
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
## The command table every front end dispatches into: the keyboard's console, the agent's
## channel, and `tools/gate.sh`. One table is what stops the agent and the user having different
## capabilities — `console_fronts_agree` holds it.
var commands: ConsoleTable = null
## The agent's front end, when this run has one open.
var channel: AgentChannel = null
## The keyboard's front end: the drop-down console. Same table as the channel.
var console: ConsoleUi = null
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
        HarnessReport.print_inventory(GATE_DIR)
        _quit(EXIT_OK)
        return
    if args.has_flag("chain"):
        HarnessReport.print_chain()
        _quit(EXIT_OK)
        return
    _apply_determinism()
    _open_console()
    # `--console` on its own is a session that exists to be driven: it holds the process open,
    # serving the agent's channel and the keyboard, until something tells it to quit. Without
    # this it fell through to capture mode and exited before the channel had polled once.
    if args.has_flag("console") and not args.has_flag("play"):
        return
    # The command line is a front end onto the console's table like any other, and `--gate` is
    # sugar over one of its commands rather than a second way to run gates. PLAN 0.8 asks for
    # one command table; a runner the command line reached and the console did not would be the
    # first thing to drift, and it would drift in the path CI uses.
    if args.values.has("command"):
        _run_command(args.get_string("command", ""))
        return
    if args.values.has("gate"):
        var names: PackedStringArray = args.get_string("gate", "").split(",", false)
        _run_command("gate run %s" % " ".join(names))
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
    # The previous world goes first, and this is not housekeeping.
    #
    # `setup_for` can be called more than once in a gate — a second weather, a second camera
    # preset — and this used to add the new world beside the old one rather than replacing it.
    # Two worlds in one viewport means two environments, two suns and two cameras, and the camera
    # that entered first stays current: the picture never changed. Measured, two completely
    # different skies produced byte-identical captures, mean luminance agreeing to six decimals.
    # `vehicle_renders` has been writing a "rear" artifact that is the front view because of it.
    var previous: Node3D = world
    if previous != null and is_instance_valid(previous):
        if previous.get_parent() != null:
            previous.get_parent().remove_child(previous)
        previous.queue_free()
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
    camera = PhysicalCamera.build(preset)
    world.add_child(camera)
    if container != null:
        container.world = world
        container.camera = camera
    metrics = HarnessMetrics.new()
    metrics.begin(render_viewport())
    return ""


## Moves to another camera preset without rebuilding the world.
##
## Changing where the camera stands is no reason to throw the scene away, and treating it as one
## bit twice in opposite directions: a second `setup_for` first gave two worlds and the *front*
## view, then — once the stale world was freed — the rear view of an empty field, the vehicle
## having been parented to the world just freed. `make_current` is explicit because a viewport
## keeps whichever camera entered first, which is how that stayed invisible. See
## `hard-won-facts.md`.
func use_camera(shot: String) -> String:
    if world == null or not is_instance_valid(world):
        return "there is no world to put a camera in; call setup_for first"
    var err: String = _resolve_preset(shot)
    if err != "":
        return err
    var fresh: Camera3D = PhysicalCamera.build(preset)
    if camera != null and is_instance_valid(camera):
        if camera.get_parent() != null:
            camera.get_parent().remove_child(camera)
        camera.queue_free()
    camera = fresh
    world.add_child(camera)
    camera.make_current()
    if container != null:
        container.camera = camera
    return ""


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


## Captures the frame as linear light rather than as display pixels: an OpenEXR, unclipped, with
## no sRGB transfer on it.
##
## The viewport is switched to an HDR render target for the capture and switched back after, so
## every other gate keeps the 8-bit display-referred capture it was written against. Opt-in
## deliberately: an HDR target changes what a PNG written from it would mean, and most gates are
## asking about the displayed image and are right to.
##
## Returns {"error", "exr", "image"}. `image` is the float image, which is what a measurement
## should read; the file is for a person and for tooling.
func capture_hdr(out_dir: String, scenario: String, converge: int) -> Dictionary:
    var viewport: Viewport = render_viewport()
    var was_hdr: bool = viewport.use_hdr_2d
    viewport.use_hdr_2d = true
    # The render target is reallocated, so the frame that matters is a later one.
    await advance_frames(maxi(converge, 2) + HDR_SETTLE_FRAMES, scenario, "hdr")
    var texture: ViewportTexture = viewport.get_texture()
    var image: Image = texture.get_image() if texture != null else null
    var path: String = "%s/%s.exr" % [HarnessCapture.resolve_dir(out_dir), preset_name]
    var error: String = HarnessCapture.capture_exr(viewport, path)
    viewport.use_hdr_2d = was_hdr
    await advance_frames(1, scenario, "hdr")
    return {"error": error, "exr": path, "image": image}


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


## Opens the command table and the front ends onto it. See `ConsoleSession`.
func _open_console() -> void:
    var opened: Dictionary = ConsoleSession.open(self)
    commands = opened["table"] as ConsoleTable
    channel = opened["channel"] as AgentChannel
    console = opened["console"] as ConsoleUi


## --------------------------------------------------------------------------------
## Gate mode


## Runs one console command and exits with its verdict. The command line's whole gate mode.
##
## `HARNESS_COMMAND` carries the answer for a caller that wants the result rather than the
## per-gate lines `gate run` prints on its way through.
func _run_command(line: String) -> void:
    var started: int = Time.get_ticks_usec()
    var result: Dictionary = await commands.dispatch(line)
    var elapsed_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
    print("HARNESS_COMMAND " + ConsoleResult.to_line(1, line, result, elapsed_ms))
    _quit(EXIT_OK if (result.get("ok", false) as bool) else EXIT_FAIL)


## --------------------------------------------------------------------------------
## Plumbing


## Puts the world into a state where numbers encoded into pixels survive to the capture.
## See `HarnessCapture.use_measurement_environment` for why both halves of it matter.
func use_measurement_environment() -> void:
    HarnessCapture.use_measurement_environment(world)
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


func _die(code: int, message: String) -> void:
    printerr("HARNESS_ERROR " + message)
    _quit(code)


func _quit(code: int) -> void:
    if _run_started:
        return
    _run_started = true
    get_tree().quit(code)
