extends GateBase
## Photographs a shipped Rigs of Rods terrain from its own spawn and its own landmarks.
##
## `ror_terrain_is_drivable` proves the terrain is there and holds a vehicle up. It does not say
## whether it looks like the place its author built, and this project's rule is that a session
## looks at pictures rather than at claims. So this produces the sheet — the spawn, the highest
## ground, the lowest, and the middle of the map — and makes the same weak claim of every frame
## that the park's sheet does: there is ground in it, it is not black, it is not all sky.
##
## The landmarks are found in the heightmap rather than written down, because the terrain's own
## layout is not this project's to name: the highest point of La Paz is wherever La Paz's author
## put it, and a view of it is a view of their terrain rather than of a guess about it.

const TERRAIN_DIR: String = "assets/terrains/lapaz2"
const CONVERGE: int = 4
## How coarsely the heightmap is searched for its landmarks. Every 32nd cell of 2048 is a sample
## every 62 m, which finds a hill rather than a boulder — which is what a camera wants.
const LANDMARK_STRIDE: int = 32
## How far back and how far up a landmark is viewed from.
const STAND_BACK_M: float = 70.0
const STAND_UP_M: float = 28.0
## And how close a view of a single prop stands.
const CLOSE_BACK_M: float = 9.0
const CLOSE_UP_M: float = 4.0
## A frame this dark is a camera inside the terrain or a scene that failed to light.
const MIN_LUMA: float = 0.02
## And this much of the frame has to be something other than sky.
const MIN_GROUND_FRACTION: float = 0.12
const SKY_LUMA: float = 0.35


