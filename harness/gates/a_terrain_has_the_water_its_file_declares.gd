extends GateBase
## A terrain that declares water gets water, at the height its own file states, and one that
## declares none gets none.
##
## **Two lines nothing has ever read.** `Water=1` and `WaterLine=254` are the whole of what a
## `.terrn2` says about its sea. Both have been parsed and ignored since the parser was written,
## so Port Starling — a port, spawning four metres above its own waterline — has been a dry pit,
## and `simple2_w` declares water at 100 m and renders dry. Reported from a window as "no water
## on the map".
##
## **The oracle is the `.terrn2` text, read here with no help from the parser under test.** A
## gate that asks the reader what the waterline is can only ever agree with it. Two lines of
## string handling cost nothing and make the expectation the file's own.
##
## **And it has to be drawn, not merely built.** A node at the right height proves the arithmetic
## and nothing about the renderer: a plane with a broken shader, a zero alpha, or a cull mode that
## faces it away is a node at exactly the right height drawing nothing at all. So one terrain's
## sea is photographed from above it, with and without the surface in the scene, and the frame
## has to change.
##
## The terrains that declare no water are the negative side, and they are not decoration: the
## first thing a wrong `Water` flag does is put a sea on every map in the library.

## How close the built surface has to sit to the height the file states.
const TOLERANCE_M: float = 0.001
## How much of the frame the sea has to change when it is put into the scene. Low, because what
## is being proved is that it draws at all; the shoreline's look is a person's judgement.
const MIN_DRAWN: float = 0.05
const CONVERGE: int = 6
## How far a pixel has to move, summed over the channels, to be the sea rather than the exposure
## drifting between two captures of the same scene.
const CHANGED: float = 0.1
const LISTED: int = 6
## The wave phase every capture here is taken at. Any fixed number would do; what matters is that
## it is fixed.
const FROZEN_WAVE_PHASE: float = 3.0


static func meta() -> Dictionary:
    return {
        "name": "a_terrain_has_the_water_its_file_declares",
        "proves": (
            "every terrain whose .terrn2 declares water is built with a surface at the waterline"
            + " that file states and covering its map, every terrain declaring none has none,"
            + " and the surface is visible when photographed from above it"
        ),
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "the surface within 1 mm of the declared waterline, reaching past the map, and"
            + " changing at least 5%% of a frame taken from above it"
        ),
        "why": (
            "Water and WaterLine have been parsed and ignored since the parser was written, so a"
            + " port spawning four metres above its own waterline has been a dry pit. A node at"
            + " the right height proves the arithmetic and nothing about the renderer, which is"
            + " why one of them is also photographed."
        ),
        "budget_s": 180.0,
        "needs_gpu": true,
        "milestone": "M8",
    }


func run(harness: Node) -> Dictionary:
    var wet: int = 0
    var dry: int = 0
    var problems: PackedStringArray = PackedStringArray()
    var photographed: String = ""
    var share: float = 0.0
    for summary: Dictionary in RorTerrainLibrary.summaries():
        if (summary["error"] as String) != "":
            continue
        var loaded: Dictionary = RorTerrainLibrary.load_named(summary["name"] as String)
        if (loaded.get("error", "") as String) != "":
            continue
        var terrain: RorTerrain = loaded["terrain"] as RorTerrain
        var declared: Dictionary = _declared(terrain)
        if declared.is_empty():
            continue
        # Held still: this gate photographs the sea, and a surface that moves with the wall clock
        # is a different surface in every frame. See `a_sea_moves_and_a_measurement_can_stop_it`.
        var built: Node3D = RorWater.build(terrain, FROZEN_WAVE_PHASE)
        var surface: MeshInstance3D = built.get_node_or_null(^"Surface") as MeshInstance3D
        if not (declared["water"] as bool):
            dry += 1
            if surface != null:
                problems.append(
                    "%s declares no water and was given a surface" % summary["name"]
                )
            built.queue_free()
            continue
        wet += 1
        var fault: String = _check(summary["name"] as String, terrain, declared, surface)
        if fault != "":
            problems.append(fault)
            built.queue_free()
            continue
        if photographed == "":
            photographed = summary["name"] as String
            var shown: Dictionary = await _photograph(harness, terrain, built)
            if (shown["error"] as String) != "":
                return fail(shown["error"] as String)
            share = shown["share"] as float
            if share < MIN_DRAWN:
                problems.append(
                    "%s is built at %.2f m and draws %.1f%% of a frame taken from above it"
                    % [photographed, declared["line"], (shown["share"] as float) * 100.0]
                )
        built.queue_free()

    if wet == 0:
        return ok("skipped: no terrain in this checkout declares water", 0)
    if problems.size() > 0:
        return fail("; ".join(problems.slice(0, LISTED)), problems.size())
    return ok(
        "%d terrains declare water and have it at the height their files state, %d declare none"
        % [wet, dry] + " and have none; %s draws %.1f%% of a frame from above its own sea"
        % [photographed, share * 100.0],
        wet
    )


