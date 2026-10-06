extends GateBase
## Standing on a terrain, the ground reaches the horizon and the terrain's own backdrop is inside
## the view.
##
## **A terrain is smaller than its own horizon.** La Paz is 4 km across and the painted mountain
## ring it ships stands at 10,070 m, so there are six kilometres between the edge of the ground and
## the foot of the mountains with nothing in them. Looking across that gap the camera is below the
## horizon and sees the sky, which draws a band of flat colour between the ground and the
## backdrop — reported from a window as a grey line along the horizon. It is a hole rather than a
## line, and it had two causes at once: the far plane stopped at 6 km, so the backdrop was clipped
## away entirely, and nothing was drawn past the terrain's own edge.
##
## So the claim is in two halves, one measured off the files and one off a frame.
##
## **The files**: every terrain in the library places things further out than its own ground, and
## the camera has to reach the furthest of them. **The frame**: from a terrain's own spawn, looking
## level, what is below the horizon is the world rather than the sky. The second is photographed
## against the same frame with the world hidden, because a hazed distance and the sky it fades into
## are the same colour by design — what separates them is that one of them is there.

const MAP: String = "lapaz"
const PRESET: String = "hero_3q"
const CONVERGE: int = 4
## Which way to look. Four quarters from the spawn, because a map's edge is in one direction and
## not another: the fault showed on one side of the road and not on the other.
const YAWS: Array[float] = [0.0, 90.0, 180.0, 270.0]
## How much of the band below the horizon has to be something other than sky, and how far below
## the horizon that band is measured. Close in, because that is where the gap opens: a hole at the
## horizon is a few degrees tall and the ground under the camera is never in doubt.
const BAND_FROM: float = 0.52
const BAND_TO: float = 0.60
const MUST_BE_COVERED: float = 0.98
## How far a pixel has to move between the two frames to be something rather than sky.
const SHOWS_AS: float = 0.02


