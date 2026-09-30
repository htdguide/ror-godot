extends GateBase
## The terrain's ground can be seen, not merely felt.
##
## The surfaces read back correctly through Terrain3D's own colour map and the grip changed at
## the right places — and a person driving saw none of it, because Terrain3D draws a checkered
## debug pattern when it has no texture assets and that pattern overrides the colour map
## entirely.
##
## Every other check of the ground reads data. This one reads pixels, which is the only way to
## tell a terrain that carries surfaces from one that is drawn with them.
##
## The subject is a terrain whose textures somebody else painted, so the two measurements are
## the ones a person actually complained about, asked of an author's own imagery: from above, is
## any of the map distinguishable from the rest of it; and at driving height, is there enough
## detail on the ground to see motion over it.

const TERRAIN_DIR: String = "assets/terrains/lapaz2"
const CONVERGE: int = 4
## Looking straight down from here, so a wide span of ground is in frame.
const CAMERA_HEIGHT_M: float = 150.0
## How far apart the brightest and darkest parts of the ground have to be. Small enough to
## survive the terrain's shading and the tonemapper, large enough that a chequerboard — which
## averages to the same grey everywhere — cannot pass.
const MIN_LUMA_GAP: float = 0.05
## And no lane may come out black, which is what an unlit or untextured terrain looks like.
const MIN_LUMA: float = 0.01
## Local contrast at driving height, as the mean absolute difference between neighbouring
## pixels relative to the local level. This is the quantity a driver reads speed from: motion
## is perceived from detail moving across the retina, and ground with none of it slides past
## invisibly however fast the vehicle is going. A flat-tinted plane reads near zero.
const MIN_LOCAL_CONTRAST: float = 0.02
## Where the camera sits for that measurement: a driver's eye height, looking at the ground
## ahead, which is the view the complaint was about.
const EYE_HEIGHT_M: float = 1.6
const LOOK_AHEAD_M: float = 18.0


