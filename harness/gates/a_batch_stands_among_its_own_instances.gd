extends GateBase
## Every batch a terrain builds stands where the things in it stand.
##
## **A visibility range is measured to the node, not to the instance.** Godot takes the distance
## from the camera to a `GeometryInstance3D`'s own origin and applies the range to everything it
## draws. A `MultiMeshInstance3D` left at the world origin with its instances scattered across a
## 3 km map is therefore judged by how far the camera is from (0, 0, 0) — which, anywhere on the
## map, is hundreds of metres from the truth.
##
## **That is how distance meshes broke the buildings.** The `beginlodmesh` work set a range on
## every batch of an object that declares one, and the batches sat at the origin: a building whose
## first level ends at 100 m was drawn only while the camera was within 100 m of the map's corner,
## which is to say almost never. Reported from a window as "some of the buildings are still
## missing", one commit after a gate had confirmed that each of those ranges was exactly the one
## the definition states. The range was right and it was being measured from nowhere.
##
## **The oracle is the instances themselves.** A batch has to stand inside the bounding box of
## what it draws. Nothing here is a tolerance: a node among its own instances is in their box by
## definition, and a node at the origin with its instances a kilometre away is not.
##
## This covers every batch a terrain builds — its objects, its distance meshes, its forests — not
## only the ones carrying a range today, because a batch that is somewhere else is also a batch
## whose frustum culling and whose sort order are wrong.

## Below this there is nothing to judge.
const MIN_BATCHES: int = 10
## Float slack on a centroid compared against the box it was computed from. A node among its own
## instances is inside their box by construction; this covers the arithmetic, not a tolerance.
const EPSILON_M: float = 0.01
const LISTED: int = 6


static func meta() -> Dictionary:
    return {
        "name": "a_batch_stands_among_its_own_instances",
        "proves": "every multimesh batch a terrain builds has its node inside the bounding box of the instances it draws, so a visibility range and a frustum test are measured from the right place",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "the node's position inside the bounding box of its own instances, for every batch",
        "why": (
            "Godot measures a visibility range to the node and applies it to every instance, so"
            + " a batch at the world origin is judged by the camera's distance from (0, 0, 0)."
            + " Buildings with a distance mesh were drawn only near one corner of the map, and"
            + " the gate on those ranges passed throughout: the range was right and it was"
            + " measured from nowhere."
        ),
        "budget_s": 300.0,
        "needs_gpu": false,
        "milestone": "C2",
    }


func run(_harness: Node) -> Dictionary:
    var batches: int = 0
    var ranged: int = 0
    var problems: PackedStringArray = PackedStringArray()
    for summary: Dictionary in RorTerrainLibrary.summaries():
        if (summary["error"] as String) != "":
            continue
        var loaded: Dictionary = RorTerrainLibrary.load_named(summary["name"] as String)
        if (loaded.get("error", "") as String) != "":
            continue
        var terrain: RorTerrain = loaded["terrain"] as RorTerrain
        for root: Node3D in [RorObjects.build(terrain), RorTrees.build(terrain)]:
            for child: Node in root.get_children():
                var batch: MultiMeshInstance3D = child as MultiMeshInstance3D
                if batch == null or batch.multimesh == null:
                    continue
                if batch.multimesh.instance_count == 0:
                    continue
                batches += 1
                if batch.visibility_range_end > 0.0 or batch.visibility_range_begin > 0.0:
                    ranged += 1
                var away: float = _outside_its_own_box(batch)
                if away > EPSILON_M:
                    problems.append(
                        "%s: %s stands %.2f m outside the box of the %d instances it draws"
                        % [summary["name"], batch.name, away, batch.multimesh.instance_count]
                    )
            root.queue_free()

    if batches < MIN_BATCHES:
        return ok("skipped: %d batches in this checkout" % batches, batches)
    if problems.size() > 0:
        return fail(
            "%d of %d batches stand away from what they draw: %s"
            % [problems.size(), batches, "; ".join(problems.slice(0, LISTED))],
            problems.size()
        )
    return ok(
        "%d batches across the library stand among their own instances, %d of them carrying a"
        % [batches, ranged] + " visibility range",
        batches
    )


## How far outside the bounding box of its own instances a batch's node stands, in metres. Zero
## when it is inside, which is where a batch belongs.
func _outside_its_own_box(batch: MultiMeshInstance3D) -> float:
    var low: Vector3 = Vector3.INF
    var high: Vector3 = -Vector3.INF
    for index: int in batch.multimesh.instance_count:
        var at: Vector3 = (
            batch.transform * batch.multimesh.get_instance_transform(index)
        ).origin
        low = low.min(at)
        high = high.max(at)
    var here: Vector3 = batch.position
    var outside: Vector3 = (low - here).max(here - high).max(Vector3.ZERO)
    return outside.length()
