extends GateBase
## Photographs each group of a terrain object's faces from straight in front of it, and requires
## that none of them is drawn back-to-front.
##
## **The fault this exists for.** Every building in the library was drawn inside out, because the
## mesh reader reverses a triangle for the vehicle path and a terrain object passes through no
## such path. From outside, a wall was simply absent — and that was reported from a window rather
## than measured, because nothing in the suite photographed a building from outside.
##
## **A back face is painted rather than culled.** A wall turned the wrong way renders as empty
## sky, which is pixel for pixel what a correct empty sky looks like, so the fault and the absence
## of the fault are the same photograph. `FacingPaint` dresses each surface so its front keeps its
## texture and its back draws the axis it points along in a primary colour.
##
## **The camera angle is what makes the paint decidable.** A fixed six-sided set could not carry a
## verdict: stand to the left of a building and the frame holds the near wall, the far wall, the
## roof and the back of whatever is turned away, and painted pixels in it may be a fault or may be
## correct — a road slab is one sheet and from underneath you are supposed to see its back. Three
## bounds were tried and real content falsified each one.
##
## So the views come from the mesh. `FacingViews` groups the faces by the direction the author's
## own vertex normals point, each group is drawn **alone**, and the camera stands on that group's
## normal looking back down it. Every triangle in the frame is one whose author said it faces the
## camera, and nothing else is in the frame at all. Then any marker is a face drawn back-to-front
## and the threshold needs no judgement. Asked for in those words from a window: make the camera
## angle and the object angle right, so only the tested surfaces face the camera.
##
## **The oracle is the file's normals, which are not the winding.** `ARRAY_NORMAL` is what the
## `.mesh` shipped; the index order is what the reader produced. Whether they agree is a question
## with an answer.
##
## Cut-out surfaces are not here. A material declaring `alpha_rejection` is drawn from both sides
## on purpose and its back is not a fault; `a_cut_out_card_is_drawn_from_both_sides` photographs
## those.
##
## **The instrument is checked against a mesh nobody here authored.** Before any terrain object is
## photographed, the same camera, the same paint and the same count are pointed at Godot's own
## `BoxMesh`, whose winding and normals are consistent by construction and which the engine draws
## correctly by definition. If the control shows marker then the gate is measuring its own
## mistake, and it says so instead of reporting every object in the library as broken. That is not
## hypothetical: the first run of this gate called all 20 face groups of five Port Starling
## objects 100% marker, which is a claim extraordinary enough to need a control before it is
## believed.
##
## `tools/objectset.sh` assembles a sheet per object. Judging whether a texture is the *right*
## texture is still a person's; this says each surface is there and is facing out.

## Which terrain to photograph, unless one is named.
const DEFAULT_TERRAIN: String = "starling-port"
## How many of the most-placed objects to photograph in one run, and how many face groups of each.
## Every group costs two captures.
const MAX_OBJECTS: int = 6
const MAX_GROUPS: int = 4
const CONVERGE: int = 6
## How much of a group's own drawn area may be marker before it is drawn back-to-front. Not zero:
## a group is flat to within `FacingViews.GROUP_DEGREES`, so a bevel at its edge can turn a few
## pixels away from a camera the group as a whole faces.
const MAX_MARKED_SHARE: float = 0.08
## How many sampled pixels a group has to put on the screen to count as drawn at all. Photographed
## head-on along its own normal, a group that draws nothing is missing geometry.
const MIN_PIXELS: int = 8
const LISTED: int = 6


