extends GateBase
## A surface whose material punches a shape out of its texture is photographed from in front and
## from behind, and has to look the same from both.
##
## **A tree is a different question from a wall, and the same instrument answers it wrongly.** The
## facing paint exists to catch a wall drawn back-to-front: it marks every back face, and a marked
## pixel is a surface turned away. Point it at foliage and it reports a fault that is not there —
## a fir on Port Starling filled 18% of its frame with marker while being drawn exactly right —
## because a leaf card *is* its own back. Asked for from a window, in those words: a tree is half
## transparent, so it needs a separate method.
##
## **What the terrain's own file says about them.** `3d-diggers_fir.material` declares
## `alpha_rejection greater_equal 128` for its foliage and nothing of the kind for its bark. That
## line is the author saying this pass is a cut-out, and `RorObjects` answers it with
## `TRANSPARENCY_ALPHA_SCISSOR` and `CULL_DISABLED`: a card with a shape punched out of it is
## meant to be seen from either side. So the claim here is not about winding at all. It is that a
## cut-out is drawn from both sides, which is a thing a photograph can settle — a card with its
## back culled is simply absent from half the directions you can walk round it.
##
## **The camera is on the card's own normal, twice.** `FacingViews` groups the cut-out faces by
## the direction their authored normals point and each group is drawn alone, so the frame holds
## one card and nothing else. Photographed from `+normal` and from `-normal`, the same card
## occupies the same silhouette; one drawn single-sided occupies none of the second frame. The
## measure is a ratio between the two views of the same geometry, so it does not depend on how
## much of the frame the card happens to fill.
##
## What this does **not** claim: that the punched shape is the right shape, or that a mesh ships
## the foliage submesh at all. `fir06_30.mesh` names `3D-Diggers/fir01` and the reader returns
## only its bark, which is why Russia's trees have no leaves; that is a reader fault with its own
## work, and this gate reports the count rather than pretending to cover it.

## Which terrain, unless one is named.
const DEFAULT_TERRAIN: String = "starling-port"
## How many objects, and how many card groups of each. Each group costs four captures: two views,
## each with and without the card.
const MAX_OBJECTS: int = 4
const MAX_GROUPS: int = 2
const CONVERGE: int = 6
## How much of the front view's area the back view has to show. Not 1.0: the two frames are
## mirror images taken from opposite sides, so the card's own perspective foreshortening and the
## stage's lighting put a few per cent between them even when the geometry is identical.
const MIN_SYMMETRY: float = 0.75
## Below this the card is too small in frame for a ratio to mean anything.
const MIN_PIXELS: int = 40
const LISTED: int = 6


static func meta() -> Dictionary:
    return {
        "name": "a_cut_out_card_is_drawn_from_both_sides",
        "proves": (
            "a surface whose own material declares alpha_rejection shows the same silhouette"
            + " from in front of its normal and from behind it"
        ),
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "the back view of a cut-out card covers at least 75% of what its front view covers"
        ),
        "why": (
            "a leaf card is its own back, so the facing paint reports a fault on every tree that"
            + " is drawn correctly, and a card whose back is culled is absent from half the"
            + " directions you can walk round it. Neither is visible to a gate that photographs"
            + " foliage the way it photographs a wall."
        ),
        "budget_s": 600.0,
        "needs_gpu": true,
        "milestone": "C2",
    }


func run(harness: Node) -> Dictionary:
    var wanted: String = Harness.args.get_string("terrain-dir", DEFAULT_TERRAIN)
    var loaded: Dictionary = RorTerrainLibrary.load_named(wanted)
    if (loaded.get("error", "") as String) != "":
        return ok("skipped: %s" % loaded["error"], 0)
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain
    var error: String = harness.setup_for("hero_3q")
    if error != "":
        return fail(error)
    # No shadows: a card's shadow on the stage floor is a difference between the two captures
    # without being the card, and it falls differently from either side.
    var sun: DirectionalLight3D = harness.world.get_node_or_null(^"Sun") as DirectionalLight3D
    if sun != null:
        sun.shadow_enabled = false

    var state: Dictionary = RorObjects.state(terrain)
    var subjects: PackedStringArray = _subjects(terrain, state)
    if subjects.is_empty():
        return ok("skipped: %s places no object with a cut-out surface" % wanted, 0)

    var one_sided: PackedStringArray = PackedStringArray()
    var report: PackedStringArray = PackedStringArray()
    var cards: int = 0
    for mesh_file: String in subjects:
        var mesh: ArrayMesh = RorObjects.mesh_of(terrain, mesh_file, state)
        if mesh == null:
            continue
        var groups: Array[Dictionary] = FacingViews.groups(mesh, MAX_GROUPS, true)
        var worst: float = 1.0
        for group: Dictionary in groups:
            var outcome: Dictionary = await _both_sides(harness, mesh, mesh_file, group)
            if (outcome["error"] as String) != "":
                return fail(outcome["error"] as String)
            cards += 1
            if (outcome["front"] as int) < MIN_PIXELS:
                continue
            var ratio: float = (
                float(outcome["back"] as int) / float(outcome["front"] as int)
            )
            worst = minf(worst, ratio)
            if ratio < MIN_SYMMETRY:
                one_sided.append(
                    "%s %s shows %.0f%% of its front view from behind"
                    % [mesh_file, group["label"], ratio * 100.0]
                )
        if not groups.is_empty():
            report.append("%s %d cards, worst %.0f%%" % [
                mesh_file.get_basename(), groups.size(), worst * 100.0
            ])

    if one_sided.size() > 0:
        return fail(
            "%d cut-out cards are drawn from one side only: %s"
            % [one_sided.size(), "; ".join(one_sided.slice(0, LISTED))],
            one_sided.size()
        )
    return ok("%s: %s" % [wanted, ", ".join(report)], cards)


