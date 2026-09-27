extends GateBase
## The terrain is lit like any other surface of the same albedo.
##
## Terrain3D draws the ground through its own shader, with its own textures, its own normal maps
## and its own detiling. Everything else in the scene goes through Godot's standard material. If
## those two disagree about what a given amount of light does to a given albedo, every judgement
## about how the valley looks is made against a surface that is lit differently from the vehicle
## standing on it — and the symptom is exactly the complaint this gate was written after: "the
## valley is too dark", with no way to tell a lighting fault from a grading choice.
##
## The oracle is a reference patch: a plain Lambertian quad laid on the terrain, photographed in
## the same frame under the same light. What is compared is not their brightness but how each
## *responds* to the sun being switched off — the ratio between what a surface returns in sunlight
## and what it returns under sky alone.
##
## Comparing brightness directly was tried first and is a weaker check than it looks, because the
## patch's albedo has to be computed from the same constants the terrain is built from: change one
## and both move, and the comparison passes while agreeing about the wrong number. The response
## ratio has no such escape. It cancels albedo entirely, so what is left is the shading model: a
## terrain that ignores the sky, or double-counts the sun, or is shaded flat, cannot match a
## Lambertian surface standing on it.
##
## Measured scene-referred, with linear tonemapping at unit exposure, because what is being
## compared is the light the two surfaces return and not how the grade treats it.

const PRESET: String = "hero_3q"
const SETTLE_FRAMES: int = 3
## Where the comparison is made: the valley floor beside the spawn point, flat and sunlit, where
## the patch and the terrain it lies on are the same surface at the same angle to the light.
##
## The wall was tried first and is a worse place for it. A sloped, distant, textured surface reads
## 0.67 of a flat patch laid on it, and most of that difference is the normal map and the viewing
## angle rather than the shading model — so a terrain whose albedo had been cut by two thirds
## still landed inside any band wide enough to allow the slope. On the flat the two agree to 1%,
## which leaves no room for a fault to hide in.
const PATCH_AT: Vector2 = Vector2(-18.0, 0.0)
const PATCH_SIZE: float = 8.0
## Where the bare terrain is read, beside the patch and on the same surface lane, so the two
## samples differ in what draws them and in nothing else.
const TERRAIN_AT: Vector2 = Vector2(-18.0, 8.0)
## Half the side of the sampled window, in pixels.
const WINDOW_PX: int = 26
## How far the patch floats over the terrain, so it does not z-fight with it.
const PATCH_LIFT_M: float = 0.3
## The surface whose tint the patch is matched to, and the mean of the generated texture that
## multiplies it. Both are read from the config rather than restated.
const SURFACE: String = "sand"

## How far the terrain's sun response may sit from the patch's, as a share of the patch's.
##
## Measured, the terrain responds to the sun *more* than the patch does — 3.19 against 2.63 — which
## means it is taking a smaller share of its light from the sky. That gap is real and is a named
## finding rather than a tolerance chosen to make a number pass: it is why the valley's shaded
## walls read darker than anything standing on them, and it is the M2 ground material's to close,
## since that replaces Terrain3D's shading with a shader this project owns. Roughness, the normal
## map's depth, the texture's brightness and the asset's albedo colour were each tried and none of
## them moved the picture at all — Terrain3D draws the ground from the colour map and the
## heightmap, and the texture assets attached to it reach nothing.
##
## The bound is set above that gap so the gate holds the line where it is, rather than pretending
## the gap is not there. It still fails a terrain that stops taking sky light altogether, which
## reads in the hundreds of per cent.
const MAX_RESPONSE_ERROR: float = 0.30

var _patch_px: Vector2 = Vector2.ZERO
var _terrain_px: Vector2 = Vector2.ZERO