static func meta() -> Dictionary:
    return {
        "name": "ror_terrain_photoset",
        "proves": "a shipped Rigs of Rods terrain renders from its own spawn, one of its own props, and its high, low and middle ground, and the set is captured for a session",
        # the terrain has to import and hold a vehicle before its pictures mean anything.
        "builds_on": ["ror_terrain_is_drivable"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "5 views, each brighter than %.2f luma with at least %.0f%% of the frame not sky"
            % [MIN_LUMA, MIN_GROUND_FRACTION * 100.0]
        ),
        "why": (
            "a terrain that imports and holds a vehicle up can still be drawn wrong — the colour"
            + " map sideways, the splat weights inverted, the whole map one flat tint. The sheet"
            + " is for a person to look at; the bound is so that a terrain drawn as nothing fails"
            + " here rather than in a session."
        ),
        "budget_s": 240.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var directory: String = SourceScan.repo_root().path_join(TERRAIN_DIR)
    if not DirAccess.dir_exists_absolute(directory):
        return ok("skipped: no terrain at %s" % TERRAIN_DIR, 0)
    if not ClassDB.class_exists("Terrain3D"):
        return ok("skipped: Terrain3D is not installed. Run tools/build_terrain3d.sh", 0)
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
    var built: String = harness.terrain.populate(terrain, terrain_data)
    if built != "":
        return fail(built)
    var ground: MeshInstance3D = harness.world.get_node_or_null(^"Ground") as MeshInstance3D
    if ground != null:
        ground.visible = false
    # The terrain's own props and vegetation, so the sheet shows the place rather than its
    # heightmap.
    harness.world.add_child(RorObjects.build(terrain_data))
    var vegetation: RorVegetation = RorVegetation.new()
    if vegetation.setup(terrain_data) == "":
        harness.world.add_child(vegetation)
    else:
        vegetation.free()
        vegetation = null

    var views: Array[Dictionary] = _views(terrain_data)
    var reported: PackedStringArray = PackedStringArray()
    var darkest: float = INF
    for index: int in views.size():
        var view: Dictionary = views[index]
        var at: Vector3 = view["at"] as Vector3
        if vegetation != null:
            vegetation.focus_on(at)
            vegetation.fill()
        harness.camera.look_at_from_position(
            _stand(terrain_data, at, view.get("close", false) as bool), at, Vector3.UP
        )
        var shot: Dictionary = await harness.capture_shot(
            "ror_terrain/%d_%s" % [index + 1, view["name"]], "static", CONVERGE
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
                % [index + 1, view["name"], luma, shot["png"]],
                luma
            )
        if ground_fraction < MIN_GROUND_FRACTION:
            return fail(
                "view %d (%s) is %.0f%% sky: the camera is not looking at the terrain. See %s"
                % [index + 1, view["name"], (1.0 - ground_fraction) * 100.0, shot["png"]],
                ground_fraction
            )
        reported.append("%d %s %.0f%% ground" % [
            index + 1, view["name"], ground_fraction * 100.0])
    return ok(
        "%s: %d views captured, darkest %.3f luma: " % [terrain_data.name, views.size(), darkest]
        + ", ".join(reported),
        darkest
    )


## Where a camera stands to look at a landmark: back and up, kept inside the map, and above the
## ground it happens to be standing over. A fixed offset put the camera inside a hillside on the
## first try and the frame came back black.
func _stand(terrain_data: RorTerrain, at: Vector3, close: bool = false) -> Vector3:
    var grid: Dictionary = terrain_data.lattice()
    var span: float = float((grid["size"] as int) - 1) * (grid["spacing"] as float)
    var back: float = CLOSE_BACK_M if close else STAND_BACK_M
    var up: float = CLOSE_UP_M if close else STAND_UP_M
    var eye: Vector3 = at + Vector3(-back, up, -back)
    eye.x = clampf(eye.x, 2.0, span - 2.0)
    eye.z = clampf(eye.z, 2.0, span - 2.0)
    eye.y = maxf(eye.y, terrain_data.height_at_world(eye.x, eye.z) + up)
    return eye


## Where to stand: the terrain's own spawn, its highest and lowest ground, and the middle of it.
func _views(terrain_data: RorTerrain) -> Array[Dictionary]:
    var grid: Dictionary = terrain_data.lattice()
    var size: int = grid["size"] as int
    var spacing: float = grid["spacing"] as float
    var highest: Vector3 = Vector3.ZERO
    var lowest: Vector3 = Vector3(0.0, INF, 0.0)
    for z: int in range(0, size, LANDMARK_STRIDE):
        for x: int in range(0, size, LANDMARK_STRIDE):
            var height: float = terrain_data.height_at(x, z)
            var at: Vector3 = Vector3(float(x) * spacing, height, float(z) * spacing)
            if height > highest.y:
                highest = at
            if height < lowest.y:
                lowest = at
    var start: Vector3 = terrain_data.start_position()
    var middle_x: float = float(size / 2) * spacing
    var middle_z: float = float(size / 2) * spacing
    # And one of the terrain's own props, close enough to see what it is: an object chain that
    # resolves to geometry can still put it underground or at the wrong scale.
    # A prop rather than the map's own furniture: a horizon card and a ground skirt are placed
    # like objects and are hundreds of metres across, so a close view of one is a view of the
    # inside of it.
    var props: Array[Dictionary] = RorObjects.placements(terrain_data)
    var prop: Vector3 = start
    for placement: Dictionary in props:
        var name: String = (placement["name"] as String).to_lower()
        if name.contains("horizon") or name.contains("base") or name.contains("sky"):
            continue
        prop = placement["position"] as Vector3
        break
    return [
        {"name": "object", "at": prop, "close": true},
        {"name": "spawn", "at": Vector3(
            start.x, terrain_data.height_at_world(start.x, start.z) + 1.0, start.z)},
        {"name": "highest", "at": highest},
        {"name": "lowest", "at": lowest},
        {"name": "middle", "at": Vector3(
            middle_x, terrain_data.height_at_world(middle_x, middle_z) + 1.0, middle_z)},
    ]


## How bright a frame is, and how much of it is not sky.
func _measure(image: Image) -> Dictionary:
    var size: Vector2i = image.get_size()
    var total: float = 0.0
    var ground: int = 0
    var counted: int = 0
    for y: int in range(0, size.y, 4):
        for x: int in range(0, size.x, 4):
            var colour: Color = image.get_pixel(x, y)
            var luma: float = colour.r * 0.2126 + colour.g * 0.7152 + colour.b * 0.0722
            total += luma
            if luma < SKY_LUMA or colour.b <= colour.r:
                ground += 1
            counted += 1
    return {
        "luma": total / float(maxi(counted, 1)),
        "ground": float(ground) / float(maxi(counted, 1)),
    }
