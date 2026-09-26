extends GateBase
## The water is drawn, and it fades with depth instead of ending at a line.
##
## Every other check of the water reads elevations. This one reads pixels, which is the only way
## to tell water that exists from water that is drawn: the surface lanes were tinted correctly,
## read back correctly and gripped correctly for a whole session while a debug pattern was drawn
## over them, and a water surface has more ways to be invisible than a terrain does — a shader that
## failed to compile, a mesh with no material, a fade that takes the alpha to zero everywhere, a
## surface built under the bed.
##
## The comparison is the same view with the water hidden, so there is no golden image: what is
## measured is how much of the frame the water changed and whether the change is a gradient.
##
## The gradient is the half that matters. A flat blue slab over the basin would pass a "did
## anything change" check, and it is exactly what placeholder water looks like. Water shallow at
## the shore and deep offshore has to render differently in the two places.

const CONVERGE: int = 4
## Looking across the shoreline from over the lake's dry side, so the frame holds both the shallows
## and the deep water. The ripple's normals need a glancing angle to catch the sun at all.
const EYE: Vector3 = Vector3(-700.0, 14.0, 90.0)
const LOOK_AT: Vector3 = Vector3(-880.0, -10.0, -10.0)
## How much of the frame the water has to change. The lake fills a good part of this view, so a
## bound this low still fails a surface that is missing and passes one partly hidden by terrain.
const MIN_CHANGED_FRACTION: float = 0.08
## A pixel counts as changed when its luma moves by this much. Above the noise a GPU is allowed.
const CHANGED_LUMA: float = 0.02
## How much more the water has to change the frame offshore than it does in the shallows.
##
## Measured as the change the water makes — the wet frame against the dry one — and not as the
## rendered brightness of the water itself. The bed under a lake is bright sand at the shore and
## dark rock offshore, so the water's *own* brightness has a gradient in it whatever the water
## does: a first version of this check measured that, and a flat slab with its depth fade turned
## off passed it with a difference of 0.094.
const MIN_FADE_GROWTH: float = 0.05


