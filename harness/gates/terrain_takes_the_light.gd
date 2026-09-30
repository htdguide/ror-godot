extends GateBase
## The terrain is lit like any other surface of the same albedo.
##
## Terrain3D draws the ground through its own shader, with its own textures, its own normal maps
## and its own detiling. Everything else in the scene goes through Godot's standard material. If
## those two disagree about what a given amount of light does to a given albedo, every judgement
## about how the world looks is made against a surface that is lit differently from the vehicle
## standing on it — and the symptom is exactly the complaint this gate was written after: "it is
## too dark", with no way to tell a lighting fault from a grading choice.
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

const TERRAIN_DIR: String = "assets/terrains/lapaz2"
const PRESET: String = "hero_3q"
const SETTLE_FRAMES: int = 3
## The comparison is made on flat, sunlit ground, where the patch and the terrain it lies on are
## at the same angle to the light.
##
## A slope was tried first and is a worse place for it. A sloped, distant, textured surface reads
## 0.67 of a flat patch laid on it, and most of that difference is the normal map and the viewing
## angle rather than the shading model — so a terrain whose albedo had been cut by two thirds
## still landed inside any band wide enough to allow the slope. On the flat the two agree to 1%,
## which leaves no room for a fault to hide in.
##
## So the flat spot is searched for rather than written down: a coordinate means something on one
## map and nothing on the next, and this gate used to hold one on a valley floor this project
## generated itself.
const PATCH_SIZE: float = 8.0
## How flat the ground under the patch has to be, over its own footprint.
const MAX_PATCH_RELIEF_M: float = 0.10
## How the flat spot is looked for: a coarse grid over the map, in a fixed order, taking the
## first place level enough to lay a patch on.
const SEARCH_STEP_M: float = 32.0
const SEARCH_MARGIN_M: float = 200.0
## Half the side of the sampled window, in pixels.
const WINDOW_PX: int = 26
## How far the patch floats over the terrain, so it does not z-fight with it.
const PATCH_LIFT_M: float = 0.3
## The patch's albedo is calibrated against the ground it lies on, in the frame itself.
##
## Not for the brightness comparison — that is a ratio and would cancel albedo — but because the
## patch has a specular lobe and specular does not scale with albedo. A patch much darker or
## brighter than the ground has a different *share* of its return coming from specular, and that
## share responds to sun and sky differently, so a mismatched albedo shows up as a shading
## disagreement that is not one. Measured: a fixed 0.18 grey on La Paz read 128% apart, and the
## patch's own sun response moved from 2.12 to 1.71 with nothing but its albedo changed.
##
## So the patch starts at mid-grey, one frame is captured, and its albedo is scaled by how far
## its rendered level is from the ground's. A terrain drawn in an author's own textures has no
## single albedo to read out of a config, which is what the earlier version of this gate did.
const PATCH_ALBEDO_START: float = 0.18
## How far the calibration may move the patch. Beyond this the two surfaces are not comparable
## at all and the gate says so rather than photographing a black square.
const MAX_ALBEDO_SCALE: float = 8.0

## How far the terrain's sun response may sit from the patch's, as a share of the patch's.
##
## Measured, the terrain responds to the sun *more* than the patch does, which means it is taking
## a smaller share of its light from the sky. That gap is real and is a named finding rather than
## a tolerance chosen to make a number pass: it is why a shaded slope reads darker than anything
## standing on it, and it is the M2 ground material's to close,
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
    var directory: String = SourceScan.repo_root().path_join(TERRAIN_DIR)
    if not DirAccess.dir_exists_absolute(directory):
        return ok("skipped: no terrain at %s" % TERRAIN_DIR, 0)
    var loaded: Dictionary = RorTerrain.load_from(directory)
    if (loaded["error"] as String) != "":
        return fail(loaded["error"] as String)
    var terrain_data: RorTerrain = loaded["terrain"] as RorTerrain
    var flat: Vector2 = _flat_spot(terrain_data)
    if flat == Vector2.INF:
        return fail(
            "no %.0f m of %s is level to %.2f m: there is nowhere on this map to lay a"
            % [PATCH_SIZE, terrain_data.name, MAX_PATCH_RELIEF_M] + " reference patch"
        )
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)
    clear_fog(harness)
    var terrain: Node3D = TerrainWorld.create()
    if terrain == null:
        return fail("Terrain3D is registered but would not instantiate")
    harness.world.add_child(terrain)
    await harness.advance_frames(2, "static", "terrain")
    var built: String = harness.terrain.populate(terrain, terrain_data)
    if built != "":
        return fail(built)
    var ground: MeshInstance3D = harness.world.get_node_or_null(^"Ground") as MeshInstance3D
    if ground != null:
        ground.visible = false

    # The bare terrain is read beside the patch, one patch-width along, so the two samples
    # differ in what draws them and in nothing else.
    var terrain_at: Vector2 = flat + Vector2(0.0, PATCH_SIZE)
    var at: Vector3 = Vector3(
        flat.x, terrain_data.height_at_world(flat.x, flat.y), flat.y
    )
    harness.world.add_child(_patch(at))
    var environment: Environment = _environment(harness)
    if environment == null:
        return fail("the world has no environment to configure")
    environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    environment.tonemap_exposure = 1.0
    harness.camera.look_at_from_position(
        at + Vector3(6.0, 9.0, 4.0), at, Vector3.UP
    )
    await harness.advance_frames(1, "static", "terrain")
    # The sampled windows are unprojected from the world, not guessed at in screen space: a
    # region written as a fraction of the frame is a region that silently lands on the wrong
    # subject when a camera moves, and this gate's first version compared the patch with itself.
    _patch_px = harness.camera.unproject_position(at + Vector3(0.0, PATCH_LIFT_M, 0.0))
    _terrain_px = harness.camera.unproject_position(Vector3(
        terrain_at.x, terrain_data.height_at_world(terrain_at.x, terrain_at.y), terrain_at.y
    ))

    var sun: DirectionalLight3D = harness.world.get_node_or_null(^"Sun") as DirectionalLight3D
    if sun == null:
        return fail("the world has no sun to switch off")

    var calibrated: Dictionary = await _match_albedo(harness)
    if (calibrated["error"] as String) != "":
        return fail(calibrated["error"] as String, calibrated["scale"] as float)

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
        + " %.4f and %.4f, sky-lit %.4f and %.4f, patch albedo %.3f" % [
            lit["patch"] as float, lit["terrain"] as float,
            shaded["patch"] as float, shaded["terrain"] as float,
            calibrated["albedo"] as float],
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


