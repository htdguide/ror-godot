extends GateBase
## Every object a terrain places is photographed from outside, from five directions, and must show
## its front everywhere a surface is nearest the camera.
##
## **This asks a different question from `object_photoset`, and the difference is the whole
## point.** That gate stands the camera on each face group's own authored normal, which settles
## whether the drawn winding agrees with the file. It cannot settle whether the *file* is right:
## when an author wound a wall inward and normalled it inward to match, the camera goes inside the
## building, photographs the front, and passes — while from the street the wall is a hole. That is
## what "four textures of the wall, but there must be something in between and nothing is there"
## looks like from a session window, and `hospital`, `officeblock02`, `store10`, `warehouse01` and
## `policedepartment` all pass the normals gate while showing it.
##
## **The oracle here is the mesh's own bounding box, and no normal is consulted.** Stand outside
## the box, look in, and whatever the depth buffer keeps is the nearest surface along that ray. A
## nearest surface showing its back is a surface you are looking through. That is not a
## convention, a threshold, or an opinion about which way a wall should face.
##
## **Five directions, not six.** The sixth is from underneath, and an object sits on the ground: a
## road slab, a sidewalk and a helipad are each one sheet whose underside is correctly its back,
## and nobody ever stands there. Including it would fail exactly the meshes that are right.
##
## **The control is Godot's own `BoxMesh`**, dressed and measured the same way, for the same
## reason `object_photoset` carries one: a measurement that calls most of a library broken is
## either a serious finding or a broken instrument, and the photograph does not say which. The
## control is also the only thing this gate fails on.
##
## **It reports rather than judges, and that is a decision rather than a shrug.** Three classes of
## content show a back from outside while being exactly right, and each one falsifies the obvious
## bound:
##
## * a road sign is a single card — correct from the front, its own back from behind;
## * `store08.mesh` is two parallel facades with no end walls, so from the end you are correctly
##   seeing the inside of one;
## * `warehouse01.mesh` and `officeblock02.mesh` have no roof, so from above you are correctly
##   looking into the shell.
##
## Nothing in a file separates those from a wall that is genuinely turned round. What does
## separate them is a person looking at the sheet, which is what `tools/mapcheck.sh` assembles,
## and the owner of this project has ruled those three classes correct content. So the number is
## reported and the stills are the product. The gate that carries a verdict about winding is
## `a_reversed_solid_is_caught`, whose oracle is a solid the engine makes itself.

## Which terrain, unless one is named. Every distinct mesh it places is photographed.
##
## `--terrain-dir all` walks the whole library instead, photographing each distinct mesh once
## however many terrains place it. That is the check to run against a map this project has never
## drawn before: the content is what differs between maps, and a map is only as correct as the
## objects it happens to use.
const DEFAULT_TERRAIN: String = "starling-port"
const EVERY_TERRAIN: String = "all"
const VIEWS: Array[String] = ["front", "back", "left", "right", "top"]
const CONVERGE: int = 2
## How much of what a view draws may be marker before the object is a hole from that direction.
##
## Not zero. A surface seen exactly edge-on shows a sliver of its own back through the depth
## buffer, and a building's own window reveals, door recesses and parapet returns are correctly
## back-facing from outside — they are the inside of a hole the author put there.
## Halved when the marker became magenta bars rather than a solid colour: the bars cover half of
## a back-facing surface, so a fully turned-away view now reads 50% where it read 100%, and a
## bound left where it was would have quietly stopped catching things.
const MAX_MARKED_SHARE: float = 0.075
## Below this share of the frame a view has too little of the object in it to carry a verdict.
##
## **A sliver is all marker and means nothing.** Every road sign on Port Starling was reported as
## a hole from the right, and the stills show the sign face correct from one side and its back
## plate correct from the other: the failing view was the post seen edge-on, a few dozen pixels of
## its own edge. A count of pixels cannot tell that from a wall, and a share of the frame can.
const MIN_DRAWN_SHARE: float = 0.02
const LISTED: int = 40