static func meta() -> Dictionary:
    return {
        "name": "water_is_drawn",
        "proves": "the lake renders as water and fades with depth, rather than being absent or a flat slab",
        # the lake is rendered over a built Terrain3D valley and captured twice.
        "builds_on": ["smoke", "terrain3d_available"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "at least %.0f%% of the frame changes when the water is hidden, and the water hides"
            % (MIN_CHANGED_FRACTION * 100.0)
            + " at least %.3f more of the bed offshore than it does in the shallows"
            % MIN_FADE_GROWTH
        ),
        "why": (
            "the surface lanes were tinted, read back and gripped correctly while a debug pattern"
            + " was drawn over them, and nothing in the suite could see it. Water has more ways to"
            + " be invisible than that. The gradient half is there because a flat slab over the"
            + " basin passes any check that only asks whether something changed, and a flat slab"
            + " is what placeholder water looks like."
        ),
        "budget_s": 120.0,
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

    var water: Node3D = ValleyWater.build()
    if water == null:
        return fail("the water shader would not load")
    harness.world.add_child(water)
    harness.camera.look_at_from_position(EYE, LOOK_AT, Vector3.UP)

    var wet: Dictionary = await harness.capture_shot("water/wet", "static", CONVERGE)
    if (wet["error"] as String) != "":
        return fail(wet["error"] as String)
    water.visible = false
    var dry: Dictionary = await harness.capture_shot("water/dry", "static", CONVERGE)
    if (dry["error"] as String) != "":
        return fail(dry["error"] as String)

    var with_water: Image = Image.load_from_file(wet["png"] as String)
    var without: Image = Image.load_from_file(dry["png"] as String)
    if with_water == null or without == null:
        return fail("the captures at %s could not be read" % wet["png"])

    var changed: Dictionary = _changed(with_water, without)
    var fraction: float = changed["fraction"] as float
    if fraction < MIN_CHANGED_FRACTION:
        return fail(
            "hiding the water changed %.2f%% of the frame, under %.0f%%: it is not being drawn."
            % [fraction * 100.0, MIN_CHANGED_FRACTION * 100.0]
            + " See %s against %s" % [wet["png"], dry["png"]],
            fraction
        )

    # How much the water changes the frame, near and far, over the pixels it changed at all: the
    # projection of the lake is not a rectangle, so splitting the frame in half would compare
    # water against terrain.
    var fade: Dictionary = _fade(with_water, without, changed["mask"] as PackedByteArray)
    var growth: float = (fade["deep"] as float) - (fade["shallow"] as float)
    if growth < MIN_FADE_GROWTH:
        return fail(
            "the water hides %.4f of the bed in the shallows and %.4f offshore, a difference of"
            % [fade["shallow"] as float, fade["deep"] as float]
            + " %.4f: it is a flat slab, not a depth fade. See %s" % [growth, wet["png"]],
            growth
        )
    return ok(
        "the water covers %.1f%% of the frame and its cover grows from %.4f in the shallows to"
        % [fraction * 100.0, fade["shallow"] as float]
        + " %.4f offshore, a difference of %.4f: %s" % [fade["deep"] as float, growth, wet["png"]],
        growth
    )


## Which pixels the water changed, and what fraction of the frame that is.
func _changed(with_water: Image, without: Image) -> Dictionary:
    if with_water.get_size() != without.get_size():
        return {"fraction": 0.0, "mask": PackedByteArray()}
    var size: Vector2i = with_water.get_size()
    var mask: PackedByteArray = PackedByteArray()
    mask.resize(size.x * size.y)
    var count: int = 0
    for y: int in size.y:
        var row: int = y * size.x
        for x: int in size.x:
            var delta: float = absf(
                _luma(with_water.get_pixel(x, y)) - _luma(without.get_pixel(x, y))
            )
            if delta > CHANGED_LUMA:
                mask[row + x] = 1
                count += 1
    return {"fraction": float(count) / float(size.x * size.y), "mask": mask}


## How much the water changes the frame in its nearest tenth of rows and its furthest tenth.
##
## Rows stand in for depth: the camera looks across the shoreline, so the water's near edge is the
## shallow end and its far edge the deep one. Only pixels the water changed are counted, so the
## terrain either side of the lake does not enter either average, and what is averaged is the
## change itself — how much of the bed the water hides — rather than how bright the water is.
func _fade(
    with_water: Image, without: Image, mask: PackedByteArray
) -> Dictionary:
    var size: Vector2i = with_water.get_size()
    var rows: Array[float] = []
    var counts: Array[int] = []
    for _y: int in size.y:
        rows.append(0.0)
        counts.append(0)
    for y: int in size.y:
        var row: int = y * size.x
        for x: int in size.x:
            if mask[row + x] == 0:
                continue
            rows[y] += absf(_luma(with_water.get_pixel(x, y)) - _luma(without.get_pixel(x, y)))
            counts[y] += 1
    var wet_rows: Array[int] = []
    for y: int in size.y:
        if counts[y] > size.x / 40:
            wet_rows.append(y)
    if wet_rows.size() < 20:
        return {"shallow": 0.0, "deep": 0.0}
    var band: int = maxi(1, wet_rows.size() / 10)
    var deep: float = 0.0
    var shallow: float = 0.0
    for index: int in band:
        # Top of frame is far away, so it is the deep end.
        var far_row: int = wet_rows[index]
        var near_row: int = wet_rows[wet_rows.size() - 1 - index]
        deep += rows[far_row] / float(counts[far_row])
        shallow += rows[near_row] / float(counts[near_row])
    return {"shallow": shallow / float(band), "deep": deep / float(band)}


func _luma(colour: Color) -> float:
    return colour.r * 0.2126 + colour.g * 0.7152 + colour.b * 0.0722