static func meta() -> Dictionary:
    return {
        "name": "a_terrain_reaches_its_own_horizon",
        "proves": "a terrain's own backdrop is inside the view distance, and what lies below the horizon from its spawn is the world rather than the sky",
        "builds_on": ["a_backdrop_keeps_the_fog_its_material_states"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "every terrain's furthest placement within the view distance, and %.0f%% of the band"
            % (MUST_BE_COVERED * 100.0) + " below the horizon covered by the world"
        ),
        "why": (
            "a terrain is smaller than its own horizon — La Paz is 4 km across and its backdrop"
            + " ring stands at 10,070 m — so a far plane that does not reach the ring clips it"
            + " away, and a world that stops at the terrain's edge leaves the sky showing under"
            + " the horizon. Both were live, and together they read as a grey line along the"
            + " horizon."
        ),
        "budget_s": 180.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var reported: PackedStringArray = PackedStringArray()
    var loaded: Dictionary = RorTerrainLibrary.load_named(MAP)
    if (loaded.get("error", "") as String) != "":
        return ok("skipped: %s is not in this checkout" % MAP, 0)
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain
    var err: String = harness.setup_for(PRESET, "noon_clear")
    if err != "":
        return fail(err)
    var ground: Node3D = TerrainWorld.create()
    if ground == null:
        return ok("skipped: Terrain3D is not installed", 0)
    harness.world.add_child(ground)
    await harness.advance_frames(2, "static", "terrain")
    var built: String = harness.terrain.populate(ground, terrain)
    if built != "":
        return fail(built)
    var blockout: Node3D = harness.world.get_node_or_null(^"Ground") as Node3D
    if blockout != null:
        blockout.visible = false
    var objects: Node3D = RorObjects.build(terrain)
    harness.world.add_child(objects)
    var at: Vector3 = terrain.start_position() + Vector3(0.0, 2.0, 0.0)

    # **The backdrop is a placement near the middle of the map and a mesh ten kilometres wide**, so
    # what the camera has to reach is the furthest corner of what a terrain *draws* and not the
    # furthest point it places: La Paz's furthest placement is 3,877 m from its spawn and its
    # horizon ring stands at 10,070.
    var reach: float = _furthest_drawn(objects, at)
    if reach > RenderCfg.VIEW_DISTANCE_M:
        return fail(
            "%s draws something %.0f m from its own spawn and the camera reaches %.0f m: the"
            % [MAP, reach, RenderCfg.VIEW_DISTANCE_M] + " terrain's own backdrop is clipped away",
            reach
        )
    reported.append(
        "%s draws out to %.0f m, inside a %.0f m view"
        % [MAP, reach, RenderCfg.VIEW_DISTANCE_M]
    )

    var worst: float = 1.0
    var worst_yaw: float = 0.0
    for yaw: float in YAWS:
        var toward: Vector3 = Vector3(cos(deg_to_rad(yaw)), 0.0, sin(deg_to_rad(yaw)))
        harness.camera.look_at_from_position(at, at + toward, Vector3.UP)
        var world: Dictionary = await _capture(harness, "yaw%d_world" % int(yaw))
        if (world["error"] as String) != "":
            return fail(world["error"] as String)
        ground.visible = false
        objects.visible = false
        var sky: Dictionary = await _capture(harness, "yaw%d_sky" % int(yaw))
        ground.visible = true
        objects.visible = true
        if (sky["error"] as String) != "":
            return fail(sky["error"] as String)
        var covered: float = _covered(world["image"] as Image, sky["image"] as Image)
        if covered < worst:
            worst = covered
            worst_yaw = yaw
    if worst < MUST_BE_COVERED:
        return fail(
            "looking %.0f degrees from the spawn, %.1f%% of the band below the horizon is the"
            % [worst_yaw, worst * 100.0]
            + " world and the rest is sky: the ground does not reach the horizon",
            worst
        )
    reported.append("%.1f%% of the band below the horizon is world, worst of four" % (worst * 100.0))
    return ok("; ".join(reported), worst)


## How far from a point the furthest drawn surface of a built scene stands, on the ground plane.
##
## The distance to a thing's middle plus its own half-width, rather than the corner of a box around
## it. A backdrop is a ring centred on the map, and the corner of an axis-aligned box around a ring
## is 1.41 times its radius out in a direction the ring does not go — measured on La Paz, 17,012 m
## for a horizon that stands at 10,070.
func _furthest_drawn(root: Node3D, from: Vector3) -> float:
    var furthest: float = 0.0
    for node: Node in _descendants(root):
        var instance: VisualInstance3D = node as VisualInstance3D
        if instance == null:
            continue
        var box: AABB = instance.global_transform * instance.get_aabb()
        var centre: Vector3 = box.get_center()
        furthest = maxf(
            furthest,
            Vector2(centre.x - from.x, centre.z - from.z).length()
            + maxf(box.size.x, box.size.z) * 0.5
        )
    return furthest


func _descendants(node: Node) -> Array[Node]:
    var out: Array[Node] = [node]
    for child: Node in node.get_children():
        out.append_array(_descendants(child))
    return out


## What share of the band below the horizon is something other than the sky behind it.
func _covered(world: Image, sky: Image) -> float:
    var size: Vector2i = world.get_size()
    var counted: int = 0
    var covered: int = 0
    for y: int in range(int(size.y * BAND_FROM), int(size.y * BAND_TO), 2):
        for x: int in range(0, size.x, 4):
            var a: Color = world.get_pixel(x, y)
            var b: Color = sky.get_pixel(x, y)
            counted += 1
            if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > SHOWS_AS:
                covered += 1
    return float(covered) / maxf(float(counted), 1.0)


func _capture(harness: Node, tag: String) -> Dictionary:
    var shot: Dictionary = await harness.capture_shot("horizon/%s" % tag, "static", CONVERGE)
    if (shot["error"] as String) != "":
        return {"error": shot["error"] as String, "image": null}
    var image: Image = Image.load_from_file(shot["png"] as String)
    if image == null:
        return {"error": "the capture at %s could not be read" % shot["png"], "image": null}
    return {"error": "", "image": image}
