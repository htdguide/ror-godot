extends GateBase
## Every object a shipped terrain asks for is read, resolved and stood in the world.
##
## A terrain is not its heightmap. La Paz's road is lined with poles, its edge is closed by a
## horizon card and a ground skirt, and all of that arrives as a chain of the author's files: an
## object list names a definition, the definition names meshes, the meshes name materials, and
## the materials name textures. A break anywhere in that chain looks the same from a distance —
## an empty desert — which is why this counts the chain rather than photographing it.
##
## What a terrain asks for beyond its objects is reported rather than ignored, and what is
## reported has to stay true: vegetation is grown by `RorVegetation`, collision boxes are built by
## `RorObjectCollision` and road points are swept by `RorProceduralRoad`, so those are counted as
## built elsewhere. Only actor spawns and unreadable lines are still unread. This line said
## "not drawn yet: 2 vegetation layers" for as long as vegetation had been growing, which is the
## kind of stale claim a gate exists to prevent rather than to make.

const TERRAIN_DIR: String = "assets/terrains/lapaz2"
## How far outside its own map an object may stand. Horizon cards and ground skirts sit at the
## map's middle and are scaled up, so this is a bound on a misread coordinate rather than on
## composition.
const MAX_OUTSIDE_M: float = 6000.0
## What share of the objects have to resolve all the way to geometry.
const MIN_BUILT_SHARE: float = 0.95
## And how many triangles the whole set has to come to, so that resolving to empty meshes is not
## mistaken for resolving.
const MIN_TRIANGLES: int = 1000


