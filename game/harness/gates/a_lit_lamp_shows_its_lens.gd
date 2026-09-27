extends GateBase
## A lamp that is on looks on: its own lens is brighter than the panel it is mounted in.
##
## `lights_follow_the_controls` checks which lamps are lit, and it checks it in the data: a
## light node is visible and a material's emission has gone up. A session looked at the truck
## with the lights on and reported that the lamps "have a source of light but are not lit up by
## themselves" — the road was lit and the headlight itself was a dark disc.
##
## That is a different claim and it needs a picture: find each lens in the frame, and compare how
## bright it is with the lights on against the same pixels with the lights off.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const PRESET: String = "hero_3q"
const CONVERGE: int = 3
## Dusk, because a lamp in full noon sun is a lamp nobody can see either way — and because it is
## what a session drives in.
const WEATHER: String = "golden_dusk"
## Half the side of the window sampled at each lens, in pixels.
const WINDOW_PX: int = 5
## How much brighter a lit lens has to be than the same pixels when it is off.
const MIN_BRIGHTENING: float = 0.15
## And how bright it has to end up, so "brighter than a dark panel" cannot pass on a dim glow.
const MIN_LIT_LUMA: float = 0.35
## How many lamps have to show, of those the camera can see at all.
const MIN_LAMPS: int = 2


static func meta() -> Dictionary:
    return {
        "name": "a_lit_lamp_shows_its_lens",
        "proves": "a lamp that is switched on is visibly brighter in the rendered frame than the same lamp switched off",
        "builds_on": ["lights_follow_the_controls"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "at least %d lenses brightening by %.2f and reaching %.2f display luma when the"
            % [MIN_LAMPS, MIN_BRIGHTENING, MIN_LIT_LUMA] + " lights are switched on"
        ),
        "why": (
            "a session reported the lamps lighting the road while the lamps themselves stayed"
            + " dark. Every check that existed passed: the light nodes were visible and the"
            + " emission values had changed. Whether a lamp looks lit is a question about"
            + " pixels."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var err: String = harness.setup_for(PRESET, WEATHER)
    if err != "":
        return fail(err)
    clear_fog(harness)
    var built: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    var truck: TruckParser = built["truck"] as TruckParser
    var root: Node3D = built["root"] as Node3D
    harness.world.add_child(root)
    var lamps: Array[Node3D] = built["lamps"] as Array[Node3D]
    if lamps.is_empty():
        return fail("%s built no lamps: there is nothing to light" % TRUCK)
    # From in front and to one side, which is where the lamps that matter are pointing. The
    # preset's own three-quarter view is behind the vehicle and sees only its tail lights.
    var forward: Vector3 = -root.global_transform.basis.z
    var right: Vector3 = root.global_transform.basis.x
    harness.camera.look_at_from_position(
        root.global_position + forward * 7.0 + right * 2.2 + Vector3(0.0, 1.3, 0.0),
        root.global_position + Vector3(0.0, 0.9, 0.0),
        Vector3.UP
    )
    await harness.advance_frames(1, "static", "lamps")

    FlareBuilder.apply_state(lamps, truck, {})
    var dark: Dictionary = await _capture(harness, "dark")
    if (dark["error"] as String) != "":
        return fail(dark["error"] as String)
    FlareBuilder.apply_state(lamps, truck, {"headlights": true, "brake": 1.0})
    var lit: Dictionary = await _capture(harness, "lit")
    if (lit["error"] as String) != "":
        return fail(lit["error"] as String)

    var brightened: PackedStringArray = PackedStringArray()
    var best: float = 0.0
    var seen: int = 0
    for index: int in mini(lamps.size(), truck.flares.size()):
        var lens: Node3D = lamps[index].get_node_or_null(^"Lens") as Node3D
        if lens == null:
            continue
        var at: Vector2 = harness.camera.unproject_position(lens.global_position)
        if not _inside(at, (lit["image"] as Image).get_size()):
            continue
        # Behind the vehicle is still "inside the frame": only lamps the camera can actually
        # see are being asked about, which is what facing the camera means. The direction is
        # the lamp's own — the holder's -Z — rather than the lens quad's, which is turned round
        # to show its face to the world.
        var facing: Vector3 = -lamps[index].global_transform.basis.z
        if facing.dot(harness.camera.global_position - lens.global_position) <= 0.0:
            continue
        seen += 1
        var was: float = _window(dark["image"] as Image, at)
        var now: float = _window(lit["image"] as Image, at)
        best = maxf(best, now - was)
        if now - was >= MIN_BRIGHTENING and now >= MIN_LIT_LUMA:
            brightened.append("%s %.2f→%.2f" % [truck.flares[index]["type"], was, now])
    if seen == 0:
        return fail("no lamp faces the camera in this view, so nothing could be measured")
    if brightened.size() < MIN_LAMPS:
        return fail(
            "%d of %d lamps facing the camera got visibly brighter when switched on; the best"
            % [brightened.size(), seen]
            + " gained %.3f, under %.2f. See %s" % [best, MIN_BRIGHTENING, lit["png"]],
            best
        )
    return ok(
        "%d of %d lamps facing the camera light up: %s"
        % [brightened.size(), seen, ", ".join(brightened)],
        best
    )


func _capture(harness: Node, tag: String) -> Dictionary:
    var shot: Dictionary = await harness.capture_shot("lamps/%s" % tag, "static", CONVERGE)
    if (shot["error"] as String) != "":
        return {"error": shot["error"] as String, "image": null, "png": ""}
    var image: Image = Image.load_from_file(shot["png"] as String)
    if image == null:
        return {
            "error": "the capture at %s could not be read" % shot["png"],
            "image": null, "png": shot["png"],
        }
    return {"error": "", "image": image, "png": shot["png"]}


func _inside(at: Vector2, size: Vector2i) -> bool:
    return (
        at.x >= float(WINDOW_PX) and at.y >= float(WINDOW_PX)
        and at.x < float(size.x - WINDOW_PX) and at.y < float(size.y - WINDOW_PX)
    )


## The brightest pixel in a small window, rather than the average: a lens is a few pixels across
## at this distance and an average over its surroundings is an average over the bodywork.
func _window(image: Image, centre: Vector2) -> float:
    var best: float = 0.0
    for y: int in range(int(centre.y) - WINDOW_PX, int(centre.y) + WINDOW_PX + 1):
        for x: int in range(int(centre.x) - WINDOW_PX, int(centre.x) + WINDOW_PX + 1):
            var colour: Color = image.get_pixel(x, y)
            best = maxf(best, colour.r * 0.2126 + colour.g * 0.7152 + colour.b * 0.0722)
    return best
