extends GateBase
## Photographs the valley from every named anchor, and checks each frame has a world in it.
##
## The vehicle has `vehicle_photoset` for the same reason: one view hides too much. A terrain has
## its own version of that — a camera inside a hillside, a region that failed to import, water
## built under its own bed — and each of them looks like a perfectly ordinary frame of something
## else unless somebody is looking at the right place.
##
## So this both produces the sheet a human session is run from (`tools/valley_shots.sh`) and makes
## a claim about every frame in it: the ground is visible, the frame is not black, and it is not
## all sky. The claim is deliberately weak, because what these pictures are for is a person
## looking at them; it is here so that a broken world fails the suite instead of waiting for one.

const CONVERGE: int = 4
## Views are numbered so a person can point at one.
const VIEWS: Array[String] = [
    "spawn", "ford", "lake", "ruts", "rock_traverse", "switchback", "ridge_vista",
]
## A frame this dark is a camera inside the terrain or a scene that failed to light.
const MIN_LUMA: float = 0.02
## And this much of the frame has to be something other than sky, or the camera is pointing over
## the world rather than at it.
const MIN_GROUND_FRACTION: float = 0.15
## Sky is the brightest thing in a daylit frame and it is blue: a pixel counts as ground when it
## is not both.
const SKY_LUMA: float = 0.35


static func meta() -> Dictionary:
    return {
        "name": "valley_photoset",
        "proves": "every named place in the valley renders a frame with ground in it, and the set of them is captured for a human session",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "%d views, each brighter than %.2f luma with at least %.0f%% of the frame not sky"
            % [VIEWS.size(), MIN_LUMA, MIN_GROUND_FRACTION * 100.0]
        ),
        "why": (
            "a terrain fails in ways that look like an ordinary picture of somewhere else: a"
            + " camera inside a hillside, a region that did not import, water under its own bed."
            + " The sheet exists for a person to look at; the bound exists so that a world with a"
            + " hole in it fails here rather than in a session."
        ),
        "budget_s": 180.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    if not ClassDB.class_exists("Terrain3D"):
        return ok("skipped: Terrain3D is not installed. Run tools/build_terrain3d.sh", 0)
    var err: String = harness.setup_for("hero_3q")
    if err != "":
        return fail(err)
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
    harness.world.add_child(Tunnel.build())
    var water: Node3D = ValleyWater.build()
    if water != null:
        harness.world.add_child(water)

    var reported: PackedStringArray = PackedStringArray()
    var darkest: float = INF
    for index: int in VIEWS.size():
        var view: String = VIEWS[index]
        var anchor: Dictionary = ValleyLayout.ANCHORS.get(view, {}) as Dictionary
        if anchor.is_empty():
            return fail("there is no anchor named '%s' in the layout" % view)
        harness.camera.look_at_from_position(
            _resolve(anchor["position"] as Vector3),
            _resolve(anchor["look_at"] as Vector3),
            Vector3.UP
        )
        var shot: Dictionary = await harness.capture_shot(
            "valley/%d_%s" % [index + 1, view], "static", CONVERGE
        )
        if (shot["error"] as String) != "":
            return fail(shot["error"] as String)
        var image: Image = Image.load_from_file(shot["png"] as String)
        if image == null:
            return fail("the capture at %s could not be read" % shot["png"])
        var measured: Dictionary = _measure(image)
        var luma: float = measured["luma"] as float
        var ground_fraction: float = measured["ground"] as float
        darkest = minf(darkest, luma)
        if luma < MIN_LUMA:
            return fail(
                "view %d (%s) renders at %.4f luma: there is nothing in frame. See %s"
                % [index + 1, view, luma, shot["png"]],
                luma
            )
        if ground_fraction < MIN_GROUND_FRACTION:
            return fail(
                "view %d (%s) is %.0f%% sky: the camera is not looking at the valley. See %s"
                % [index + 1, view, (1.0 - ground_fraction) * 100.0, shot["png"]],
                ground_fraction
            )
        reported.append("%d %s %.0f%% ground" % [index + 1, view, ground_fraction * 100.0])
    return ok(
        "%d views captured, darkest %.3f luma: " % [VIEWS.size(), darkest]
        + ", ".join(reported),
        darkest
    )


## An anchor's height is metres above the terrain under it, so that moving a feature moves the
## camera that frames it.
func _resolve(anchor: Vector3) -> Vector3:
    return Vector3(anchor.x, ValleyShape.height_at_world(anchor.x, anchor.z) + anchor.y, anchor.z)


## How bright a frame is, and how much of it is not sky.
func _measure(image: Image) -> Dictionary:
    var size: Vector2i = image.get_size()
    var total: float = 0.0
    var ground: int = 0
    var step: int = 4
    var counted: int = 0
    for y: int in range(0, size.y, step):
        for x: int in range(0, size.x, step):
            var colour: Color = image.get_pixel(x, y)
            var luma: float = colour.r * 0.2126 + colour.g * 0.7152 + colour.b * 0.0722
            total += luma
            counted += 1
            # Sky is bright and blue; anything else in a daylit frame is the world.
            if not (luma > SKY_LUMA and colour.b > colour.r * 1.05):
                ground += 1
    return {"luma": total / float(counted), "ground": float(ground) / float(counted)}
