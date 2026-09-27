extends GateBase
## The park's ground is drawn as a measured grid, the test areas are not, and the lines are sharp.
##
## A workshop floor should say how far away something is and how fast you are crossing it, and it
## should say plainly that it is not pretending to be a place. The test areas are the exception:
## the road, the surface patches let into it and the skid pad are drawn as what they are, because
## the thing being tested is the thing that should be coloured.
##
## The first version of this gate proved the grid was in the terrain's colour map and reached a
## pixel, and that was not enough: a session reported the result as "too blurry". A colour map is
## one texel per metre and is filtered and mipmapped, so a 0.45 m line stored in it is a third of a
## texel and arrives as a smear. Sharpness is therefore a measurement here rather than a hope —
## floor colour from the colour map, lines from `world/park_grid.gd`, and the rendered line edge
## measured in pixels.
##
## Three claims, in the order that isolates a fault:
##   - the floor is one flat grey off the test areas, and the test areas carry their own surface;
##   - the grid overlay's mask says grid on open ground and not on a test area;
##   - and on the screen the lines are at the stated spacing, with an edge only a pixel or two wide.

const PRESET: String = "hero_3q"
const CONVERGE: int = 3
## Looking straight down from here, so the grid fills the frame without perspective closing it up.
const CAMERA_HEIGHT_M: float = 22.0
## Where to look: off the road, over open ground, and half a grid square off a line in z, so the
## scanned row crosses lines rather than running along one.
const OVER: Vector2 = Vector2(-60.0, 62.5)
## How far the sampled row may be from the projected centre of the view, in pixels.
const ROW_SLACK_PX: int = 2
## A line has to be this much brighter than the floor between lines.
const MIN_RENDERED_CONTRAST: float = 0.04
## And its edge has to be this narrow. Measured between the quarter and three-quarter levels of
## one line's own rise, which is about 26 px wide at this camera height.
##
## This is the blur bound, and it is the whole point of the gate. Measured: 2.0 px with the
## procedural overlay against 50 px for the same grid baked into the colour map, whose lines also
## reached only 0.086 of contrast against 0.343 here. So a change back to a painted grid fails
## here rather than being reported by a person.
const MAX_EDGE_PX: float = 4.0
## How far the measured line pitch may sit from the pitch the spacing and the camera imply.
const PITCH_TOLERANCE: float = 0.12