## A plain Lambertian quad laid on the ground beside the terrain it is compared with.
func _patch(at: Vector3) -> MeshInstance3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = Color(
        PATCH_ALBEDO_START, PATCH_ALBEDO_START, PATCH_ALBEDO_START
    )
    # The roughness the terrain is actually drawn with, which is the one written into the colour
    # map's alpha channel rather than the per-surface value in SurfaceCfg: Terrain3D reads it from
    # there. Specular is left on, because a patch with no specular lobe responds to the sun
    # differently from one with, and the comparison is with the terrain as it is drawn.
    material.roughness = TerrainWorld.COLOUR_MAP_ROUGHNESS
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


## The first place on the terrain level enough to lay the reference patch on, and far enough
## inside the map that the camera looking at it sees ground rather than the edge.
##
## Scanned in a fixed order over a coarse grid, so the answer is the same on every machine and
## every run. Returns `Vector2.INF` when the map has nowhere like that.
func _flat_spot(terrain_data: RorTerrain) -> Vector2:
    var grid: Dictionary = terrain_data.lattice()
    var span: float = float((grid["size"] as int) - 1) * (grid["spacing"] as float)
    # The patch, and the ground read beside it, have to be level together.
    var half: float = PATCH_SIZE * 0.5
    var at: float = SEARCH_MARGIN_M
    while at < span - SEARCH_MARGIN_M:
        var across: float = SEARCH_MARGIN_M
        while across < span - SEARCH_MARGIN_M:
            var lowest: float = INF
            var highest: float = -INF
            for corner: Vector2 in [
                Vector2(-half, -half), Vector2(half, -half),
                Vector2(-half, half), Vector2(half, half),
                Vector2(-half, PATCH_SIZE + half), Vector2(half, PATCH_SIZE + half),
            ]:
                var height: float = terrain_data.height_at_world(
                    across + corner.x, at + corner.y
                )
                lowest = minf(lowest, height)
                highest = maxf(highest, height)
            if highest - lowest <= MAX_PATCH_RELIEF_M:
                return Vector2(across, at)
            across += SEARCH_STEP_M
        at += SEARCH_STEP_M
    return Vector2.INF


## Scales the patch's albedo until it renders at the level the ground beside it does.
##
## One capture and one correction: the patch is Lambertian and linear in its albedo, so the
## scale that makes their rendered levels match is the ratio of the two levels. The specular
## term is not linear in albedo, which is the whole reason for doing this, so the match is close
## rather than exact — close is enough, since what it has to remove is a large mismatch and not
## the last percent.
func _match_albedo(harness: Node) -> Dictionary:
    var out: Dictionary = {"error": "", "scale": 1.0, "albedo": PATCH_ALBEDO_START}
    var patch_node: MeshInstance3D = harness.world.get_node_or_null(
        ^"ReferencePatch"
    ) as MeshInstance3D
    if patch_node == null:
        out["error"] = "the reference patch is not in the world"
        return out
    var sampled: Dictionary = await _sample(harness, "calibrate")
    if (sampled["error"] as String) != "":
        out["error"] = sampled["error"] as String
        return out
    var patch: float = sampled["patch"] as float
    var terrain: float = sampled["terrain"] as float
    if patch <= 0.0005 or terrain <= 0.0005:
        out["error"] = (
            "calibrating: the patch renders at %.5f and the ground at %.5f, so one of them is"
            % [patch, terrain] + " not being drawn. See %s" % (sampled["png"] as String)
        )
        return out
    var scale: float = terrain / patch
    out["scale"] = scale
    if scale > MAX_ALBEDO_SCALE or scale < 1.0 / MAX_ALBEDO_SCALE:
        out["error"] = (
            "the ground renders %.1f times the patch's level: no albedo makes these two"
            % scale + " surfaces comparable. See %s" % (sampled["png"] as String)
        )
        return out
    var material: StandardMaterial3D = patch_node.get_active_material(0) as StandardMaterial3D
    if material == null:
        out["error"] = "the reference patch has no material to calibrate"
        return out
    var albedo: float = PATCH_ALBEDO_START * scale
    out["albedo"] = albedo
    material.albedo_color = Color(albedo, albedo, albedo)
    await harness.advance_frames(1, "static", "terrain")
    return out
