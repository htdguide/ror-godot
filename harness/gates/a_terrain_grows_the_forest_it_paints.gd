extends GateBase
## Every forest a terrain paints with a density map is grown, where it painted it.
##
## **A `trees` line was not a keyword this project knew.** Six lines across the whole library go
## unread, and two of them are Russia's: `trees 0, 360, 0.07, 0.09, 1, 100, 800, fir06_30.mesh
## none Russia-TreeMesh.png`, and the same again for `fir14_25.mesh`. Both meshes and the density
## map are on the disk. That terrain has been a bare hillside for want of one word in a list of
## two.
##
## **The oracle is upstream's placement rule and the terrain's own density map.**
## `TerrainObjectManager::ProcessTree` walks a 10 m grid over the whole map, asks the density map
## how much grows at each cell, and scatters that many trees inside it at a yaw and scale drawn
## from the line's own ranges. The gate walks the same grid with its own reader and requires the
## built scene to hold exactly that many.
##
## **Three things beyond the count**, each checkable against the line that asked for them:
##
## - every tree stands on the ground, within a millimetre of the heightmap;
## - every yaw and every scale falls inside the range the line states;
## - a second build is identical, because a position decides its own tree and nothing is drawn
##   from a random number generator.

## Below this there is no forest to judge.
const MIN_TREES: int = 100
## A tree sits on the heightmap. This is float slack, not a tolerance.
const ON_GROUND_M: float = 0.002
## Float slack on a scale compared against the range it was drawn from.
const RANGE_EPSILON: float = 1e-4
const LISTED: int = 6


## **It builds on nothing.** `builds_on` means "running this exercises that, at least as
## hard", and the graph stops running what it implies — so an edge that only records which
## gate came first is an edge that silently retires a gate. This one grows trees and never touches a blade of grass.


static func meta() -> Dictionary:
    return {
        "name": "a_terrain_grows_the_forest_it_paints",
        "proves": "every `trees` line grows as many trees as its own density map and upstream's placement rule call for, each standing on the ground within the yaw and scale the line states",
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": "the count upstream's rule gives over the terrain's own density map, exactly; every tree on the ground and inside its stated ranges",
        "why": (
            "`trees` was not a keyword this project knew, so Russia's two fir species went into"
            + " the pile of lines nothing reads. 14,090 trees were missing from one map because"
            + " of one word."
        ),
        "budget_s": 300.0,
        "needs_gpu": false,
        "milestone": "C2",
    }


func run(_harness: Node) -> Dictionary:
    var terrains: int = 0
    var trees: int = 0
    # What the content asks for, which is what decides whether there is anything to judge. A
    # builder that grows nothing must fail rather than skip, and a first draft of this gate let
    # it skip: halving the density made the count zero and the verdict "skipped".
    var asked: int = 0
    var problems: PackedStringArray = PackedStringArray()
    for summary: Dictionary in RorTerrainLibrary.summaries():
        if (summary["error"] as String) != "":
            continue
        var loaded: Dictionary = RorTerrainLibrary.load_named(summary["name"] as String)
        if (loaded.get("error", "") as String) != "":
            continue
        var terrain: RorTerrain = loaded["terrain"] as RorTerrain
        var counted: Dictionary = RorTrees.summary(terrain)
        if (counted["layers"] as int) == 0:
            continue
        terrains += 1
        var wanted: int = _wanted(terrain)
        asked += wanted
        var root: Node3D = RorTrees.build(terrain)
        var built: int = _instances(root)
        trees += built
        if built != wanted:
            problems.append(
                "%s: its density map and the placement rule call for %d trees and %d were grown"
                % [summary["name"], wanted, built]
            )
        problems.append_array(_judge(terrain, root, summary["name"] as String))
        var again: Node3D = RorTrees.build(terrain)
        if not _same(root, again):
            problems.append("%s: a second build grew a different forest" % summary["name"])
        root.queue_free()
        again.queue_free()

    if asked < MIN_TREES:
        return ok(
            "skipped: the terrains in this checkout ask for %d trees" % asked, asked
        )
    if problems.size() > 0:
        return fail(
            "%d faults across %d terrains with a forest: %s"
            % [problems.size(), terrains, "; ".join(problems.slice(0, LISTED))],
            problems.size()
        )
    return ok(
        "%d trees across %d terrains, each on the ground and inside the yaw and scale its own"
        % [trees, terrains] + " line states, identical on a second build",
        trees
    )


