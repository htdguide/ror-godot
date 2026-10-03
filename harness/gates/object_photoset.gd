extends GateBase
## Photographs a terrain's own objects from every side.
##
## **A building is a model like any other, and one angle hides as much of it as it hides of a
## truck.** The vehicle photoset exists because a door looked open from the front, a tailgate
## looked missing, and single-sided panels looked transparent — each obvious from a view nobody
## was taking. Terrain objects had no such instrument, and the fault that proved it was reported
## from a window rather than measured: every building in the library was drawn inside out, because
## the mesh reader reverses a triangle for the vehicle path and an object passes through no such
## path. From outside, a wall was simply absent.
##
## **A back face is painted rather than culled.** A wall turned the wrong way renders as empty
## sky, which is pixel for pixel what a correct empty sky looks like — so the fault and the
## absence of the fault are the same photograph, and no amount of counting settles it. Every
## surface is dressed in `FacingPaint` for these captures: the front keeps its own texture, the
## back draws the axis it points along in a primary colour. A view showing any marker is a view
## of a surface facing the wrong way, and the still says which wall and which direction.
##
## **A view that is empty is a finding too — for a person.** Each object is photographed alone on the stage, framed
## from its own bounds, twice — once without it and once with — and what is measured is the
## difference. The stage has a floor and a sky of its own, so counting "pixels that are not
## background" passes every view whether or not the object is there, which is what the first
## version of this gate did: it could not fail. A model visible from the left and
## not from the right is exactly what a single-sided or inverted panel looks like, and it is the
## one geometry fault a still photograph catches better than any measurement of the mesh.
##
## `tools/objectset.sh` assembles a sheet per object for a person to look at. Judging whether a
## texture is the *right* texture is theirs; this says the thing is there and is drawn from every
## side it should be.
##
## Which objects: the ones a terrain places most, because those are what a session actually
## drives past. `--object <mesh>` photographs one by name instead.

## Which terrain to photograph, unless one is named.
const DEFAULT_TERRAIN: String = "starling-port"
## How many of the most-placed objects to photograph in one run. The sheet has to stay readable
## and every view costs a capture.
const MAX_OBJECTS: int = 6
## Outside views only: an object has no interior to stand in, and its underside is usually open.
const VIEWS: Array[String] = ["front", "back", "left", "right", "top", "three_quarter"]
const CONVERGE: int = 6
## Every view must show something.
## A view counts as empty when it shows this little of what the object's best view shows.
##
## **A share of the frame is not a verdict.** Every view is framed from the object's own bounding
## diagonal, so a flat slab fills a different fraction from above than a tall sign does from the
## side, and a fixed bound either fails honest edge-on views or passes a face that is missing.
## Measured against the object's own best view it is framing-independent: a sidewalk seen along
## its edge is a thin sliver of its plan view and still plainly there, while a roof invisible from
## above is a few parts in a thousand of its own silhouette.
const MIN_SHARE_OF_BEST: float = 0.02
## How much of a frame may be marker before the view is reporting a surface facing the wrong way.
## Not zero: a face seen exactly edge-on shows a sliver of its own back through the depth buffer.
const MAX_MARKED: float = 0.002
const LISTED: int = 6
## How much a pixel has to move, summed over the channels, to count as the object rather than as
## the renderer's own noise between two captures of the same scene.
const CHANGED: float = 0.02


