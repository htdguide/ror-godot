extends GateBase
## A shipped terrain's road markings land on its road.
##
## La Paz's road texture is a whole cross-section: dirt shoulder, white edge line, two lanes
## either side of a double yellow centre line, edge line, shoulder — 10.1 m of it, laid across an
## 11.5 m band of asphalt whose centre is at z = 45. If the tiling is half a tile out, every one
## of those markings is still drawn and every one of them is in the wrong place, which is what a
## session reported: "one wide lane, and the separation line is on the right".
##
## Terrain3D samples a texture at `world.xz * uv_scale - 0.5`, so it is half a tile out by
## construction. This measures the result rather than the arithmetic: it photographs the road
## from directly above and finds the yellow line in the picture, then asks where that is in the
## world.

const TERRAIN_DIR: String = "assets/terrains/lapaz2"
const PRESET: String = "hero_3q"
const CONVERGE: int = 3
## Looking straight down at the road from here, over a straight stretch of it.
const OVER: Vector2 = Vector2(3700.0, 45.0)
const CAMERA_HEIGHT_M: float = 26.0
## Where the road is, measured from the terrain's own traction map rather than written down.
const ROAD_SURFACE: String = "asphalt"
const BAND_SEARCH_M: float = 30.0
## How far the centre line may sit from the middle of the asphalt.
##
## Measured at 0.35 m. The bound is not tighter because the middle of the asphalt is itself only
## known to about half a metre: the traction map that says where the road is has one pixel every
## 3.9 m. Half a tile out — the fault this exists for — reads as 5.1 m.
const MAX_OFFSET_M: float = 0.9
## What counts as the yellow line: a pixel much more yellow than grey asphalt.
const MIN_YELLOWNESS: float = 0.06


static func meta() -> Dictionary:
    return {
        "name": "ror_terrain_road_is_where_it_is_painted",
        "proves": "a shipped terrain's road texture tiles where its author laid it, with the centre line down the middle of the asphalt",
        "builds_on": ["ror_terrain_is_drivable"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "the yellow centre line within %.1f m of the middle of the asphalt band, measured"
            % MAX_OFFSET_M + " in a rendered frame"
        ),
        "why": (
            "a half-tile offset in a ground texture is invisible on dirt and glaring on a road:"
            + " every marking is drawn and every one is in the wrong place. Terrain3D samples at"
            + " world * scale - 0.5, so this is off by construction unless something cancels it,"
            + " and the only honest check is where the paint lands in the picture."
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
        return ok("skipped: Terrain3D is not installed", 0)
    var loaded: Dictionary = RorTerrain.load_from(directory)
    if (loaded["error"] as String) != "":
        return fail(loaded["error"] as String)
    var terrain_data: RorTerrain = loaded["terrain"] as RorTerrain

    # Where the road actually is, from the terrain's own traction map.
    var band: Dictionary = _asphalt_band(terrain_data)
    if (band["error"] as String) != "":
        return fail(band["error"] as String)

    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)
    var terrain: Node3D = TerrainWorld.create()
    harness.world.add_child(terrain)
    await harness.advance_frames(2, "static", "terrain")
    var built: String = harness.terrain.populate(terrain, terrain_data)
    if built != "":
        return fail(built)
    var ground: MeshInstance3D = harness.world.get_node_or_null(^"Ground") as MeshInstance3D
    if ground != null:
        ground.visible = false
    var centre: Vector3 = Vector3(OVER.x, terrain_data.height_at_world(OVER.x, OVER.y), OVER.y)
    harness.camera.look_at_from_position(
        centre + Vector3(0.0, CAMERA_HEIGHT_M, 0.0), centre, Vector3.FORWARD
    )
    await harness.advance_frames(1, "static", "road")
    var shot: Dictionary = await harness.capture_shot("road_markings", "static", CONVERGE)
    if (shot["error"] as String) != "":
        return fail(shot["error"] as String)
    var image: Image = Image.load_from_file(shot["png"] as String)
    if image == null:
        return fail("the capture at %s could not be read" % shot["png"])

    var found: Dictionary = _yellow_line(harness, image, terrain_data, band)
    if (found["error"] as String) != "":
        return fail(found["error"] as String, found["value"] as float)
    var off: float = absf((found["value"] as float) - (band["centre"] as float))
    if off > MAX_OFFSET_M:
        return fail(
            "the centre line is painted at z = %.2f where the asphalt runs %.2f to %.2f, %.2f m"
            % [found["value"], band["first"], band["last"], off]
            + " off its middle. See %s" % shot["png"],
            off
        )
    return ok(
        "the centre line lands at z = %.2f, %.2f m from the middle of an asphalt band %.1f m"
        % [found["value"], off, (band["last"] as float) - (band["first"] as float)]
        + " wide",
        off
    )


## Where the asphalt is, across the road, from the terrain's own traction map.
func _asphalt_band(terrain_data: RorTerrain) -> Dictionary:
    var first: float = INF
    var last: float = -INF
    var step: float = 0.25
    var count: int = int(BAND_SEARCH_M * 2.0 / step)
    for index: int in count:
        var z: float = OVER.y - BAND_SEARCH_M + float(index) * step
        if terrain_data.models.name_of(terrain_data.surface_at_world(OVER.x, z)) == ROAD_SURFACE:
            first = minf(first, z)
            last = maxf(last, z)
    if not is_finite(first) or last <= first:
        return {"error": "there is no %s within %.0f m of %v" % [
            ROAD_SURFACE, BAND_SEARCH_M, OVER], "centre": 0.0, "first": 0.0, "last": 0.0}
    return {"error": "", "centre": (first + last) * 0.5, "first": first, "last": last}


## Where the yellow line is in the world, found in the picture.
##
## Yellowness rather than brightness: the road carries white edge lines too, and the one that
## says where the middle is is the yellow one.
func _yellow_line(
    harness: Node, image: Image, terrain_data: RorTerrain, band: Dictionary
) -> Dictionary:
    var size: Vector2i = image.get_size()
    var camera: Camera3D = harness.camera
    # Walk across the road in world metres and read the pixel each lands on, so the answer is in
    # metres without having to invert the projection.
    var best: float = -1.0
    var best_z: float = 0.0
    var step: float = 0.05
    var count: int = int(((band["last"] as float) - (band["first"] as float)) / step)
    for index: int in count:
        var z: float = (band["first"] as float) + float(index) * step
        var at: Vector3 = Vector3(
            OVER.x, terrain_data.height_at_world(OVER.x, z), z
        )
        var pixel: Vector2 = camera.unproject_position(at)
        if pixel.x < 0.0 or pixel.y < 0.0 or pixel.x >= float(size.x) or pixel.y >= float(size.y):
            continue
        var colour: Color = image.get_pixel(int(pixel.x), int(pixel.y))
        # Yellow is red and green together, without blue.
        var yellowness: float = minf(colour.r, colour.g) - colour.b
        if yellowness > best:
            best = yellowness
            best_z = z
    if best < MIN_YELLOWNESS:
        return {
            "error": (
                "the most yellow point across the road reads %.3f, under %.2f: there is no"
                % [best, MIN_YELLOWNESS] + " centre line in the picture"
            ),
            "value": best,
        }
    return {"error": "", "value": best_z}