## How many trees the terrain's own lines and density maps call for, by upstream's rule, counted
## here rather than asked of the builder.
func _wanted(terrain: RorTerrain) -> int:
    var dds: RefCounted = ClassDB.instantiate("DdsReader") as RefCounted
    var total: int = 0
    for line: Dictionary in RorTrees.lines(terrain):
        var layer: Dictionary = TreeLayer.read(line)
        if not TreeLayer.is_complete(layer):
            continue
        var density: Image = RorTerrainSkin.image_of(
            RorContentPath.find(layer["density_map"] as String, terrain.directory), dds
        )
        if density == null:
            continue
        var span_x: float = terrain.geometry["world_x"] as float
        var span_z: float = terrain.geometry["world_z"] as float
        var grid: float = TreeLayer.grid_metres(layer)
        var regular: bool = TreeLayer.is_regular(layer)
        var high: float = layer["high_density"] as float
        var x: float = 0.0
        while x < span_x:
            var z: float = 0.0
            while z < span_z:
                var px: int = clampi(
                    int(x / span_x * float(density.get_width())), 0, density.get_width() - 1
                )
                var pz: int = clampi(
                    int(z / span_z * float(density.get_height())), 0, density.get_height() - 1
                )
                var share: float = density.get_pixel(px, pz).r
                if regular:
                    total += 1 if share >= RorTrees.REGULAR_DENSITY else 0
                else:
                    total += int(high * share)
                z += grid
            x += grid
    return total


## Whether every tree stands on the ground and inside the ranges its line states.
func _judge(terrain: RorTerrain, root: Node3D, name: String) -> PackedStringArray:
    var out: PackedStringArray = PackedStringArray()
    var ranges: Dictionary = {}
    for line: Dictionary in RorTrees.lines(terrain):
        var layer: Dictionary = TreeLayer.read(line)
        ranges[layer["mesh"]] = layer
    for child: Node in root.get_children():
        var batch: MultiMeshInstance3D = child as MultiMeshInstance3D
        if batch == null or not batch.has_meta("mesh_file"):
            continue
        var layer: Dictionary = ranges.get(batch.get_meta("mesh_file"), {}) as Dictionary
        if layer.is_empty():
            continue
        var low: float = minf(layer["scale_from"] as float, layer["scale_to"] as float)
        var high: float = maxf(layer["scale_from"] as float, layer["scale_to"] as float)
        for index: int in batch.multimesh.instance_count:
            # Local to the batch, which stands among its own trees.
            var at: Transform3D = (
                batch.transform * batch.multimesh.get_instance_transform(index)
            )
            var ground: float = terrain.height_at_world(at.origin.x, at.origin.z)
            if absf(at.origin.y - ground) > ON_GROUND_M:
                out.append(
                    "%s: a tree floats %.3f m off the ground"
                    % [name, at.origin.y - ground]
                )
                return out
            var scale: float = at.basis.get_scale().y
            if scale < low - RANGE_EPSILON or scale > high + RANGE_EPSILON:
                out.append(
                    "%s: a tree is scaled %.4f, outside the %.4f to %.4f its line states"
                    % [name, scale, low, high]
                )
                return out
    return out


func _instances(root: Node3D) -> int:
    var out: int = 0
    for child: Node in root.get_children():
        out += (child as MultiMeshInstance3D).multimesh.instance_count
    return out


## Whether two builds placed the same trees in the same places.
func _same(a: Node3D, b: Node3D) -> bool:
    if a.get_child_count() != b.get_child_count():
        return false
    for index: int in a.get_child_count():
        var one: MultiMeshInstance3D = a.get_child(index) as MultiMeshInstance3D
        var two: MultiMeshInstance3D = b.get_child(index) as MultiMeshInstance3D
        if one.name != two.name or one.multimesh.instance_count != two.multimesh.instance_count:
            return false
        for which: int in one.multimesh.instance_count:
            if not one.multimesh.get_instance_transform(which).is_equal_approx(
                two.multimesh.get_instance_transform(which)
            ):
                return false
    return true