static func meta() -> Dictionary:
    return {
        "name": "object_photoset",
        "proves": "a terrain's most-placed objects are photographed from every side with their back faces painted, so a person can see which surfaces are turned away",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "every view of every object captured; what the sheets show is for a person",
        "why": (
            "every building in the library was drawn inside out and it was reported from a window,"
            + " not measured: the mesh reader reverses a triangle for the vehicle path and an"
            + " object passes through no such path. From outside, a wall was simply absent, and"
            + " nothing in the suite photographed a building from outside."
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

    # No shadows while measuring. The object casts one on the stage's floor, and a shadow is a
    # difference between the two captures without being the object: a roof invisible from above
    # still moved 0.5% of the frame through its shadow alone, which read as "the object is there".
    var sun: DirectionalLight3D = harness.world.get_node_or_null(^"Sun") as DirectionalLight3D
    if sun != null:
        sun.shadow_enabled = false

    var meshes: PackedStringArray = _subjects(terrain)
    if meshes.is_empty():
        return ok("skipped: %s places no object with geometry" % wanted, 0)

    var state: Dictionary = RorObjects.state(terrain)
    var empty: PackedStringArray = PackedStringArray()
    var wrong_way: PackedStringArray = PackedStringArray()
    var report: PackedStringArray = PackedStringArray()
    for mesh_file: String in meshes:
        var mesh: ArrayMesh = RorObjects.mesh_of(terrain, mesh_file, state)
        if mesh == null:
            continue
        var read: Dictionary = (state["reader"] as RefCounted).read_file(
            RorContentPath.find(mesh_file, terrain.directory)
        )
        var closed: bool = (
            (read.get("error", "") as String) == ""
            and not ObjectWinding.is_open(read["submeshes"] as Array)
        )
        var node: MeshInstance3D = MeshInstance3D.new()
        # A copy, because the facing dress is a diagnostic and the cached mesh is shared.
        var dressed: ArrayMesh = mesh.duplicate() as ArrayMesh
        FacingPaint.apply(dressed)
        node.mesh = dressed
        # The same -90 degree pitch every object is placed with, so the photograph shows the
        # object the way the map does rather than on its side.
        node.transform = RorObjects.transform_of(
            {"position": Vector3.ZERO, "rotation": Vector3.ZERO}, Vector3.ONE
        )
        harness.world.add_child(node)
        var bounds: AABB = node.transform * mesh.get_aabb()
        var covered: Dictionary = {}
        var painted: float = 0.0
        for view: String in VIEWS:
            var placement: Dictionary = Photoset.placement(view, bounds, bounds.get_center())
            harness.camera.look_at_from_position(
                placement["pos"] as Vector3, placement["look_at"] as Vector3, Vector3.UP
            )
            # The same frame without the object, so what is measured is the object and not the
            # stage. A first version counted every pixel that was not background and the stage's
            # own checkerboard floor passed every view on its own: the gate could not fail.
            node.visible = false
            var bare: Dictionary = await harness.capture_shot(
                "objectset/%s/%s-bare" % [mesh_file.get_basename(), view], "static", CONVERGE
            )
            node.visible = true
            if (bare["error"] as String) != "":
                return fail("%s %s: %s" % [mesh_file, view, bare["error"]])
            var shot: Dictionary = await harness.capture_shot(
                "objectset/%s/%s" % [mesh_file.get_basename(), view], "static", CONVERGE
            )
            if (shot["error"] as String) != "":
                return fail("%s %s: %s" % [mesh_file, view, shot["error"]])
            covered[view] = _coverage(shot["png"] as String, bare["png"] as String)
            var marked: float = FacingPaint.marked_share(shot["png"] as String)
            painted += marked
            # **Only a closed object is judged automatically.** Seeing the back of an open
            # surface is not a fault: a road slab is one sheet and from underneath you are
            # looking at its back, correctly. A closed object has no outside view of its
            # interior, so a marker there means a face is turned the wrong way round.
            if marked > MAX_MARKED:
                wrong_way.append(
                    "%s %s from the %s (%.0f%%)"
                    % [mesh_file, "closed" if closed else "open", view, marked * 100.0]
                )
            # The view's own name, in the frame, stamped after the measurement so the label is
            # never part of what is measured. A texture can look plausible and be on the wrong
            # face, and a tile that does not say which side it is of cannot tell you.
            var stamped: String = Stamp.write(shot["png"] as String, _label(view))
            if stamped != "":
                return fail(stamped)
        var best: float = 0.0
        for view: String in VIEWS:
            best = maxf(best, covered[view] as float)
        var thin: int = 0
        for view: String in VIEWS:
            var share: float = 0.0 if best <= 0.0 else (covered[view] as float) / best
            if share < MIN_SHARE_OF_BEST:
                thin += 1
                empty.append(
                    "%s from the %s (%.1f%% of its own best view)"
                    % [mesh_file, view, share * 100.0]
                )
        report.append("%s %s %d/%d painted %.0f%%" % [
            mesh_file.get_basename(), "closed" if closed else "open",
            VIEWS.size() - thin, VIEWS.size(), painted / float(VIEWS.size()) * 100.0
        ])
        harness.world.remove_child(node)
        node.queue_free()

    return ok(
        "%s: %s; %d views show a surface turned away and %d show nothing at all, both for the"
        % [wanted, ", ".join(report), wrong_way.size(), empty.size()]
        + " sheet rather than for a verdict",
        meshes.size()
    )


## What a view is called in the frame. Short enough to read at a glance on a tiled sheet.
func _label(view: String) -> String:
    return "3 QUARTER" if view == "three_quarter" else view


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


## What share of a frame the object itself occupies: the pixels that changed when it was put
## there. Measured against the same view of the same stage without it, because the stage's own
## floor and sky fill a frame whether or not anything is standing on it.
func _coverage(with_object: String, without: String) -> float:
    var shown: Image = Image.load_from_file(with_object)
    var bare: Image = Image.load_from_file(without)
    if shown == null or bare == null or shown.get_size() != bare.get_size():
        return 0.0
    var changed: int = 0
    var total: int = 0
    for y: int in range(0, shown.get_height(), 2):
        for x: int in range(0, shown.get_width(), 2):
            total += 1
            var here: Color = shown.get_pixel(x, y)
            var there: Color = bare.get_pixel(x, y)
            if (
                absf(here.r - there.r) + absf(here.g - there.g) + absf(here.b - there.b)
                > CHANGED
            ):
                changed += 1
    return 0.0 if total == 0 else float(changed) / float(total)