static func meta() -> Dictionary:
    return {
        "name": "object_photoset",
        "proves": (
            "every large group of faces on a terrain's most-placed objects shows its front to a"
            + " camera standing on the normal its own file carries for it"
        ),
        "oracle": GateBase.ORACLE_EXTERNAL,
        "threshold": (
            "photographed alone and head-on along its authored normal, a face group draws"
            + " something and is under 8% marker"
        ),
        "why": (
            "every building in the library was drawn inside out and it was reported from a"
            + " window, not measured: the mesh reader reverses a triangle for the vehicle path"
            + " and an object passes through no such path. From outside, a wall was simply"
            + " absent, and nothing in the suite photographed a building from outside."
        ),
        "budget_s": 900.0,
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

    # No floor, no sky, no ambient, no shadow. The stage's checkerboard ground sits at y = 0 and
    # so does a ground-hugging object, and the two fight for the depth buffer; a shadow on it is a
    # difference between captures without being the object.
    harness.use_measurement_environment()
    var sun: DirectionalLight3D = harness.world.get_node_or_null(^"Sun") as DirectionalLight3D
    if sun != null:
        sun.shadow_enabled = false

    var meshes: PackedStringArray = _subjects(terrain)
    if meshes.is_empty():
        return ok("skipped: %s places no object with geometry" % wanted, 0)

    var control: Dictionary = await _control(harness)
    if (control["error"] as String) != "":
        return fail(control["error"] as String)

    var state: Dictionary = RorObjects.state(terrain)
    var wrong_way: PackedStringArray = PackedStringArray()
    var missing: PackedStringArray = PackedStringArray()
    var unjudged: PackedStringArray = PackedStringArray()
    var report: PackedStringArray = PackedStringArray()
    var shot_count: int = 0
    for mesh_file: String in meshes:
        var mesh: ArrayMesh = RorObjects.mesh_of(terrain, mesh_file, state)
        if mesh == null:
            continue
        var groups: Array[Dictionary] = FacingViews.groups(mesh, MAX_GROUPS)
        var cards: int = FacingViews.cut_outs(mesh).size()
        if groups.is_empty():
            # Either every surface is a cut-out card, which has its own gate, or the mesh ships
            # no normals and there is nothing to hold its winding against. Reported, not failed:
            # a gate that invents the direction it then checks proves nothing.
            unjudged.append("%s (%d cut-out surfaces)" % [mesh_file, cards])
            continue
        var outcome: Dictionary = await _photograph(harness, mesh, mesh_file, groups)
        if (outcome["error"] as String) != "":
            return fail(outcome["error"] as String)
        shot_count += (outcome["shots"] as int)
        wrong_way.append_array(outcome["wrong_way"] as PackedStringArray)
        missing.append_array(outcome["missing"] as PackedStringArray)
        report.append("%s %s" % [mesh_file.get_basename(), outcome["summary"]])

    if missing.size() > 0:
        return fail(
            "%d face groups draw nothing when photographed along their own normal: %s"
            % [missing.size(), "; ".join(missing.slice(0, LISTED))],
            missing.size()
        )
    if wrong_way.size() > 0:
        return fail(
            "%d face groups are drawn back-to-front — the camera is on the normal their own"
            % wrong_way.size()
            + " file carries and they show their back: %s"
            % "; ".join(wrong_way.slice(0, LISTED)),
            wrong_way.size()
        )
    return ok(
        "%s; %s: %s%s" % [
            control["summary"], wanted, ", ".join(report),
            "" if unjudged.is_empty() else
            "; no authored direction to judge %s" % ", ".join(unjudged.slice(0, LISTED)),
        ],
        shot_count
    )


## The same instrument pointed at a mesh this project did not author: Godot's `BoxMesh`.
##
## Its six faces are wound and normalled consistently by construction, so every group of them
## must show its front to a camera standing on its own normal. Marker here is the gate being
## wrong, not the content, and the difference matters: a measurement that calls every object in
## the library inside out is either a serious finding or a broken instrument, and nothing in the
## photograph itself tells you which.
func _control(harness: Node) -> Dictionary:
    var box: ArrayMesh = ArrayMesh.new()
    box.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().get_mesh_arrays())
    var groups: Array[Dictionary] = FacingViews.groups(box, MAX_GROUPS)
    if groups.is_empty():
        return {"error": "the control mesh has no face groups: the grouping is broken"}
    var outcome: Dictionary = await _photograph(harness, box, "control-box.mesh", groups)
    if (outcome["error"] as String) != "":
        return outcome
    var wrong: PackedStringArray = outcome["wrong_way"] as PackedStringArray
    var gone: PackedStringArray = outcome["missing"] as PackedStringArray
    if wrong.size() > 0 or gone.size() > 0:
        return {"error":
            "the control fails: Godot's own BoxMesh draws %d groups back-to-front and %d not at"
            % [wrong.size(), gone.size()]
            + " all under this camera, so the instrument is wrong and no object measured with it"
            + " means anything (%s)" % ", ".join(wrong + gone)
        }
    return {"error": "", "summary": "control box %s" % outcome["summary"]}


