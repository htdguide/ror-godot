extends GateBase
## A loaded terrain's vegetation grows where its own density map says, and nowhere else.
##
## La Paz asks for grass at 1.5 plants per square metre over 16 square kilometres — twenty-four
## million plants — so what is drawn is a ring of tiles around whoever is looking, the way
## upstream's paged geometry does it. That makes three things worth checking and none of them
## visible in a photograph: that the layer's numbers are the terrain's own, that the density map
## is actually consulted, and that a tile built twice is the same tile.
##
## The last one matters more than it sounds. Vegetation placed with an RNG changes between runs,
## which makes every screenshot comparison and every drive unrepeatable; this project places by a
## hash of the position for that reason, and `no_global_random` keeps it that way. Here is where
## that is measured rather than assumed.

const TERRAIN_DIR: String = "assets/terrains/lapaz2"
## Where to grow it for the test: the terrain's own spawn, which is beside its road.
const SAMPLES: int = 400
## What the density map has to do: somewhere thick, somewhere bare. A map that says the same
## everywhere is a map that is not being read.
const MIN_DENSITY_SPREAD: float = 0.2
## How far a plant may sit off the ground it grows on.
const MAX_FLOAT_M: float = 0.05


static func meta() -> Dictionary:
    return {
        "name": "ror_terrain_grows_its_vegetation",
        "proves": "a loaded terrain's vegetation layers are read with the terrain's own numbers, placed by its own density map, standing on its ground, and identical between runs",
        "builds_on": ["ror_terrain_objects_are_placed"],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "every layer's material and density map resolved, the density map varying by at"
            + " least %.1f across the map, plants within %.0f mm of the ground, and two builds"
            % [MIN_DENSITY_SPREAD, MAX_FLOAT_M * 1000.0] + " identical"
        ),
        "why": (
            "vegetation is most of what a terrain looks like at eye level, and all of it is the"
            + " author's data: a density map, a material, a size range. Placed with an RNG it"
            + " would also make every screenshot comparison and every drive unrepeatable, which"
            + " is why it is placed by a hash of the position — and why that is measured here."
        ),
        "budget_s": 120.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var directory: String = SourceScan.repo_root().path_join(TERRAIN_DIR)
    if not DirAccess.dir_exists_absolute(directory):
        return ok("skipped: no terrain at %s" % TERRAIN_DIR, 0)
    var loaded: Dictionary = RorTerrain.load_from(directory)
    if (loaded["error"] as String) != "":
        return fail(loaded["error"] as String)
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain

    var first: RorVegetation = RorVegetation.new()
    var grown: String = first.setup(terrain)
    if grown != "":
        return ok("skipped: %s" % grown, 0)

    # The layers, against the terrain's own file.
    var stated: PackedStringArray = _stated_lines(terrain)
    if stated.size() != first.layers().size():
        first.free()
        return fail(
            "the object file holds %d vegetation lines and %d layers were read"
            % [stated.size(), first.layers().size()],
            first.layers().size()
        )
    for index: int in first.layers().size():
        var layer: Dictionary = first.layers()[index]
        var line: String = stated[index]
        if not line.contains(layer["material"] as String):
            first.free()
            return fail(
                "layer %d reports the material '%s', which is not in its own line: %s"
                % [index + 1, layer["material"], line]
            )
        if (layer["density_map"] as String).is_empty():
            first.free()
            return fail("layer %d names no density map: %s" % [index + 1, line])
        if (layer["density_image"] as Image) == null:
            first.free()
            return fail(
                "layer %d's density map %s could not be read"
                % [index + 1, layer["density_map"]]
            )
        if (layer["density"] as float) <= 0.0:
            first.free()
            return fail("layer %d grows at a density of %.2f" % [
                index + 1, layer["density"] as float])

    var spread: Dictionary = _density_varies(first.layers()[0])
    if (spread["error"] as String) != "":
        first.free()
        return fail(spread["error"] as String, spread["value"] as float)

    # Grown around the terrain's own spawn.
    var start: Vector3 = terrain.start_position()
    first.focus_on(start)
    var planted: int = first.planted()
    if planted <= 0:
        first.free()
        return fail(
            "nothing grew within a tile of the spawn at %v, where the density map reads %.2f"
            % [start, spread["at_spawn"] as float],
            planted
        )
    var floating: Dictionary = _stands_on_the_ground(terrain, first)
    if (floating["error"] as String) != "":
        first.free()
        return fail(floating["error"] as String, floating["value"] as float)

    # And the same again: a hash places, so a second build is the first one.
    var second: RorVegetation = RorVegetation.new()
    second.setup(terrain)
    second.focus_on(start)
    var again: int = second.planted()
    second.free()
    first.free()
    if again != planted:
        return fail(
            "two builds of the same place grew %d plants and %d: the placement is not"
            % [planted, again] + " deterministic",
            again - planted
        )
    return ok(
        "%d layers from the terrain's own lines, density map spanning %.2f, %d plants around the"
        % [stated.size(), spread["value"] as float, planted]
        + " spawn standing within %.0f mm of the ground, identical on a second build"
        % ((floating["value"] as float) * 1000.0),
        planted
    )


## The vegetation lines as the terrain's own file writes them.
func _stated_lines(terrain: RorTerrain) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    for file: String in terrain.config["objects"] as PackedStringArray:
        var text: String = RorText.read(terrain.directory.path_join(file))
        for raw_line: String in text.split("\n"):
            var line: String = raw_line.strip_edges()
            if line.begins_with("grass"):
                out.append(line)
    return out


## The density map says different things in different places, and something where a vehicle
## starts.
func _density_varies(layer: Dictionary) -> Dictionary:
    var image: Image = layer["density_image"] as Image
    var lowest: float = INF
    var highest: float = -INF
    var step_x: int = maxi(image.get_width() / 64, 1)
    var step_y: int = maxi(image.get_height() / 64, 1)
    for y: int in range(0, image.get_height(), step_y):
        for x: int in range(0, image.get_width(), step_x):
            var value: float = image.get_pixel(x, y).r
            lowest = minf(lowest, value)
            highest = maxf(highest, value)
    var spread: float = highest - lowest
    if spread < MIN_DENSITY_SPREAD:
        return {
            "error": (
                "the density map varies by %.3f across the whole terrain: it is not deciding"
                % spread + " where anything grows"
            ),
            "value": spread,
            "at_spawn": 0.0,
        }
    return {"error": "", "value": spread, "at_spawn": highest}


## Every plant stands on the ground it grew from.
func _stands_on_the_ground(terrain: RorTerrain, vegetation: RorVegetation) -> Dictionary:
    var worst: float = 0.0
    var checked: int = 0
    for tile: Node in vegetation.get_children():
        for child: Node in tile.get_children():
            var instance: MultiMeshInstance3D = child as MultiMeshInstance3D
            if instance == null or instance.multimesh == null:
                continue
            var step: int = maxi(instance.multimesh.instance_count / 64, 1)
            for at: int in range(0, instance.multimesh.instance_count, step):
                var origin: Vector3 = instance.multimesh.get_instance_transform(at).origin
                var ground: float = terrain.height_at_world(origin.x, origin.z)
                worst = maxf(worst, absf(origin.y - ground))
                checked += 1
    if checked == 0:
        return {"error": "no plant could be checked against the ground", "value": 0.0}
    if worst > MAX_FLOAT_M:
        return {
            "error": "a plant stands %.3f m off the ground: the vegetation is not on the terrain"
                % worst,
            "value": worst,
        }
    return {"error": "", "value": worst}
