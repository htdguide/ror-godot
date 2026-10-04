extends GateBase
## With the lights on at night, the road ahead of the vehicle is lit; with them off, it is not.
##
## **Reported from a window as "during the night headlights are not working".** Three separate
## faults, each of which hid the next:
##
## 1. **There was no night.** Every weather preset was a daylight one, and under physical light
##    units an hour states its light in lux — so it has to state the exposure that light was
##    metered for. A camera set for a hundred thousand lux of midday sun sees nothing at all by a
##    quarter-lux moon, and no lamp can reach it: a 22,000 cd low beam is about fifty lux on the
##    road at twenty metres, a two-thousandth of what the day exposure expects.
## 2. **The small lamps were ceiling fittings.** Godot takes an omni's output in lumens and
##    defaults it to a thousand; a tail light is about twelve. Ten of them on the bodywork lit the
##    whole vehicle like a showroom the moment the switch went on.
## 3. **A light projector needs its light to cast a shadow.** The beam pattern — the cut-off, the
##    hot spot, the kerb-side step — is a texture the lamp is seen through, and with shadows off
##    the projector is never sampled and the lamp emits nothing. Measured: the road ahead read
##    0.2150 with the beams on and 0.2150 with them off, the same frame to four decimals.
##
## **The oracle is the same frame without the lamps**, taken in the same run on the same terrain
## from the same camera. An absolute brightness would be a number somebody chose; the ratio
## between a road with headlights on it and the same road without is the claim.
##
## A real terrain rather than the blockout stage, because the blockout ground is a near-white
## checker and a moonlit white checker is brighter than a headlit road — the contrast this
## measures would be the stage's albedo rather than the lamps.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const MAP: String = "lapaz"
const HOUR: String = "night_moon"
## How dark the road has to be with the lamps off. The moon is a quarter of a lux and asphalt
## keeps a tenth of what lands on it, so this is generous.
const MAX_DARK: float = 0.02
## How much brighter the low beam has to make it, and how much more the main beam again.
## Measured at 354 times and 3.3; these are a long way under both.
const MIN_LIT_RATIO: float = 20.0
const MIN_MAIN_RATIO: float = 1.3
## And an absolute floor, so that a scene which is dark everywhere cannot pass on a ratio.
const MIN_LIT: float = 0.05
const CONVERGE: int = 8
## The patch of the frame the road ahead of the vehicle lands in, and the patch beside it.
const ROAD: Array[float] = [0.35, 0.65, 0.45, 0.85]


static func meta() -> Dictionary:
    return {
        "name": "a_headlight_lights_the_road_at_night",
        "proves": (
            "under the night preset the road ahead of the hero vehicle is dark with the lights"
            + " off, lit with the low beam, and brighter again with the main beam"
        ),
        "builds_on": ["lights_follow_the_controls"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "the road under 0.02 luminance unlit, at least 20 times that and at least 0.05 on"
            + " low beam, and at least 1.3 times the low beam on main"
        ),
        "why": (
            "a headlight that throws no light is invisible in daylight and is the whole of the"
            + " picture at night. Three separate faults each hid the next — no night exposure,"
            + " bulb-sized lamps at a thousand lumens, and a beam projector on a light with no"
            + " shadow map, which emits nothing at all."
        ),
        "budget_s": 180.0,
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
    var error: String = harness.setup_for("hero_3q", HOUR)
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
    harness.world.add_child(root)
    var start: Vector3 = terrain.start_position()
    root.position = start + Vector3(0.0, 0.6, 0.0)
    var lamps: Array[Node3D] = built["lamps"] as Array[Node3D]
    var beams: int = 0
    for lamp: Node3D in lamps:
        if lamp.get_node_or_null(^"Beam") != null:
            beams += 1
    if beams == 0:
        return fail("%s built no forward beam: there is nothing to light the road with" % TRUCK)
    # Above and behind, looking the way the vehicle faces, so the road it is lighting is the
    # middle of the frame and the vehicle itself is not.
    var at: Vector3 = start + Vector3(10.0, 7.0, 0.0)
    harness.camera.look_at_from_position(at, start + Vector3(-30.0, 0.0, 0.0), Vector3.UP)
    var road: Dictionary = {}
    for lit: String in ["off", "low", "main"]:
        FlareBuilder.apply_state(lamps, truck, {
            "headlights": lit != "off", "high_beam": lit == "main",
        })
        var shot: Dictionary = await harness.capture_shot(
            "night/%s-%s" % [MAP, lit], "static", CONVERGE
        )
        if (shot["error"] as String) != "":
            return fail(shot["error"] as String)
        road[lit] = _patch(shot["png"] as String)

    var dark: float = road["off"] as float
    var low: float = road["low"] as float
    var main: float = road["main"] as float
    if dark > MAX_DARK:
        return fail(
            "the road reads %.4f with every lamp off, over the %.2f a moonlit road should be:"
            % [dark, MAX_DARK] + " something other than the headlights is lighting it",
            dark
        )
    if low < MIN_LIT or low < dark * MIN_LIT_RATIO:
        return fail(
            "the low beam takes the road from %.4f to %.4f: %.1f times, against the %.0f and the"
            % [dark, low, low / maxf(dark, 0.00001), MIN_LIT_RATIO]
            + " %.2f floor both required. The lamps are on and the road is not lit" % MIN_LIT,
            low
        )
    if main < low * MIN_MAIN_RATIO:
        return fail(
            "the main beam reads %.4f against the low beam's %.4f, which is %.2f times and not"
            % [main, low, main / maxf(low, 0.00001)]
            + " the %.1f required: the two are the same beam" % MIN_MAIN_RATIO,
            main
        )
    return ok(
        "%d forward beams: the road ahead reads %.4f unlit, %.4f on low beam (%.0f times) and"
        % [beams, dark, low, low / maxf(dark, 0.00001)]
        + " %.4f on main (%.1f times the low)" % [main, main / maxf(low, 0.00001)],
        low
    )


## How bright the road ahead is in one frame.
func _patch(png: String) -> float:
    var image: Image = Image.load_from_file(png)
    if image == null:
        return 0.0
    var total: float = 0.0
    var count: int = 0
    for y: int in range(int(image.get_height() * ROAD[2]), int(image.get_height() * ROAD[3]), 3):
        for x: int in range(int(image.get_width() * ROAD[0]), int(image.get_width() * ROAD[1]), 3):
            var pixel: Color = image.get_pixel(x, y)
            total += pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
            count += 1
    return 0.0 if count == 0 else total / float(count)
