extends GateBase
## The park's ground is drawn as a measured grid, and the test areas are not.
##
## A workshop floor should say how far away something is and how fast you are crossing it, and it
## should say plainly that it is not pretending to be a place. The test areas are the exception:
## the road, the surface patches let into it and the skid pad are drawn as what they are, because
## the thing being tested is the thing that should be coloured.
##
## Two claims, and they are the same claim from both ends: the grid is a grid where it should be —
## periodic, at the spacing the config states, with a brighter line every tenth — and it is absent
## where a surface is being tested. Checked in the tint function, which is what the terrain's
## colour map is built from, and then in a rendered frame, because a colour map that never reaches
## a pixel is the fault this project has already had once.

const PRESET: String = "hero_3q"
const CONVERGE: int = 3
## Looking straight down from here, so the grid fills the frame without perspective closing it up.
const CAMERA_HEIGHT_M: float = 22.0
## Where to look: off the road, over open ground, and half a grid square off a line in z — a row
## walked along a line is a row where every sample is a line, which is how the first version of
## this gate measured a contrast of 0.024 on a grid that was plainly there.
const OVER: Vector2 = Vector2(-60.0, 62.5)
## How many samples to walk across the ground when checking the pattern.
const SAMPLES: int = 400
## A line has to be this much brighter than the floor between lines, or it is not a line.
const MIN_LINE_CONTRAST: float = 0.08
## And the rendered ground has to carry that structure. Measured between pixels this far apart
## rather than adjacent ones: the terrain's colour map is coarser than the heightmap and its lines
## arrive soft, so neighbouring pixels differ by almost nothing while the pattern is plainly there
## a few pixels away.
const CONTRAST_STRIDE_PX: int = 8
const MIN_RENDERED_CONTRAST: float = 0.004