static func meta() -> Dictionary:
    return {
        "name": "an_object_is_not_a_hole_from_outside",
        "proves": (
            "every distinct mesh a terrain places is photographed from outside its own bounding"
            + " box in five directions, with its back faces painted, and how much of each is"
            + " facing away is counted"
        ),
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "the control box shows no back face from outside; what the content shows is counted"
            + " and left for a person"
        ),
        "why": (
            "an author who wound a wall inward and normalled it inward to match passes every"
            + " check against the file's own normals, because the camera goes inside the building"
            + " to take the photograph. From the street the wall is a hole, and a hole renders as"
            + " sky, which is pixel for pixel what correct sky looks like."
        ),
        "budget_s": 1800.0,
        "needs_gpu": true,
        "milestone": "C2",
    }


func run(harness: Node) -> Dictionary:
    var wanted: String = Harness.args.get_string("terrain-dir", DEFAULT_TERRAIN)
    var terrains: Array[RorTerrain] = _terrains(wanted)
    if terrains.is_empty():
        return ok("skipped: no terrain named '%s' in this checkout" % wanted, 0)
    var error: String = harness.setup_for("hero_3q")
    if error != "":
        return fail(error)
    var sun: DirectionalLight3D = harness.world.get_node_or_null(^"Sun") as DirectionalLight3D
    if sun != null:
        sun.shadow_enabled = false

    # And no floor, no sky, no ambient. The stage's checkerboard ground sits at y = 0 and so does
    # a ground-hugging object: `sidewalk.mesh` is a slab whose top face is coplanar with it and
    # the two fight for the depth buffer.
    harness.use_measurement_environment()

    var control: ArrayMesh = ArrayMesh.new()
    control.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().get_mesh_arrays())
    var checked: Dictionary = await _look(harness, control, "control-box.mesh")
    if (checked["error"] as String) != "":
        return fail(checked["error"] as String)
    if (checked["worst"] as float) > MAX_MARKED_SHARE:
        return fail(
            "the control fails: Godot's own BoxMesh is %.0f%% back-facing from outside, so the"
            % ((checked["worst"] as float) * 100.0)
            + " instrument is wrong and nothing it says about content means anything"
        )

    var holes: PackedStringArray = PackedStringArray()
    var meshes: int = 0
    var worst: float = 0.0
    var worst_name: String = ""
    # A mesh is photographed once however many terrains place it: Starling Island's four maps
    # share almost all of theirs, and a second photograph of the same file answers nothing.
    var done: Dictionary = {}
    for terrain: RorTerrain in terrains:
        var state: Dictionary = RorObjects.state(terrain)
        for file: String in _subjects(terrain, state):
            var path: String = RorContentPath.find(file, terrain.directory)
            if done.has(path):
                continue
            done[path] = true
            var mesh: ArrayMesh = RorObjects.mesh_of(terrain, file, state)
            if mesh == null:
                continue
            var seen: Dictionary = await _look(harness, mesh, file)
            if (seen["error"] as String) != "":
                return fail(seen["error"] as String)
            meshes += 1
            var share: float = seen["worst"] as float
            if share > worst:
                worst = share
                worst_name = file
            if share > MAX_MARKED_SHARE:
                holes.append("%s %.0f%% from the %s" % [file, share * 100.0, seen["where"]])

    if meshes == 0:
        return ok("skipped: %s places no object with geometry" % wanted, 0)
    if holes.is_empty():
        return ok(
            "%s: %d object meshes, none more than %.0f%% back-facing from outside (worst %s)"
            % [wanted, meshes, worst * 100.0, worst_name],
            meshes
        )
    return ok(
        "%s: %d of %d object meshes show a back face from outside, for the sheet rather than for"
        % [wanted, holes.size(), meshes]
        + " a verdict: %s" % "; ".join(holes.slice(0, LISTED)),
        holes.size()
    )