## Every face group of one mesh, photographed alone and head-on. Returns
## `{"error", "shots", "wrong_way", "missing", "summary"}`.
func _photograph(
    harness: Node, mesh: ArrayMesh, mesh_file: String, groups: Array[Dictionary]
) -> Dictionary:
    var out: Dictionary = {
        "error": "", "shots": 0, "wrong_way": PackedStringArray(),
        "missing": PackedStringArray(), "summary": "",
    }
    # The same -90 degree pitch every object is placed with, so the photograph shows the object
    # the way the map does rather than on its side.
    var at: Transform3D = RorObjects.transform_of(
        {"position": Vector3.ZERO, "rotation": Vector3.ZERO}, Vector3.ONE
    )
    var size: float = (at * mesh.get_aabb()).size.length()
    var worst: float = 0.0
    for group: Dictionary in groups:
        # Isolated from the undressed mesh, then painted: `FacingPaint` has to see the terrain's
        # own material to know whether the surface is a cut-out it must leave alone.
        var alone: ArrayMesh = FacingViews.isolate(mesh, group)
        FacingPaint.apply(alone)
        var node: MeshInstance3D = MeshInstance3D.new()
        node.mesh = alone
        node.transform = at
        harness.world.add_child(node)
        var label: String = group["label"] as String
        var placement: Dictionary = FacingViews.placement(group, at, size)
        harness.camera.look_at_from_position(
            placement["pos"] as Vector3, placement["look_at"] as Vector3,
            placement["up"] as Vector3
        )
        var stem: String = "objectset/%s/%s" % [
            mesh_file.get_basename(), label.to_lower().replace(" ", "")
        ]
        # The same frame twice, against two backgrounds. What the group drew is identical in
        # both; the background is not. Differencing against an empty stage instead loses every
        # part of a subject that happens to match it, and a mid-grey slab drawn unshaded against
        # a mid-grey sky cancels completely.
        HarnessCapture.use_background(harness.world, Color.BLACK)
        var dark: Dictionary = await harness.capture_shot(stem + "-dark", "static", CONVERGE)
        if (dark["error"] as String) != "":
            out["error"] = "%s %s: %s" % [mesh_file, label, dark["error"]]
            return out
        HarnessCapture.use_background(harness.world, Color.WHITE)
        var shot: Dictionary = await harness.capture_shot(stem, "static", CONVERGE)
        if (shot["error"] as String) != "":
            out["error"] = "%s %s: %s" % [mesh_file, label, shot["error"]]
            return out
        out["shots"] = (out["shots"] as int) + 1
        harness.world.remove_child(node)
        node.queue_free()

        var measured: Dictionary = FacingPaint.drawn_and_marked(
            dark["png"] as String, shot["png"] as String
        )
        var drawn: int = measured["drawn"] as int
        var marked: int = measured["marked"] as int
        var share: float = 0.0 if drawn == 0 else float(marked) / float(drawn)
        worst = maxf(worst, share)
        if drawn < MIN_PIXELS:
            # A packed array read out of a dictionary is a copy, so a fault is recorded by
            # writing the array back. Appending to the read-out value loses it, silently, and
            # that is how the first run of this gate reported "worst 100% marker" and passed.
            var absent: PackedStringArray = out["missing"] as PackedStringArray
            absent.append("%s %s" % [mesh_file, label])
            out["missing"] = absent
        elif share > MAX_MARKED_SHARE:
            var faults: PackedStringArray = out["wrong_way"] as PackedStringArray
            faults.append("%s %s (%.0f%% of it)" % [mesh_file, label, share * 100.0])
            out["wrong_way"] = faults
        # The group's own name and direction, in the frame, stamped after the measurement so the
        # label is never part of what is measured. A texture can look plausible and be on the
        # wrong face, and a tile that does not say which side it is of cannot tell you.
        var stamped: String = Stamp.write(shot["png"] as String, label)
        if stamped != "":
            out["error"] = stamped
            return out
    out["summary"] = "%d groups, worst %.0f%% marker" % [groups.size(), worst * 100.0]
    return out


## The meshes a terrain places most often, which are the ones a session drives past.
func _subjects(terrain: RorTerrain) -> PackedStringArray:
    var state: Dictionary = RorObjects.state(terrain)
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
    if named != "":
        return PackedStringArray([named] if counts.has(named) else [])
    var names: Array = counts.keys()
    names.sort_custom(func(a: String, b: String) -> bool:
        return (counts[a] as int) > (counts[b] as int)
    )
    var out: PackedStringArray = PackedStringArray()
    for name: String in names.slice(0, MAX_OBJECTS):
        out.append(name as String)
    return out
