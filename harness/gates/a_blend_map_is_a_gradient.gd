extends GateBase
## A terrain's splat map is read as a gradient, not as a grid of blocks.
##
## **Ogre hands a blend map to the GPU as a texture and the GPU filters it.** Read with the
## nearest pixel instead, the map's own resolution becomes visible on the ground: Starling
## Island's is 64 by 64 over 3000 m — **46.9 m a pixel** — so every boundary the author painted
## came out as a hard staircase edge. The hillsides read as terraces, dark bands following the
## contours, which looks like broken lighting or a broken heightmap and is neither.
##
## **The oracle is arithmetic over the terrain's own two numbers.** Between neighbouring lattice
## vertices the ground moves `spacing` metres, and between neighbouring blend-map pixels it moves
## `world / width` metres. A filtered read cannot change coverage faster than the map itself does,
## so across one vertex step coverage may move at most
##
##     the largest step between two neighbouring pixels  x  spacing / metres per pixel
##
## which on Starling is one sixteenth of a pixel's own step. A nearest read moves the whole step
## in one vertex, sixteen times that, every time a vertex crosses a pixel boundary. Both figures
## come out of the terrain's files; neither is a number this project chose.
##
## Sampled along the axes rather than diagonally, so the bound is exact rather than a diagonal
## allowance somebody picked.
##
## **What is measured is the map as it is read, not the coverage derived from it.** Ogre composites
## layers by multiplying each one's weight through what the layers above it left, so a terrain with
## four layers can move one layer's share faster than any single channel moved — La Paz does, and
## a first draft of this gate failed it for arithmetic rather than for blockiness. The smoothness
## that matters is the source's; everything downstream inherits it.

## How many vertex steps to walk in each direction. Enough to cross many pixel boundaries.
const STEPS: int = 400
## Float slack on a comparison of two sums of products.
const EPSILON: float = 1e-4
## Below this there is no map to judge.
const MIN_PIXELS: int = 4


## **It builds on nothing.** `builds_on` means "running this exercises that, at least as
## hard", and the graph stops running what it implies — so an edge that only records which
## gate came first is an edge that silently retires a gate. This one reads a splat map and checks none of a terrain's own figures.


static func meta() -> Dictionary:
    return {
        "name": "a_blend_map_is_a_gradient",
        "proves": "a terrain's splat map is read smoothly, so what the ground is painted with never moves faster between two lattice vertices than the map itself moves between two pixels",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": "the map reads at most (its own largest pixel step) x (vertex spacing / metres per pixel) different across one vertex",
        "why": (
            "Starling Island's blend map is 64 by 64 over 3000 m, 46.9 m a pixel. Read with the"
            + " nearest pixel its resolution is the ground: every painted boundary becomes a"
            + " staircase, and the hillsides read as terraces that look like broken lighting."
        ),
        "budget_s": 120.0,
        "needs_gpu": false,
        "milestone": "C2",
    }


func run(_harness: Node) -> Dictionary:
    var checked: int = 0
    var worst_ratio: float = 0.0
    var worst: String = ""
    var problems: PackedStringArray = PackedStringArray()
    for summary: Dictionary in RorTerrainLibrary.summaries():
        if (summary["error"] as String) != "":
            continue
        var loaded: Dictionary = RorTerrainLibrary.load_named(summary["name"] as String)
        if (loaded.get("error", "") as String) != "":
            continue
        var terrain: RorTerrain = loaded["terrain"] as RorTerrain
        var image: Image = terrain.blend_image()
        if image == null or image.get_width() < MIN_PIXELS:
            continue
        checked += 1
        var grid: Dictionary = terrain.lattice()
        var spacing: float = grid["spacing"] as float
        var metres_per_pixel: float = (
            (terrain.geometry["world_x"] as float) / float(image.get_width())
        )
        # What the map itself does between two neighbouring pixels, at its worst.
        var pixel_step: float = _largest_pixel_step(image)
        if pixel_step <= 0.0:
            continue
        var allowed: float = pixel_step * (spacing / metres_per_pixel) + EPSILON
        var measured: float = _largest_read_step(terrain, image, spacing)
        var ratio: float = measured / maxf(allowed, EPSILON)
        if ratio > worst_ratio:
            worst_ratio = ratio
            worst = "%s: %.4f against %.4f allowed" % [summary["name"], measured, allowed]
        if measured > allowed:
            problems.append(
                "%s: the map reads %.4f different across one %.2f m step, over the %.4f its own"
                % [summary["name"], measured, spacing, allowed]
                + " %.1f m pixels allow" % metres_per_pixel
            )

    if checked == 0:
        return ok("skipped: no terrain in this checkout ships a blend map", 0)
    if problems.size() > 0:
        return fail(
            "%d of %d terrains read their splat map as blocks: %s"
            % [problems.size(), checked, "; ".join(problems)],
            problems.size()
        )
    return ok(
        "%d terrains with a blend map, worst %s" % [checked, worst],
        worst_ratio
    )


## The largest difference between two neighbouring pixels of the map, over any channel. Read from
## the image, which is the thing the ground is supposed to follow.
func _largest_pixel_step(image: Image) -> float:
    var worst: float = 0.0
    for z: int in image.get_height():
        for x: int in image.get_width():
            var here: Color = image.get_pixel(x, z)
            if x + 1 < image.get_width():
                worst = maxf(worst, _apart(here, image.get_pixel(x + 1, z)))
            if z + 1 < image.get_height():
                worst = maxf(worst, _apart(here, image.get_pixel(x, z + 1)))
    return worst


## The largest change the map reads between two neighbouring lattice vertices, walked along both
## axes across the map.
func _largest_read_step(terrain: RorTerrain, image: Image, spacing: float) -> float:
    var world: Vector2 = Vector2(
        terrain.geometry["world_x"] as float, terrain.geometry["world_z"] as float
    )
    var worst: float = 0.0
    for axis: int in 2:
        var previous: Color = Color(0.0, 0.0, 0.0, 0.0)
        for step: int in STEPS:
            var along: float = float(step) * spacing
            var at: Vector2 = (
                Vector2(along, world.y * 0.5) if axis == 0 else Vector2(world.x * 0.5, along)
            )
            var here: Color = RorTerrainSkin.blend_at(image, at.x, at.y, world)
            if step > 0:
                worst = maxf(worst, _apart(previous, here))
            previous = here
    return worst


## How far apart two pixels are, over whichever channel moved most.
func _apart(a: Color, b: Color) -> float:
    return maxf(
        maxf(absf(a.r - b.r), absf(a.g - b.g)),
        maxf(absf(a.b - b.b), absf(a.a - b.a))
    )