static func meta() -> Dictionary:
    return {
        "name": "park_ground_is_a_dev_grid",
        "proves": "the test park's open ground is drawn as a grid at the stated spacing with a sharp line edge, and the test areas keep their own surfaces",
        # the floor is in the terrain's colour map, so the terrain has to build and render first.
        "builds_on": ["smoke", "terrain3d_available"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "lines at %.0f m spacing within %.0f%% of what the camera implies, at least %.2f of"
            % [ParkCfg.GRID_SPACING_M, PITCH_TOLERANCE * 100.0, MIN_RENDERED_CONTRAST]
            + " rendered contrast, an edge under %.0f px, and no grid on the road or the skid pad"
            % MAX_EDGE_PX
        ),
        "why": (
            "a grid is the fastest way to see speed and distance on a flat test site, and the"
            + " reason to have one rather than ground. Painting it into the terrain's colour map"
            + " put it on the screen and a session still rejected it — one texel per metre,"
            + " filtered, turns a line into a smear. So the line's edge is measured in pixels,"
            + " which is the thing that was actually wrong."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var flat: Dictionary = _floor_is_flat()
    if (flat["error"] as String) != "":
        return fail(flat["error"] as String, flat["value"] as float)
    var masked: String = _mask_covers_the_test_areas()
    if masked != "":
        return fail(masked)

    if not ClassDB.class_exists("Terrain3D"):
        return ok("the floor and the mask are right; skipped the render: Terrain3D is absent", 0.0)
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)
    var terrain: Node3D = ValleyTerrain.create()
    harness.world.add_child(terrain)
    await harness.advance_frames(2, "static", "terrain")
    var built: String = ValleyTerrain.populate(terrain, ParkShape)
    if built != "":
        return fail(built)
    harness.world.add_child(ParkGrid.build())
    var ground: MeshInstance3D = harness.world.get_node_or_null(^"Ground") as MeshInstance3D
    if ground != null:
        ground.visible = false
    var centre: Vector3 = Vector3(OVER.x, 0.0, OVER.y)
    harness.camera.look_at_from_position(
        centre + Vector3(0.0, CAMERA_HEIGHT_M, 0.0), centre, Vector3.FORWARD
    )
    await harness.advance_frames(1, "static", "grid")
    # What the camera says a grid square should measure on the screen. Taken from the camera
    # itself rather than from its field of view, so the expectation cannot drift from the shot.
    var here: Vector2 = harness.camera.unproject_position(centre)
    var one_square: Vector2 = harness.camera.unproject_position(
        centre + Vector3(ParkCfg.GRID_SPACING_M, 0.0, 0.0)
    )
    var wanted_pitch: float = here.distance_to(one_square)

    var shot: Dictionary = await harness.capture_shot("park_grid", "static", CONVERGE)
    if (shot["error"] as String) != "":
        return fail(shot["error"] as String)
    var image: Image = Image.load_from_file(shot["png"] as String)
    if image == null:
        return fail("the capture at %s could not be read" % shot["png"])
    return _measure(image, here, wanted_pitch, shot["png"] as String)


## The colour map's side of it: one flat grey off the test areas, and each test area its own
## surface. Flat is the claim now — the lines used to be baked here and that is what was blurry.
func _floor_is_flat() -> Dictionary:
    var step: float = ParkCfg.GRID_SPACING_M / 7.0
    for index: int in 200:
        var x: float = OVER.x + float(index) * step
        var tint: Color = ParkShape.tint_at(x, OVER.y)
        var off: float = absf(_luma(tint) - _luma(ParkCfg.GRID_BASE))
        if off > 0.002:
            return {
                "error": (
                    "open ground at %.1f m is drawn %v where the grid's floor is %v: the lines are"
                    % [x, tint, ParkCfg.GRID_BASE]
                    + " back in the colour map, which is where they smear"
                ),
                "value": off,
            }
    for place: Dictionary in _test_places():
        var at: Vector2 = place["at"] as Vector2
        var drawn: Color = ParkShape.tint_at(at.x, at.y)
        var wanted: Color = TerrainCfg.SURFACE_COLOURS.get(
            place["surface"] as String, Color.GRAY
        ) as Color
        if absf(_luma(drawn) - _luma(wanted)) > 0.02:
            return {
                "error": (
                    "%s at %v is drawn %v where its %s surface is %v: the floor is covering a test"
                    % [place["name"], at, drawn, place["surface"], wanted] + " area"
                ),
                "value": _luma(drawn) - _luma(wanted),
            }
    return {"error": "", "value": 0.0}


## The overlay's side of it: the mask lets the grid onto open ground and keeps it off a test area.
func _mask_covers_the_test_areas() -> String:
    var mask: Image = ParkGrid.mask_image()
    for place: Dictionary in _test_places():
        var at: Vector2 = place["at"] as Vector2
        if _mask_at(mask, at) > 0.5:
            return (
                "the grid's mask is open over %s at %v: the overlay draws lines across a test area"
                % [place["name"], at]
            )
    for at: Vector2 in [OVER, Vector2(200.0, 200.0), Vector2(-300.0, -120.0)]:
        if _mask_at(mask, at) < 0.5:
            return "the grid's mask is closed over open ground at %v: there is no grid there" % at
    return ""


## The places that are drawn as themselves rather than as grid.
func _test_places() -> Array[Dictionary]:
    return [
        {"name": "the road", "at": Vector2(-40.0, 0.0), "surface": ParkCfg.ROAD_SURFACE},
        {"name": "an ice patch", "at": Vector2(ParkCfg.PATCH_FIRST_X_M + 85.0, 0.0),
            "surface": "ice"},
        {"name": "the skid pad", "at": ParkCfg.SKID_PAD_CENTRE,
            "surface": ParkCfg.SKID_PAD_SURFACE},
    ]


func _mask_at(mask: Image, at: Vector2) -> float:
    var x: int = clampi(
        int(round((at.x - TerrainCfg.ORIGIN.x) / TerrainCfg.VERTEX_SPACING)),
        0, mask.get_width() - 1
    )
    var z: int = clampi(
        int(round((at.y - TerrainCfg.ORIGIN.z) / TerrainCfg.VERTEX_SPACING)),
        0, mask.get_height() - 1
    )
    return mask.get_pixel(x, z).r


## What the rendered frame says: the spacing, the contrast, and how wide a line's edge is.
func _measure(image: Image, here: Vector2, wanted_pitch: float, png: String) -> Dictionary:
    var size: Vector2i = image.get_size()
    var row: int = clampi(int(round(here.y)), ROW_SLACK_PX, size.y - 1 - ROW_SLACK_PX)
    var first: int = int(float(size.x) * 0.2)
    var last: int = int(float(size.x) * 0.8)
    var profile: PackedFloat32Array = PackedFloat32Array()
    for x: int in range(first, last):
        profile.append(_luma(image.get_pixel(x, row)))
    var floor_level: float = _percentile(profile, 0.2)
    var peak: float = _percentile(profile, 0.98)
    var contrast: float = peak - floor_level
    if contrast < MIN_RENDERED_CONTRAST:
        return fail(
            "the ground renders with %.4f between its lines and its floor, under %.2f: there is no"
            % [contrast, MIN_RENDERED_CONTRAST] + " grid on the screen. See %s" % png,
            contrast
        )
    var crossings: PackedInt32Array = _rising(profile, floor_level + contrast * 0.5)
    if crossings.size() < 3:
        return fail(
            "scanning %d px across the ground found %d lines: the grid is not periodic on the"
            % [profile.size(), crossings.size()] + " screen. See %s" % png,
            crossings.size()
        )
    var pitch: float = float(crossings[crossings.size() - 1] - crossings[0]) / float(
        crossings.size() - 1
    )
    if absf(pitch - wanted_pitch) > wanted_pitch * PITCH_TOLERANCE:
        return fail(
            "the lines are %.1f px apart where %.0f m at this camera is %.1f px: the grid is drawn"
            % [pitch, ParkCfg.GRID_SPACING_M, wanted_pitch]
            + " at the wrong spacing. See %s" % png,
            pitch - wanted_pitch
        )
    var edge: float = _edge_width(profile, crossings, int(round(pitch)))
    if edge > MAX_EDGE_PX:
        return fail(
            "a line's edge takes %.1f px to rise, over %.0f: the grid is blurred, which is what a"
            % [edge, MAX_EDGE_PX]
            + " line stored in the terrain's colour map does. See %s" % png,
            edge
        )
    return ok(
        "lines %.1f px apart against %.1f expected, %.3f of contrast, and an edge %.1f px wide"
        % [pitch, wanted_pitch, contrast, edge],
        edge
    )


## Where the profile rises through a level, which is once per line.
func _rising(profile: PackedFloat32Array, level: float) -> PackedInt32Array:
    var out: PackedInt32Array = PackedInt32Array()
    for index: int in range(1, profile.size()):
        if profile[index - 1] < level and profile[index] >= level:
            out.append(index)
    return out


## The median width of a line's rise, measured between the quarter and three-quarter levels of
## that line's own floor and peak. Per line rather than globally, because a major line is both
## wider and brighter than a minor one and a single pair of levels would not fit both.
func _edge_width(profile: PackedFloat32Array, crossings: PackedInt32Array, pitch: int) -> float:
    var widths: Array[float] = []
    var window: int = maxi(pitch / 2, 2)
    for at: int in crossings:
        var low: float = INF
        var high: float = -INF
        for index: int in range(maxi(at - window, 0), mini(at + window, profile.size())):
            low = minf(low, profile[index])
            high = maxf(high, profile[index])
        if high - low < MIN_RENDERED_CONTRAST * 0.5:
            continue
        var quarter: float = low + (high - low) * 0.25
        var three_quarters: float = low + (high - low) * 0.75
        var up: int = at
        while up < profile.size() - 1 and profile[up] < three_quarters:
            up += 1
        var down: int = at
        while down > 0 and profile[down] > quarter:
            down -= 1
        widths.append(float(up - down))
    if widths.is_empty():
        return INF
    widths.sort()
    return widths[widths.size() / 2]


func _percentile(values: PackedFloat32Array, fraction: float) -> float:
    var sorted: PackedFloat32Array = values.duplicate()
    sorted.sort()
    var at: int = clampi(int(float(sorted.size() - 1) * fraction), 0, sorted.size() - 1)
    return sorted[at]


func _luma(colour: Color) -> float:
    return colour.r * 0.2126 + colour.g * 0.7152 + colour.b * 0.0722