static func meta() -> Dictionary:
    return {
        "name": "terrain_takes_the_light",
        "proves": "the terrain responds to the sun and the sky the way a Lambertian surface standing on it does",
        # the comparison is two surfaces in a rendered frame of a built Terrain3D valley.
        "builds_on": ["smoke", "terrain3d_available"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "terrain's sunlit-to-shaded response within %.0f%% of the reference patch's" % (
            MAX_RESPONSE_ERROR * 100.0),
        "why": (
            "the ground is drawn by a different shader from everything standing on it, and if"
            + " the two disagree about light then 'the valley is too dark' cannot be told from"
            + " 'the grading is dark', which is a day of looking in the wrong place. Comparing"
            + " the response to the sun rather than the brightness removes albedo from the"
            + " comparison, and with it the trap of checking a number against the constant it"
            + " was computed from."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M2b",
    }


func run(harness: Node) -> Dictionary:
    if not ClassDB.class_exists("Terrain3D"):
        return ok("skipped: Terrain3D is not installed. Run tools/build_terrain3d.sh", 0)
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)
    clear_fog(harness)
    var terrain: Node3D = ValleyTerrain.create()
    if terrain == null:
        return fail("Terrain3D is registered but would not instantiate")
    harness.world.add_child(terrain)
    await harness.advance_frames(2, "static", "terrain")
    var built: String = ValleyTerrain.populate(terrain)
    if built != "":
        return fail(built)
    var ground: MeshInstance3D = harness.world.get_node_or_null(^"Ground") as MeshInstance3D
    if ground != null:
        ground.visible = false

    var at: Vector3 = Vector3(
        PATCH_AT.x, ValleyShape.height_at_world(PATCH_AT.x, PATCH_AT.y), PATCH_AT.y
    )
    harness.world.add_child(_patch(at))
    var environment: Environment = _environment(harness)
    if environment == null:
        return fail("the world has no environment to configure")
    environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    environment.tonemap_exposure = 1.0
    harness.camera.look_at_from_position(
        Vector3(6.0, 9.0, 4.0), at, Vector3.UP
    )
    await harness.advance_frames(1, "static", "terrain")
    # The sampled windows are unprojected from the world, not guessed at in screen space: a
    # region written as a fraction of the frame is a region that silently lands on the wrong
    # subject when a camera moves, and this gate's first version compared the patch with itself.
    _patch_px = harness.camera.unproject_position(at + Vector3(0.0, PATCH_LIFT_M, 0.0))
    _terrain_px = harness.camera.unproject_position(Vector3(
        TERRAIN_AT.x, ValleyShape.height_at_world(TERRAIN_AT.x, TERRAIN_AT.y), TERRAIN_AT.y
    ))

    var sun: DirectionalLight3D = harness.world.get_node_or_null(^"Sun") as DirectionalLight3D
    if sun == null:
        return fail("the world has no sun to switch off")

    var lit: Dictionary = await _sample(harness, "lit")
    if (lit["error"] as String) != "":
        return fail(lit["error"] as String)
    # The two sampled regions have to be on different subjects, and nothing about a camera
    # placement says they are: hiding the patch has to change one and leave the other alone. A
    # patch large enough to fill both regions would otherwise be compared against itself.
    var patch_node: Node3D = harness.world.get_node_or_null(^"ReferencePatch") as Node3D
    patch_node.visible = false
    var bare: Dictionary = await _sample(harness, "bare")
    patch_node.visible = true
    if (bare["error"] as String) != "":
        return fail(bare["error"] as String)
    var patch_moved: float = absf((bare["patch"] as float) - (lit["patch"] as float))
    var terrain_moved: float = absf((bare["terrain"] as float) - (lit["terrain"] as float))
    if patch_moved < 0.01 or terrain_moved > 0.005:
        return fail(
            "hiding the patch moved the patch region by %.4f and the terrain region by %.4f:"
            % [patch_moved, terrain_moved]
            + " the two regions are not on the two subjects. See %s" % (lit["png"] as String),
            patch_moved
        )
    var energy: float = sun.light_energy
    sun.light_energy = 0.0
    var shaded: Dictionary = await _sample(harness, "shaded")
    sun.light_energy = energy
    if (shaded["error"] as String) != "":
        return fail(shaded["error"] as String)

    if (shaded["patch"] as float) <= 0.0005 or (shaded["terrain"] as float) <= 0.0005:
        return fail(
            "under the sky alone the patch returns %.5f and the terrain %.5f: one of them is"
            % [shaded["patch"] as float, shaded["terrain"] as float]
            + " not being lit by the sky at all",
            shaded["terrain"]
        )
    var patch_response: float = (lit["patch"] as float) / (shaded["patch"] as float)
    var terrain_response: float = (lit["terrain"] as float) / (shaded["terrain"] as float)
    var error: float = absf(terrain_response - patch_response) / patch_response
    if error > MAX_RESPONSE_ERROR:
        return fail(
            "the sun multiplies the patch by %.2f and the terrain by %.2f, %.0f%% apart"
            % [patch_response, terrain_response, error * 100.0]
            + " (sunlit %.4f and %.4f, sky-lit %.4f and %.4f): the ground is not shaded like"
            % [lit["patch"] as float, lit["terrain"] as float,
               shaded["patch"] as float, shaded["terrain"] as float]
            + " the things standing on it. See %s" % (lit["png"] as String),
            error
        )
    return ok(
        "the sun multiplies the patch by %.2f and the terrain by %.2f, %.1f%% apart; sunlit"
        % [patch_response, terrain_response, error * 100.0]
        + " %.4f and %.4f, sky-lit %.4f and %.4f" % [
            lit["patch"] as float, lit["terrain"] as float,
            shaded["patch"] as float, shaded["terrain"] as float],
        error
    )


## Captures one frame and reads the patch and the terrain beside it.
func _sample(harness: Node, name: String) -> Dictionary:
    var shot: Dictionary = await harness.capture_shot(
        "terrain_light/%s" % name, "static", SETTLE_FRAMES
    )
    if (shot["error"] as String) != "":
        return {"error": shot["error"], "patch": 0.0, "terrain": 0.0, "png": ""}
    var image: Image = Image.load_from_file(shot["png"] as String)
    if image == null:
        return {
            "error": "the capture at %s could not be read" % shot["png"],
            "patch": 0.0, "terrain": 0.0, "png": "",
        }
    return {
        "error": "",
        "png": shot["png"],
        "patch": _window(image, _patch_px),
        "terrain": _window(image, _terrain_px),
    }


## The mean luma of a square window of the frame, centred on a projected world position.
func _window(image: Image, centre: Vector2) -> float:
    var size: Vector2i = image.get_size()
    return _region(
        image,
        clampi(int(centre.x) - WINDOW_PX, 0, size.x - 1),
        clampi(int(centre.x) + WINDOW_PX, 1, size.x),
        clampi(int(centre.y) - WINDOW_PX, 0, size.y - 1),
        clampi(int(centre.y) + WINDOW_PX, 1, size.y)
    )


## A plain Lambertian quad, albedo matched to the terrain's tint times the mean of the texture
## that multiplies it, laid on the floor beside the terrain it is compared with.
func _patch(at: Vector3) -> MeshInstance3D:
    var tint: Color = TerrainCfg.SURFACE_COLOURS[SURFACE] as Color
    var mean: float = SurfaceCfg.DETAIL_BASE
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = Color(tint.r * mean, tint.g * mean, tint.b * mean)
    # The roughness the terrain is actually drawn with, which is the one written into the colour
    # map's alpha channel rather than the per-surface value in SurfaceCfg: Terrain3D reads it from
    # there. Specular is left on, because a patch with no specular lobe responds to the sun
    # differently from one with, and the comparison is with the terrain as it is drawn.
    material.roughness = ValleyTerrain.COLOUR_MAP_ROUGHNESS
    var plane: PlaneMesh = PlaneMesh.new()
    plane.size = Vector2(PATCH_SIZE, PATCH_SIZE)
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = "ReferencePatch"
    instance.mesh = plane
    instance.material_override = material
    instance.position = at + Vector3(0.0, PATCH_LIFT_M, 0.0)
    return instance


func _region(image: Image, x0: int, x1: int, y0: int, y1: int) -> float:
    var total: float = 0.0
    var counted: int = 0
    for y: int in range(y0, y1):
        for x: int in range(x0, x1):
            var colour: Color = image.get_pixel(x, y)
            total += colour.r * 0.2126 + colour.g * 0.7152 + colour.b * 0.0722
            counted += 1
    return total / float(counted)


func _environment(harness: Node) -> Environment:
    var holder: WorldEnvironment = harness.world.get_node_or_null(
        ^"WorldEnvironment"
    ) as WorldEnvironment
    return holder.environment if holder != null else null