## One mesh from five outside directions. Returns `{"error", "worst", "where"}`.
func _look(harness: Node, mesh: ArrayMesh, file: String) -> Dictionary:
    var out: Dictionary = {"error": "", "worst": 0.0, "where": ""}
    var at: Transform3D = RorObjects.transform_of(
        {"position": Vector3.ZERO, "rotation": Vector3.ZERO}, Vector3.ONE
    )
    # A copy, because the facing dress is a diagnostic and the cached mesh is shared with whatever
    # else asks the loader for it.
    var dressed: ArrayMesh = mesh.duplicate() as ArrayMesh
    FacingPaint.apply(dressed)
    var node: MeshInstance3D = MeshInstance3D.new()
    node.mesh = dressed
    node.transform = at
    harness.world.add_child(node)
    var bounds: AABB = at * mesh.get_aabb()
    for view: String in VIEWS:
        var placement: Dictionary = Photoset.placement(view, bounds, bounds.get_center())
        # **Not `Vector3.UP` for every view.** Looking straight down, the up vector is the view
        # direction, `look_at_from_position` has no basis to build, and the camera keeps whatever
        # it was pointing at. Every "from the top" reading in the first run of this gate was taken
        # through that camera, which is why two thirds of a library appeared to be a hole from
        # above while a person driving round the same map saw roofs.
        var ahead: Vector3 = (
            (placement["look_at"] as Vector3) - (placement["pos"] as Vector3)
        ).normalized()
        var up: Vector3 = Vector3.BACK if absf(ahead.dot(Vector3.UP)) > 0.95 else Vector3.UP
        harness.camera.look_at_from_position(
            placement["pos"] as Vector3, placement["look_at"] as Vector3, up
        )
        var stem: String = "outside/%s/%s" % [file.get_basename(), view]
        # The same frame twice, against two backgrounds. What the object drew is identical in
        # both; the background is not. See `FacingPaint.drawn_and_marked`.
        HarnessCapture.use_background(harness.world, Color.BLACK)
        var dark: Dictionary = await harness.capture_shot(stem + "-dark", "static", CONVERGE)
        if (dark["error"] as String) != "":
            out["error"] = "%s %s: %s" % [file, view, dark["error"]]
            break
        HarnessCapture.use_background(harness.world, Color.WHITE)
        var shot: Dictionary = await harness.capture_shot(stem, "static", CONVERGE)
        if (shot["error"] as String) != "":
            out["error"] = "%s %s: %s" % [file, view, shot["error"]]
            break
        var measured: Dictionary = FacingPaint.drawn_and_marked(
            dark["png"] as String, shot["png"] as String
        )
        var drawn: int = measured["drawn"] as int
        if float(drawn) < float(measured["sampled"] as int) * MIN_DRAWN_SHARE:
            continue
        var share: float = float(measured["marked"] as int) / float(drawn)
        if share > (out["worst"] as float):
            out["worst"] = share
            out["where"] = view
        var stamped: String = Stamp.write(shot["png"] as String, view)
        if stamped != "":
            out["error"] = stamped
            break
    harness.world.remove_child(node)
    node.queue_free()
    return out


## The terrains to photograph: the one named, or every one in the library for `all`.
func _terrains(wanted: String) -> Array[RorTerrain]:
    var out: Array[RorTerrain] = []
    var names: PackedStringArray = PackedStringArray([wanted])
    if wanted == EVERY_TERRAIN:
        names = PackedStringArray()
        for summary: Dictionary in RorTerrainLibrary.summaries():
            if (summary["error"] as String) == "":
                names.append(summary["name"] as String)
    for name: String in names:
        var loaded: Dictionary = RorTerrainLibrary.load_named(name)
        if (loaded.get("error", "") as String) == "":
            out.append(loaded["terrain"] as RorTerrain)
    return out


## Every distinct mesh the terrain places, most-placed first, or the one `--object` names.
func _subjects(terrain: RorTerrain, state: Dictionary) -> PackedStringArray:
    var counts: Dictionary = {}
    for placement: Dictionary in RorObjects.placements(terrain):
        var odef: Dictionary = RorObjects.definition(
            terrain, placement["name"] as String, state
        )
        if (odef.get("error", "") as String) != "":
            continue
        for file: String in odef["meshes"] as PackedStringArray:
            counts[file] = (counts.get(file, 0) as int) + 1
    var named: String = Harness.args.get_string("object", "")
    if named != "":
        return PackedStringArray([named] if counts.has(named) else [])
    var names: Array = counts.keys()
    names.sort_custom(func(a: String, b: String) -> bool:
        return (counts[a] as int) > (counts[b] as int)
    )
    var out: PackedStringArray = PackedStringArray()
    for name: String in names:
        out.append(name as String)
    return out
