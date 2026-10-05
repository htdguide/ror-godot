extends GateBase
## A surface the bodywork encloses is lit less than one facing the sky.
##
## **Light arrives from every direction and geometry does not.** The floor of a truck bed has the
## bed's own sides and the cab standing between it and most of the sky, and a renderer that does
## not account for that lights it as brightly as the roof above it. Measured at a quarter past six
## in the evening: the bed read 0.0626 and the roof 0.0671 — 93% — on a road reading 0.024.
## Reported from a window as the moon shining through the truck and landing in its bed, with the
## session asking whether the term was ambient occlusion.
##
## **It is, and it is not the whole of it.** Godot's screen-space ambient occlusion darkens the
## ambient term, which is the right tool and reached a hundredth of this: at twelve times its own
## strength the bed moved from 0.0343 to 0.0320. What was actually lighting the bed was
## *reflection* — the sky's own radiance and, above all, the vehicle's reflection probe, which is
## one cubemap taken from the middle of the vehicle and applied to everything inside its box
## whatever is in the way. Turning the probe off took the bed to 0.0305 while the roof stayed at
## 0.0616, which is the shape of the fault in two numbers.
##
## So the claim is a ratio and not a brightness: whatever an hour is worth, the part of a vehicle
## that cannot see the sky must take less of it than the part that can, and the darker the hour
## the less it may take. A night where the two are equal is a night where the bodywork is not
## blocking anything.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const MAP: String = "lapaz"
## The hours this is held at, and how much of the open roof's light the enclosed bed may have at
## each. Dusk measured 0.75 and the small hours 0.36; before the probe followed the hour, dusk
## was 0.93.
const HOURS: Array[float] = [18.25, 21.0]
const MOST_OF_THE_ROOF: Array[float] = [0.85, 0.6]
## Below this the frame is too dark to divide one number by another and mean anything.
const MIN_ROOF: float = 0.002
const CONVERGE: int = 8


static func meta() -> Dictionary:
    return {
        "name": "an_enclosed_part_is_darker_than_the_sky_it_cannot_see",
        "proves": (
            "the floor of the hero vehicle's bed is lit less than its roof at dusk and less again"
            + " in the small hours, so that a surface the bodywork encloses does not take the"
            + " light of one facing the sky"
        ),
        "builds_on": ["a_vehicle_photoset_through_the_day"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "the bed floor at most 85%% of the roof at 18:15 and at most 60%% of it at 21:00"
        ),
        "why": (
            "a reflection probe is one cubemap from the middle of a vehicle and is applied to"
            + " every surface inside its box, so an enclosed floor reflects a sky that the sides"
            + " standing around it block. At 93% of the roof's light it reads as the moon"
            + " shining through the bodywork."
        ),
        "budget_s": 240.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var loaded: Dictionary = RorTerrainLibrary.load_named(MAP)
    if (loaded.get("error", "") as String) != "":
        return ok("skipped: %s" % loaded["error"], 0)
    var terrain: RorTerrain = loaded["terrain"] as RorTerrain
    var error: String = harness.setup_for("hero_3q", "noon_clear")
    if error != "":
        return fail(error)
    var ground: Node3D = TerrainWorld.create()
    if ground == null:
        return ok("skipped: Terrain3D is not installed", 0)
    harness.world.add_child(ground)
    await harness.advance_frames(2, "static", "terrain")
    var built_error: String = harness.terrain.populate(ground, terrain)
    if built_error != "":
        return fail(built_error)
    var blockout: Node3D = harness.world.get_node_or_null(^"Ground") as Node3D
    if blockout != null:
        blockout.visible = false
    var built: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    var truck: TruckParser = built["truck"] as TruckParser
    var root: Node3D = built["root"] as Node3D
    var start: Vector3 = terrain.start_position()
    root.position = start + Vector3(0.0, 0.6, 0.0)
    harness.world.add_child(root)
    var bounds: AABB = ActorProbe.local_bounds(root)
    bounds.position += root.position
    var centre: Vector3 = bounds.get_center()
    # Behind and above, looking down into the bed: a session's own chase view, and the one the
    # fault was reported from.
    var at: Vector3 = centre + Vector3(5.2, 2.3, 0.0)
    harness.camera.look_at_from_position(at, centre + Vector3(0.0, -0.1, 0.0), Vector3.UP)

    var rows: PackedStringArray = PackedStringArray()
    for index: int in HOURS.size():
        var hour: float = HOURS[index]
        var sky: Dictionary = DayCycle.at(hour)
        BlockoutWorld.apply_weather(harness.world, sky, RenderCfg.CLOUDS_ENABLED)
        PhysicalCamera.reexpose(harness.camera, CameraCfg.get_preset("hero_3q"), sky)
        ActorProbe.recapture(root, float(sky.get("probe_intensity", ActorProbe.INTENSITY)))
        # Lights on, because a driver's would be, and because the lamps are the one thing that
        # is allowed to light what the sky cannot reach.
        FlareBuilder.apply_state(built["lamps"] as Array[Node3D], truck, {"headlights": true})
        var shot: Dictionary = await harness.capture_shot(
            "enclosed/%04d" % int(hour * 100.0), "static", CONVERGE
        )
        if (shot["error"] as String) != "":
            return fail(shot["error"] as String)
        var image: Image = Image.load_from_file(shot["png"] as String)
        var bed: float = _patch(image, 0.42, 0.58, 0.52, 0.66)
        var roof: float = _patch(image, 0.44, 0.56, 0.34, 0.42)
        if roof < MIN_ROOF:
            return fail(
                "at %05.2f the roof itself reads %.4f, too dark to compare anything with"
                % [hour, roof], roof
            )
        var share: float = bed / roof
        rows.append("%05.2f bed %.4f roof %.4f (%.0f%%)" % [hour, bed, roof, share * 100.0])
        if share > MOST_OF_THE_ROOF[index]:
            return fail(
                "at %05.2f the enclosed bed reads %.4f against a roof of %.4f, which is %.0f%%"
                % [hour, bed, roof, share * 100.0]
                + " of it and over the %.0f%% allowed: the bodywork is not blocking the sky"
                % (MOST_OF_THE_ROOF[index] * 100.0),
                share
            )
    return ok("; ".join(rows), 0)


## How bright one patch of the frame is.
func _patch(image: Image, u0: float, u1: float, v0: float, v1: float) -> float:
    var total: float = 0.0
    var count: int = 0
    for y: int in range(int(image.get_height() * v0), int(image.get_height() * v1), 2):
        for x: int in range(int(image.get_width() * u0), int(image.get_width() * u1), 2):
            var pixel: Color = image.get_pixel(x, y)
            total += pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
            count += 1
    return 0.0 if count == 0 else total / float(count)