static func meta() -> Dictionary:
    return {
        "name": "ror_terrain_objects_are_placed",
        "proves": "every object a shipped Rigs of Rods terrain lists resolves through its definition, meshes and materials into geometry standing inside the map",
        # the terrain itself has to load before what stands on it can.
        "builds_on": ["ror_terrain_matches_its_files"],
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "at least %.0f%% of the object file's own lines built, over %d triangles in total,"
            % [MIN_BUILT_SHARE * 100.0, MIN_TRIANGLES]
            + " and none more than %.0f m outside the map" % MAX_OUTSIDE_M
        ),
        "why": (
            "a terrain's props arrive through four of its author's file formats in a chain, and"
            + " a break anywhere in that chain renders as an empty desert — which is also what a"
            + " terrain with no props renders as. Counting the chain is the only way to tell"
            + " those apart without a person looking at the right part of the map."
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

    # The file's own count, taken by reading its lines here rather than through the parser under
    # test: a parser that drops half a file agrees with itself about how many objects there are.
    var listed: int = _object_lines(terrain)
    if listed == 0:
        return fail("%s lists no objects at all" % (terrain.config["objects"] as PackedStringArray))
    # Every six-number line is accounted for, as one of the three things it can be. A `.tobj`
    # mixes scenery with road points and actor spawns, and upstream sorts them before anything is
    # done with them — `TObjFileFormat.cpp`'s `IsRoad()` and `IsActor()`. Counting only the
    # scenery against every line would demand that road points be buildings; counting them all as
    # scenery is what made 374 of Port Starling's lines ask for object definitions named `0`, `8`
    # and `10`. So the sum is what has to match, and the split is reported.
    var placements: Array[Dictionary] = RorObjects.placements(terrain)
    var sorted: Dictionary = RorObjects.unbuilt(terrain)
    var accounted: int = (
        placements.size()
        + (sorted["road_points"] as int) + (sorted["actor_spawns"] as int)
    )
    if accounted != listed:
        return fail(
            "the object files hold %d object lines and the reader accounted for %d"
            % [listed, accounted],
            accounted - listed
        )

    # Objects are drawn as `MultiMeshInstance3D` batches — one per mesh per tile — so what is
    # counted here is derived from the instance transforms rather than from the number of nodes.
    # Counting children would count batches, and a batch is not an object: La Paz's 101 objects
    # come to 34 of them. Derived rather than asked for, so the thing under test is not the thing
    # reporting on itself.
    var root: Node3D = RorObjects.build(terrain)
    var triangles: int = 0
    var span: Vector2 = Vector2(
        terrain.geometry["world_x"] as float, terrain.geometry["world_z"] as float
    )
    var outside: PackedStringArray = PackedStringArray()
    var textured: int = 0
    var places: Dictionary = {}
    for child: Node in root.get_children():
        var batch: MultiMeshInstance3D = child as MultiMeshInstance3D
        if batch == null or batch.multimesh == null or batch.multimesh.mesh == null:
            continue
        var mesh: ArrayMesh = batch.multimesh.mesh as ArrayMesh
        var per_instance: int = _triangles(mesh)
        var drawn_here: int = batch.multimesh.instance_count
        triangles += per_instance * drawn_here
        if _is_textured(mesh):
            textured += drawn_here
        for index: int in drawn_here:
            var at: Vector3 = batch.multimesh.get_instance_transform(index).origin
            # One object can carry several meshes and so appear in several batches at the same
            # place; counted by where it stands, it is one object either way.
            places[Vector3i(roundi(at.x), roundi(at.y), roundi(at.z))] = true
            if (
                at.x < -MAX_OUTSIDE_M or at.x > span.x + MAX_OUTSIDE_M
                or at.z < -MAX_OUTSIDE_M or at.z > span.y + MAX_OUTSIDE_M
            ):
                outside.append("%s at %v" % [batch.name, at])
    var built: int = places.size()
    root.queue_free()

    var share: float = float(built) / float(maxi(placements.size(), 1))
    if share < MIN_BUILT_SHARE:
        return fail(
            "%d of %d objects resolved to geometry (%.0f%%): the chain from the object file to a"
            % [built, placements.size(), share * 100.0] + " mesh is broken somewhere",
            share
        )
    if triangles < MIN_TRIANGLES:
        return fail(
            "%d objects came to %d triangles: they are resolving to empty meshes"
            % [built, triangles],
            triangles
        )
    if outside.size() > 0:
        return fail(
            "objects stand outside the map: %s" % ", ".join(outside), outside.size()
        )
    if textured == 0:
        return fail(
            "not one of %d objects carries a texture: the material scripts are not being read"
            % built,
            textured
        )
    return ok(
        "%d of %d objects built, %d textured, %d triangles; %d vegetation layers grown by"
        % [built, placements.size(), textured, triangles, sorted["grass"] as int]
        + " RorVegetation, %d collision boxes and %d road points built elsewhere; not read:"
        % [sorted["collision_boxes"] as int, sorted["road_points"] as int]
        + " %d actor spawns, %d other lines"
        % [sorted["actor_spawns"] as int, sorted["unread_lines"] as int],
        built
    )


## How many object lines the terrain's own object files hold, counted by reading them.
func _object_lines(terrain: RorTerrain) -> int:
    var count: int = 0
    for file: String in terrain.config["objects"] as PackedStringArray:
        var text: String = RorText.read(terrain.directory.path_join(file))
        for raw_line: String in text.split("\n"):
            var line: String = raw_line.strip_edges()
            if line.is_empty() or line.begins_with("//") or line.begins_with(";"):
                continue
            var fields: PackedStringArray = line.split(",")
            if fields.size() < 7:
                continue
            if not fields[0].strip_edges().is_valid_float():
                continue
            count += 1
    return count


func _triangles(mesh: ArrayMesh) -> int:
    var total: int = 0
    for surface: int in mesh.get_surface_count():
        total += (mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
    return total


func _is_textured(mesh: ArrayMesh) -> bool:
    for surface: int in mesh.get_surface_count():
        var material: StandardMaterial3D = mesh.surface_get_material(surface) as StandardMaterial3D
        if material != null and material.albedo_texture != null:
            return true
    return false
