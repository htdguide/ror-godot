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
## **A view that is empty is the finding.** Each object is photographed alone on the stage, framed
## from its own bounds, and every view has to contain something. A model visible from the left and
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
## Every view must show something. Low, because this catches an empty frame rather than a poor
## composition: a thin signpost seen edge-on covers very little and is still correct.
const MIN_COVERAGE: float = 0.004


static func meta() -> Dictionary:
    return {
        "name": "object_photoset",
        "proves": "a terrain's most-placed objects are drawn from every side, so a panel that is single-sided or inverted shows as an empty view",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": "each of the %d views of each object covers at least %.1f%% of its frame"
            % [VIEWS.size(), MIN_COVERAGE * 100.0],
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

    var meshes: PackedStringArray = _subjects(terrain)
    if meshes.is_empty():
        return ok("skipped: %s places no object with geometry" % wanted, 0)

    var state: Dictionary = RorObjects.state(terrain)
    var empty: PackedStringArray = PackedStringArray()
    var report: PackedStringArray = PackedStringArray()
    for mesh_file: String in meshes:
        var mesh: ArrayMesh = RorObjects.mesh_of(terrain, mesh_file, state)
        if mesh == null:
            continue
        var node: MeshInstance3D = MeshInstance3D.new()
        node.mesh = mesh
        # The same -90 degree pitch every object is placed with, so the photograph shows the
        # object the way the map does rather than on its side.
        node.transform = RorObjects.transform_of(
            {"position": Vector3.ZERO, "rotation": Vector3.ZERO}, Vector3.ONE
        )
        harness.world.add_child(node)
        var bounds: AABB = node.transform * mesh.get_aabb()
        var thin: int = 0
        for view: String in VIEWS:
            var placement: Dictionary = Photoset.placement(view, bounds, bounds.get_center())
            harness.camera.look_at_from_position(
                placement["pos"] as Vector3, placement["look_at"] as Vector3, Vector3.UP
            )
            var shot: Dictionary = await harness.capture_shot(
                "objectset/%s/%s" % [mesh_file.get_basename(), view], "static", CONVERGE
            )
            if (shot["error"] as String) != "":
                return fail("%s %s: %s" % [mesh_file, view, shot["error"]])
            var coverage: float = _coverage(shot["png"] as String)
            if coverage < MIN_COVERAGE:
                thin += 1
                empty.append("%s from the %s (%.2f%%)" % [mesh_file, view, coverage * 100.0])
        report.append("%s %d/%d" % [mesh_file.get_basename(), VIEWS.size() - thin, VIEWS.size()])
        harness.world.remove_child(node)
        node.queue_free()

    if empty.size() > 0:
        return fail(
            "%d views show nothing at all: %s" % [empty.size(), "; ".join(empty)],
            empty.size()
        )
    return ok(
        "%s: %s, every view of every one of them showing the object"
        % [wanted, ", ".join(report)],
        meshes.size()
    )


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


## What share of a capture is not the background.
func _coverage(path: String) -> float:
    var image: Image = Image.load_from_file(path)
    if image == null:
        return 0.0
    var lit: int = 0
    var total: int = 0
    for y: int in range(0, image.get_height(), 2):
        for x: int in range(0, image.get_width(), 2):
            total += 1
            var pixel: Color = image.get_pixel(x, y)
            if maxf(pixel.r, maxf(pixel.g, pixel.b)) > 0.02:
                lit += 1
    return 0.0 if total == 0 else float(lit) / float(total)