static func meta() -> Dictionary:
    return {
        "name": "park_ground_is_a_dev_grid",
        "proves": "the test park's open ground is drawn as a grid at the stated spacing, the test areas keep their own surfaces, and the grid reaches the screen",
        # the grid is in the terrain's colour map, so the terrain has to build and render first.
        "builds_on": ["smoke", "terrain3d_available"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "lines every %.0f m with at least %.2f of contrast against the floor between them,"
            % [ParkCfg.GRID_SPACING_M, MIN_LINE_CONTRAST]
            + " no grid on the road or the skid pad, and %.3f rendered local contrast"
            % MIN_RENDERED_CONTRAST
        ),
        "why": (
            "a grid is the fastest way to see speed and distance on a flat test site, and the"
            + " reason to have one rather than ground. It is also exactly the kind of thing that"
            + " can be correct in the data and never reach a pixel — which has happened here"
            + " before, with the surface lanes and a debug pattern drawn over them."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    # The pattern itself, in the function the colour map is built from.
    var floor_tint: float = 0.0
    var line_tint: float = 0.0
    var floors: int = 0
    var lines: int = 0
    var step: float = ParkCfg.GRID_SPACING_M / 16.0
    for index: int in SAMPLES:
        var x: float = OVER.x + float(index) * step
        var tint: Color = ParkShape.tint_at(x, OVER.y)
        var luma: float = _luma(tint)
        # Which it should be, from the same arithmetic the grid is drawn with.
        var along: float = absf(
            fposmod(x + ParkCfg.GRID_SPACING_M * 0.5, ParkCfg.GRID_SPACING_M)
            - ParkCfg.GRID_SPACING_M * 0.5
        )
        if along <= ParkCfg.GRID_LINE_M * 0.5:
            line_tint += luma
            lines += 1
        else:
            floor_tint += luma
            floors += 1
    if lines == 0 or floors == 0:
        return fail(
            "walking %.0f m of ground found %d line samples and %d floor samples: the spacing and"
            % [float(SAMPLES) * step, lines, floors] + " the sampling disagree",
            lines
        )
    var contrast: float = line_tint / float(lines) - floor_tint / float(floors)
    if contrast < MIN_LINE_CONTRAST:
        return fail(
            "the grid's lines are %.3f brighter than the floor between them, under %.2f: there is"
            % [contrast, MIN_LINE_CONTRAST] + " no grid",
            contrast
        )

    # And the test areas are drawn as themselves.
    for place: Dictionary in [
        {"name": "the road", "at": Vector2(-40.0, 0.0), "surface": ParkCfg.ROAD_SURFACE},
        {"name": "an ice patch", "at": Vector2(ParkCfg.PATCH_FIRST_X_M + 85.0, 0.0),
            "surface": "ice"},
        {"name": "the skid pad", "at": ParkCfg.SKID_PAD_CENTRE,
            "surface": ParkCfg.SKID_PAD_SURFACE},
    ]:
        var at: Vector2 = place["at"] as Vector2
        var drawn: Color = ParkShape.tint_at(at.x, at.y)
        var wanted: Color = TerrainCfg.SURFACE_COLOURS.get(
            place["surface"] as String, Color.GRAY
        ) as Color
        if absf(_luma(drawn) - _luma(wanted)) > 0.02:
            return fail(
                "%s at %v is drawn %v where its %s surface is %v: the grid is covering a test area"
                % [place["name"], at, drawn, place["surface"], wanted],
                _luma(drawn) - _luma(wanted)
            )

    # Then the same pattern, on the screen.
    if not ClassDB.class_exists("Terrain3D"):
        return ok("the grid is in the colour map; skipped the render: Terrain3D is not installed",
            contrast)
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)
    var terrain: Node3D = ValleyTerrain.create()
    harness.world.add_child(terrain)
    await harness.advance_frames(2, "static", "terrain")
    var built: String = ValleyTerrain.populate(terrain, ParkShape)
    if built != "":
        return fail(built)
    var ground: MeshInstance3D = harness.world.get_node_or_null(^"Ground") as MeshInstance3D
    if ground != null:
        ground.visible = false
    var centre: Vector3 = Vector3(OVER.x, 0.0, OVER.y)
    harness.camera.look_at_from_position(
        centre + Vector3(0.0, CAMERA_HEIGHT_M, 0.0), centre, Vector3.FORWARD
    )
    var shot: Dictionary = await harness.capture_shot("park_grid", "static", CONVERGE)
    if (shot["error"] as String) != "":
        return fail(shot["error"] as String)
    var image: Image = Image.load_from_file(shot["png"] as String)
    if image == null:
        return fail("the capture at %s could not be read" % shot["png"])
    var rendered: float = _local_contrast(image)
    if rendered < MIN_RENDERED_CONTRAST:
        return fail(
            "the ground renders with %.4f of local contrast, under %.3f: the grid is in the"
            % [rendered, MIN_RENDERED_CONTRAST]
            + " colour map and not on the screen. See %s" % shot["png"],
            rendered
        )
    return ok(
        "lines %.3f brighter than the floor at %.0f m spacing, the road and the skid pad drawn as"
        % [contrast, ParkCfg.GRID_SPACING_M]
        + " themselves, and %.4f of local contrast on the screen" % rendered,
        contrast
    )


func _luma(colour: Color) -> float:
    return colour.r * 0.2126 + colour.g * 0.7152 + colour.b * 0.0722


## The mean absolute difference between pixels a stride apart: flat ground is zero, a grid is not.
func _local_contrast(image: Image) -> float:
    var size: Vector2i = image.get_size()
    var total: float = 0.0
    var counted: int = 0
    for y: int in range(size.y / 4, size.y * 3 / 4, 2):
        for x: int in range(size.x / 4, size.x * 3 / 4 - CONTRAST_STRIDE_PX, 2):
            total += absf(
                _luma(image.get_pixel(x, y))
                - _luma(image.get_pixel(x + CONTRAST_STRIDE_PX, y))
            )
            counted += 1
    return total / float(maxi(counted, 1))