## One card group, photographed from in front of its normal and from behind it. Returns
## `{"error", "front", "back"}` as sampled pixel counts.
func _both_sides(
    harness: Node, mesh: ArrayMesh, mesh_file: String, group: Dictionary
) -> Dictionary:
    var out: Dictionary = {"error": "", "front": 0, "back": 0}
    var at: Transform3D = RorObjects.transform_of(
        {"position": Vector3.ZERO, "rotation": Vector3.ZERO}, Vector3.ONE
    )
    var size: float = (at * mesh.get_aabb()).size.length()
    # Undressed: the facing paint is the instrument this gate exists to replace, and the card's
    # own alpha-scissored texture is what has to be visible from both sides.
    var alone: ArrayMesh = FacingViews.isolate(mesh, group)
    var node: MeshInstance3D = MeshInstance3D.new()
    node.mesh = alone
    node.transform = at
    harness.world.add_child(node)
    var label: String = group["label"] as String
    for side: String in ["front", "back"]:
        var turned: Dictionary = group.duplicate()
        if side == "back":
            turned["normal"] = -(group["normal"] as Vector3)
        var placement: Dictionary = FacingViews.placement(turned, at, size)
        harness.camera.look_at_from_position(
            placement["pos"] as Vector3, placement["look_at"] as Vector3,
            placement["up"] as Vector3
        )
        var stem: String = "cutout/%s/%s-%s" % [
            mesh_file.get_basename(), label.to_lower().replace(" ", ""), side
        ]
        node.visible = false
        var bare: Dictionary = await harness.capture_shot(stem + "-bare", "static", CONVERGE)
        node.visible = true
        if (bare["error"] as String) != "":
            out["error"] = "%s %s %s: %s" % [mesh_file, label, side, bare["error"]]
            break
        var shot: Dictionary = await harness.capture_shot(stem, "static", CONVERGE)
        if (shot["error"] as String) != "":
            out["error"] = "%s %s %s: %s" % [mesh_file, label, side, shot["error"]]
            break
        out[side] = FacingPaint.drawn_and_marked(
            shot["png"] as String, bare["png"] as String
        )["drawn"] as int
        var stamped: String = Stamp.write(
            shot["png"] as String, "%s %s" % [label, side.to_upper()]
        )
        if stamped != "":
            out["error"] = stamped
            break
    harness.world.remove_child(node)
    node.queue_free()
    return out


## The most-placed meshes that have a cut-out surface at all.
func _subjects(terrain: RorTerrain, state: Dictionary) -> PackedStringArray:
    var counts: Dictionary = {}
    for placement: Dictionary in RorObjects.placements(terrain):
        var odef: Dictionary = RorObjects.definition(
            terrain, placement["name"] as String, state
        )
        if (odef.get("error", "") as String) != "":
            continue
        for mesh_file: String in odef["meshes"] as PackedStringArray:
            counts[mesh_file] = (counts.get(mesh_file, 0) as int) + 1
    var named: String = Harness.args.get_string("object", "")
    var names: Array = [named] if named != "" else counts.keys()
    names.sort_custom(func(a: String, b: String) -> bool:
        return (counts.get(a, 0) as int) > (counts.get(b, 0) as int)
    )
    var out: PackedStringArray = PackedStringArray()
    for name: String in names:
        if out.size() >= MAX_OBJECTS:
            break
        var mesh: ArrayMesh = RorObjects.mesh_of(terrain, name as String, state)
        if mesh != null and FacingViews.cut_outs(mesh).size() > 0:
            out.append(name as String)
    return out