static func meta() -> Dictionary:
    return {
        "name": "surfaces_are_visible",
        "proves": "the terrain draws the textures its author shipped, so a driver can see the ground they are on and see themselves move over it",
        # the ground is read from captured frames of a built Terrain3D terrain.
        "builds_on": ["smoke", "terrain3d_available"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "the ground varies in rendered luminance by at least %.2f from above, none of it is"
            % MIN_LUMA_GAP
            + " black, and it has a local contrast of at least %.2f at driving height"
            % MIN_LOCAL_CONTRAST
        ),
        "why": (
            "the surfaces were read correctly, tinted correctly and gripped correctly, and were"
            + " still invisible to the person driving on them: a debug pattern was being drawn"
            + " over the colour map. Data checks cannot see that. This reads the pixels."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M1",
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
    var err: String = harness.setup_for("hero_3q")
    if err != "":
        return fail(err)
    var terrain: Node3D = TerrainWorld.create()
    harness.world.add_child(terrain)
    await harness.advance_frames(2, "static", "terrain")
    var built: String = TerrainWorld.populate(terrain, terrain_data)
    if built != "":
        return fail(built)

    # Straight down over the middle of the map, so a wide span of ground is in frame.
    var grid: Dictionary = terrain_data.lattice()
    var middle: float = 0.5 * float((grid["size"] as int) - 1) * (grid["spacing"] as float)
    var centre: Vector3 = Vector3(
        middle, terrain_data.height_at_world(middle, middle), middle
    )
    harness.camera.look_at_from_position(
        centre + Vector3(0.0, CAMERA_HEIGHT_M, 0.0), centre, Vector3.FORWARD
    )
    var ground: MeshInstance3D = harness.world.get_node_or_null(^"Ground") as MeshInstance3D
    if ground != null:
        ground.visible = false
    var shot: Dictionary = await harness.capture_shot("surfaces", "static", CONVERGE)
    if (shot["error"] as String) != "":
        return fail(shot["error"] as String)
    var image: Image = Image.load_from_file(shot["png"] as String)
    if image == null:
        return fail("the capture at %s could not be read" % shot["png"])

    # Averaged per row: from straight above, ground that varies in one direction reads as
    # bands across the frame, and a band is invisible to a measurement taken along it.
    var rows: PackedFloat32Array = _row_luma(image)
    var lowest: float = INF
    var highest: float = 0.0
    for luma: float in rows:
        lowest = minf(lowest, luma)
        highest = maxf(highest, luma)
    if highest < MIN_LUMA:
        return fail(
            "the terrain renders black (brightest column %.4f): nothing is being drawn" % highest,
            highest
        )
    var gap: float = highest - lowest
    if gap < MIN_LUMA_GAP:
        return fail(
            "every part of the terrain renders the same brightness (%.4f to %.4f, a gap of"
            % [lowest, highest]
            + " %.4f): the surface lanes are not visible. See %s" % [gap, shot["png"]],
            gap
        )
    # The other half of the complaint: the lanes were distinguishable and still gave the eye
    # nothing to track, so a vehicle on them felt stationary.
    var eye: Vector3 = centre + Vector3(0.0, EYE_HEIGHT_M, 0.0)
    harness.camera.look_at_from_position(
        eye, eye + Vector3(LOOK_AHEAD_M, -EYE_HEIGHT_M * 0.55, 0.0), Vector3.UP
    )
    var close: Dictionary = await harness.capture_shot("surfaces/close", "static", CONVERGE)
    if (close["error"] as String) != "":
        return fail(close["error"] as String)
    var detail: float = _local_contrast(Image.load_from_file(close["png"] as String))
    if detail < MIN_LOCAL_CONTRAST:
        return fail(
            "the ground has a local contrast of %.4f at driving height, under %.4f: there is"
            % [detail, MIN_LOCAL_CONTRAST]
            + " nothing on it for the eye to track, so motion over it is not visible. See %s"
            % close["png"],
            detail
        )
    return ok(
        "%s renders from %.3f to %.3f luminance, a gap of %.3f across the map, with a local"
        % [terrain_data.name, lowest, highest, gap]
        + " contrast of %.4f at driving height: %s" % [detail, close["png"]],
        detail
    )


## Mean absolute difference between neighbouring pixels, relative to the local level.
##
## Relative, because a dark surface and a bright one should be held to the same standard: what
## matters for perceiving motion is how much the ground varies against its own brightness, not
## how many absolute units it varies by.
func _local_contrast(image: Image) -> float:
    if image == null:
        return 0.0
    var total: float = 0.0
    var count: int = 0
    # The lower half of the frame, which is the ground rather than the sky.
    for y: int in range(image.get_height() / 2, image.get_height() - 1, 2):
        for x: int in range(0, image.get_width() - 1, 2):
            var here: float = image.get_pixel(x, y).get_luminance()
            var right: float = image.get_pixel(x + 1, y).get_luminance()
            var below: float = image.get_pixel(x, y + 1).get_luminance()
            var level: float = maxf(here, 0.01)
            total += (absf(right - here) + absf(below - here)) / (2.0 * level)
            count += 1
    return total / float(maxi(count, 1))


## Mean luminance of each row, over a band of columns through the middle of the frame.
##
## Averaged per row rather than per column because the first version of this gate sampled
## columns and reported every part of the terrain as identically bright.
func _row_luma(image: Image) -> PackedFloat32Array:
    var out: PackedFloat32Array = PackedFloat32Array()
    var first: int = image.get_width() / 3
    var last: int = image.get_width() * 2 / 3
    for y: int in range(0, image.get_height(), 4):
        var total: float = 0.0
        var count: int = 0
        for x: int in range(first, last, 4):
            total += image.get_pixel(x, y).get_luminance()
            count += 1
        out.append(total / float(maxi(count, 1)))
    return out