## What one terrain's built surface gets wrong, or "".
func _check(
    name: String, terrain: RorTerrain, declared: Dictionary, surface: MeshInstance3D
) -> String:
    if surface == null:
        return "%s declares water at %.2f m and was given none" % [name, declared["line"]]
    if absf(surface.position.y - (declared["line"] as float)) > TOLERANCE_M:
        return "%s declares its waterline at %.2f m and the surface sits at %.2f m" % [
            name, declared["line"], surface.position.y
        ]
    # Past the map, not up to it: an island's sea meets the horizon, and a sea that stops at the
    # terrain's edge is a visible square of nothing.
    var across: float = RorWater.width_of(terrain)
    var span: Vector2 = (surface.mesh as PlaneMesh).size
    if span.x < across or span.y < across:
        return "%s is %.0f m across and its sea is %.0f by %.0f" % [
            name, across, span.x, span.y
        ]
    return ""


## One terrain's sea, from a camera above it, with and without the surface. Returns
## `{"error", "share"}`.
func _photograph(harness: Node, terrain: RorTerrain, built: Node3D) -> Dictionary:
    var error: String = harness.setup_for("hero_3q")
    if error != "":
        return {"error": error, "share": 0.0}
    harness.world.add_child(built)
    var across: float = RorWater.width_of(terrain)
    var line: float = RorWater.height_at(terrain)
    # Standing on the sea looking along it, from a height that puts the horizon in frame. Not
    # straight down: a camera pointing at a flat plane from directly above cannot be told from
    # one pointing at nothing, and the up vector is degenerate there.
    var at: Vector3 = Vector3(across * 0.5, line + across * 0.05, across * 0.5)
    harness.camera.look_at_from_position(
        at, at + Vector3(1.0, -0.25, 0.0), Vector3.UP
    )
    var surface: Node3D = built.get_node(^"Surface") as Node3D
    surface.visible = false
    var dry: Dictionary = await harness.capture_shot("water/dry", "static", CONVERGE)
    surface.visible = true
    if (dry["error"] as String) != "":
        return {"error": dry["error"], "share": 0.0}
    var wet: Dictionary = await harness.capture_shot("water/wet", "static", CONVERGE)
    if (wet["error"] as String) != "":
        return {"error": wet["error"], "share": 0.0}
    harness.world.remove_child(built)
    return {"error": "", "share": _changed(dry["png"] as String, wet["png"] as String)}


## What share of a frame the sea changed, counting only pixels that moved further than the
## renderer moves them on its own.
##
## **The first version of this counted any difference at all and read 94% on two photographs of
## an empty sky.** Exposure drifts a little between two captures of the same scene, every pixel
## of a smooth sky gradient moves with it, and a threshold of a fiftieth of a channel calls that
## a sea. It passed a shader that had failed to compile and was drawing nothing. A tenth of a
## channel summed over three is larger than any drift measured here and far smaller than water
## against sky.
func _changed(before: String, after: String) -> float:
    var dry: Image = Image.load_from_file(before)
    var wet: Image = Image.load_from_file(after)
    if dry == null or wet == null or dry.get_size() != wet.get_size():
        return 0.0
    var moved: int = 0
    var total: int = 0
    for y: int in range(0, dry.get_height(), 4):
        for x: int in range(0, dry.get_width(), 4):
            total += 1
            var a: Color = dry.get_pixel(x, y)
            var b: Color = wet.get_pixel(x, y)
            if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > CHANGED:
                moved += 1
    return 0.0 if total == 0 else float(moved) / float(total)


## What a terrain's own `.terrn2` says about water, read here rather than asked of the parser.
func _declared(terrain: RorTerrain) -> Dictionary:
    for file: String in DirAccess.get_files_at(terrain.directory):
        if file.get_extension().to_lower() != "terrn2":
            continue
        if terrain.name != "" and not _names(terrain.directory.path_join(file), terrain.name):
            continue
        var text: String = FileAccess.get_file_as_string(terrain.directory.path_join(file))
        var water: bool = false
        var line: float = 0.0
        for raw: String in text.split("\n"):
            var key: String = raw.get_slice("=", 0).strip_edges().to_lower()
            var value: String = raw.get_slice("=", 1).strip_edges()
            if key == "water":
                water = value != "0" and value.to_lower() != "false"
            elif key == "waterline":
                line = value.to_float()
        return {"water": water, "line": line}
    return {}


## Whether a `.terrn2` is the one this terrain was loaded from, by the name inside it.
func _names(path: String, wanted: String) -> bool:
    for raw: String in FileAccess.get_file_as_string(path).split("\n"):
        if raw.get_slice("=", 0).strip_edges().to_lower() == "name":
            return raw.get_slice("=", 1).strip_edges() == wanted
    return false
