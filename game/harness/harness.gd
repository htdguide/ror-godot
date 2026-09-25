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
var frame_index: int = 0
var preset_name: String = ""
var preset: Dictionary = {}

var _main: Node
var _run_started: bool = false


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
    _apply_determinism()
    if args.values.has("gate"):
        _run_gate(args.get_string("gate", ""))
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


func _build_world(scenario: String, weather: String) -> String:
    if not Scenarios.has(scenario):
        return "unknown scenario '%s'; known: %s" % [scenario, Scenarios.names()]
    if not WeatherCfg.has(weather):
        return "unknown weather preset '%s'" % weather
    world = BlockoutWorld.build(WeatherCfg.get_preset(weather))
    _main.add_child(world)
    camera = _build_camera(preset)
    world.add_child(camera)
    metrics = HarnessMetrics.new()
    metrics.begin(get_viewport())
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
    if args.has_flag("play"):
        var rig: PlayRig = PlayRig.new()
        rig.name = "PlayRig"
        add_child(rig)
        rig.setup(camera, world, weather)
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
    var err: String = HarnessCapture.capture_png(get_viewport(), png_path)
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
            "resolution": "%dx%d" % [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
            "summary": summary,
        }
    )
    if err != "":
        return {"error": err, "png": "", "manifest": ""}
    return {"error": "", "png": png_path, "manifest": manifest_path}


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


func _run_gate(name: String) -> void:
    var script_path: String = "%s/%s.gd" % [GATE_DIR, name]
    if not ResourceLoader.exists(script_path):
        _die(EXIT_USAGE, "no gate '%s' at %s" % [name, script_path])
        return
    var gate_script: GDScript = load(script_path) as GDScript
    if gate_script == null or not gate_script.can_instantiate():
        _die(EXIT_USAGE, "gate '%s' failed to compile; see the parse errors above" % name)
        return
    var meta_dict: Dictionary = gate_script.call("meta") as Dictionary
    var meta_error: String = GateBase.validate_meta(meta_dict)
    if meta_error != "":
        _die(EXIT_USAGE, "gate '%s' metadata invalid: %s" % [name, meta_error])
        return
    var gate: GateBase = gate_script.new() as GateBase
    print("HARNESS_GATE_BEGIN " + JSON.stringify(meta_dict))
    var started_usec: int = Time.get_ticks_usec()
    var result: Dictionary = await gate.run(self)
    var elapsed_s: float = float(Time.get_ticks_usec() - started_usec) / 1000000.0
    var passed: bool = result.get("pass", false) as bool
    var over_budget: bool = elapsed_s > float(meta_dict["budget_s"])
    var row: Dictionary = {
        "gate": name,
        "pass": passed and not over_budget,
        "detail": result.get("detail", "") as String,
        "measured": result.get("measured"),
        "threshold": meta_dict["threshold"],
        "oracle": meta_dict["oracle"],
        "elapsed_s": snappedf(elapsed_s, 0.01),
        "budget_s": meta_dict["budget_s"],
        "over_budget": over_budget,
    }
    print("HARNESS_GATE_RESULT " + JSON.stringify(row))
    _quit(EXIT_OK if row["pass"] else EXIT_FAIL)


## Builds the world a gate asked for. Gates never construct scenes themselves.
func setup_for(shot: String) -> String:
    var err: String = _resolve_preset(shot)
    if err != "":
        return err
    return _build_world(
        args.get_string("scenario", preset.get("scenario", "static") as String),
        args.get_string("weather", preset.get("weather", "noon_clear") as String)
    )


## --------------------------------------------------------------------------------
## Plumbing


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
