extends GateBase
## The sky has clouds in it, and they are the sky's own rather than a picture on a dome.
##
## A gradient sky is a dependable thing to grade lighting against and it is not a sky anybody
## believes: a session asked for clouds, and the thing that makes clouds convincing is that they
## are marched in the same direction the camera is looking rather than painted on a ceiling.
##
## Two claims. There is structure up there — a flat gradient has none — and the structure is the
## cloud layer rather than anything else in frame, which is checked by turning the cover down to
## nothing and watching the structure go with it. That negative control is the whole gate: a sky
## shader that ignored its own uniforms would pass the first half on the gradient's own banding.

const PRESET: String = "diag_origin"
const CONVERGE: int = 3
## Looking up and out, so the frame is sky and nothing else.
const EYE: Vector3 = Vector3(0.0, 2.0, 0.0)
const AIM: Vector3 = Vector3(0.0, 24.0, -40.0)
## How much the sky has to vary across the frame, as the mean absolute difference from its own
## mean brightness. A gradient alone measures about a third of this.
const MIN_STRUCTURE: float = 0.02
## And how much of that has to go when the cover is turned off.
const MIN_STRUCTURE_DROP: float = 0.5
## The sky also has to stay a sky: bright enough to be daylight, not blown out.
const SKY_LUMA_RANGE: Vector2 = Vector2(0.05, 0.95)


static func meta() -> Dictionary:
    return {
        "name": "the_sky_has_weather_in_it",
        "proves": "the sky is drawn with volumetric clouds that answer to their own cover setting, and stays a daylight sky",
        "builds_on": ["smoke"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "at least %.2f of structure across the sky, losing %.0f%% of it when the cover is"
            % [MIN_STRUCTURE, MIN_STRUCTURE_DROP * 100.0]
            + " turned off, at a brightness between %.2f and %.2f"
            % [SKY_LUMA_RANGE.x, SKY_LUMA_RANGE.y]
        ),
        "why": (
            "clouds are what tells a driver the scene has weather in it, and a cloud texture on"
            + " a dome reads as a painted ceiling the moment the camera moves. The cover control"
            + " is the honest check: structure that does not answer to it is structure that came"
            + " from somewhere else."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    if not RenderCfg.CLOUDS_ENABLED:
        return ok("skipped: this project is built with a clear sky", 0)
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)
    _hide_props(harness)
    var holder: WorldEnvironment = harness.world.get_node_or_null(
        ^"WorldEnvironment"
    ) as WorldEnvironment
    if holder == null:
        return fail("the world has no environment, so it has no sky")
    var environment: Environment = holder.environment
    # Gates are rendered under the stated gradient, because that is the sky every lighting bound
    # in this project was measured against. This one is about the other sky, so it asks for it.
    if SkyClouds.settings(environment).is_empty():
        var sky: Sky = Sky.new()
        sky.sky_material = SkyClouds.material(WeatherCfg.get_preset(harness.weather_name))
        sky.radiance_size = RenderCfg.SKY_RADIANCE_SIZE as Sky.RadianceSize
        environment.sky = sky
        environment.background_mode = Environment.BG_SKY
    if SkyClouds.settings(environment).is_empty():
        return fail("the sky is not a cloud sky: nothing here can be measured")
    # Fog would close the distance and the sky with it; this is about the sky itself.
    environment.fog_enabled = false
    harness.camera.look_at_from_position(EYE, AIM, Vector3.UP)

    var clouded: Dictionary = await _measure(harness, "clouded")
    if (clouded["error"] as String) != "":
        return fail(clouded["error"] as String)
    var structure: float = clouded["structure"] as float
    var luma: float = clouded["luma"] as float
    if luma < SKY_LUMA_RANGE.x or luma > SKY_LUMA_RANGE.y:
        return fail(
            "the sky renders at %.3f luma, outside %.2f to %.2f: that is not daylight. See %s"
            % [luma, SKY_LUMA_RANGE.x, SKY_LUMA_RANGE.y, clouded["png"]],
            luma
        )
    if structure < MIN_STRUCTURE:
        return fail(
            "the sky varies by %.4f across the frame, under %.2f: there is nothing in it. See %s"
            % [structure, MIN_STRUCTURE, clouded["png"]],
            structure
        )

    # The control: no cover, so whatever is left is the gradient and the sun.
    SkyClouds.set_parameter(environment, "coverage", 0.0)
    var clear: Dictionary = await _measure(harness, "clear")
    if (clear["error"] as String) != "":
        return fail(clear["error"] as String)
    var drop: float = 1.0 - (clear["structure"] as float) / maxf(structure, 0.0001)
    SkyClouds.set_parameter(
        environment, "coverage", SkyClouds.settings(environment).get("coverage", 0.0) as float
    )
    if drop < MIN_STRUCTURE_DROP:
        return fail(
            "turning the cover off left %.0f%% of the sky's structure behind (%.4f of %.4f):"
            % [(1.0 - drop) * 100.0, clear["structure"], structure]
            + " what is up there is not the clouds. See %s" % clear["png"],
            drop
        )
    return ok(
        "the sky carries %.4f of structure at %.3f luma, and %.0f%% of it goes when the cover"
        % [structure, luma, drop * 100.0] + " is turned off",
        structure
    )


## One frame of sky: how bright it is and how much it varies.
func _measure(harness: Node, tag: String) -> Dictionary:
    var shot: Dictionary = await harness.capture_shot("sky/%s" % tag, "static", CONVERGE)
    if (shot["error"] as String) != "":
        return {"error": shot["error"] as String, "structure": 0.0, "luma": 0.0, "png": ""}
    var image: Image = Image.load_from_file(shot["png"] as String)
    if image == null:
        return {
            "error": "the capture at %s could not be read" % shot["png"],
            "structure": 0.0, "luma": 0.0, "png": shot["png"],
        }
    var size: Vector2i = image.get_size()
    var total: float = 0.0
    var counted: int = 0
    var values: PackedFloat32Array = PackedFloat32Array()
    # The top half of the frame only: the bottom is whatever the world is standing on.
    for y: int in range(0, size.y / 2, 4):
        for x: int in range(0, size.x, 4):
            var colour: Color = image.get_pixel(x, y)
            var luma: float = colour.r * 0.2126 + colour.g * 0.7152 + colour.b * 0.0722
            values.append(luma)
            total += luma
            counted += 1
    var mean: float = total / float(maxi(counted, 1))
    var spread: float = 0.0
    for value: float in values:
        spread += absf(value - mean)
    return {
        "error": "",
        "structure": spread / float(maxi(counted, 1)),
        "luma": mean,
        "png": shot["png"],
    }


## The blockout world's own scale props would stand in the shot.
func _hide_props(harness: Node) -> void:
    for child: Node in harness.world.get_children():
        var mesh: MeshInstance3D = child as MeshInstance3D
        if mesh != null:
            mesh.visible = false
