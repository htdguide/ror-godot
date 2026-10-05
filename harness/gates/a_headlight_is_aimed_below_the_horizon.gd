extends GateBase
## A forward lamp points at the road, whatever the body it is bolted to is doing.
##
## **A headlight is aimed at the ground and a vehicle is not a fixed thing.** A lamp's own frame is
## the bodywork's — upstream gives each flare three nodes and this project takes the normal of
## that triad — so the beam pitches with the chassis. A truck that squats under power lifts its
## beams into the sky: measured with the body nosed up six degrees, the two beams pointed 0.027
## and 0.003 *above* the horizon and the road ahead read 0.0018 where level it read 0.264.
## Reported from a window as "the light is directed partially to the air, and when I throttle it
## is even worse — the light doesn't even touch the ground".
##
## Every car sold with a headlight answers this somehow, from a thumbwheel on the dash to
## automatic levelling that reads the axle. `HeadBeam.level` is the automatic kind: the lamp keeps
## the direction it is pointed in, its own toe-out included, and takes its pitch from the aim
## rather than from the body. So the claim is about the beam and not about the bodywork: at any
## attitude a vehicle can be in, a forward lamp sits a little below the horizon — far enough to
## reach the road, not so far that it lights the bumper.
##
## The rendered half of this is a floor and says so: the road in front of the vehicle has to be
## lit at all. Which way up the beam *pattern* lands is held by
## `a_headlight_lights_the_road_at_night` instead, where a main beam has to out-throw a low one —
## turning the pattern over makes the low beam the brighter of the two, which is a cut-off that
## has stopped cutting anything off.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
## The attitudes the body is put through, in degrees of pitch: squatting under power, diving
## under brakes, and level.
const PITCHES: Array[float] = [-8.0, -4.0, 0.0, 4.0, 8.0]
## How far below the horizon a beam has to sit, as an angle. Under this it is lighting the
## horizon rather than the road; over it, it is lighting the bumper.
const MIN_DROP_DEG: float = 0.5
const MAX_DROP_DEG: float = 3.5
## And how bright the road just ahead of the vehicle has to be at night with the lamps on, which
## is what the pattern being the right way up buys.
const MIN_NEAR_ROAD: float = 0.15
const CONVERGE: int = 8


static func meta() -> Dictionary:
    return {
        "name": "a_headlight_is_aimed_below_the_horizon",
        "proves": (
            "every forward lamp of the hero vehicle points between half a degree and three and a"
            + " half below the horizon at any body pitch, and lights the road in front of it"
        ),
        "builds_on": ["a_headlight_lights_the_road_at_night"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "each beam's own direction between %.1f and %.1f degrees below horizontal across"
            % [MIN_DROP_DEG, MAX_DROP_DEG] + " pitches from -8 to +8, and the near road over"
            + " %.2f luminance with the lamps lit" % MIN_NEAR_ROAD
        ),
        "why": (
            "a lamp bolted to bodywork pitches with it, so a vehicle that squats under power"
            + " lifts its beams off the road — measured at 0.027 above the horizon nosed up six"
            + " degrees, with the road ahead at 0.0018 against 0.264 level."
        ),
        "budget_s": 180.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var error: String = harness.setup_for("hero_3q", "night_moon")
    if error != "":
        return fail(error)
    var built: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    var truck: TruckParser = built["truck"] as TruckParser
    var root: Node3D = built["root"] as Node3D
    harness.world.add_child(root)
    var lamps: Array[Node3D] = built["lamps"] as Array[Node3D]
    FlareBuilder.apply_state(lamps, truck, {"headlights": true})
    var beams: Array[SpotLight3D] = []
    for lamp: Node3D in lamps:
        var beam: SpotLight3D = lamp.get_node_or_null(^"Beam") as SpotLight3D
        if beam != null:
            beams.append(beam)
    if beams.is_empty():
        return fail("%s built no forward beam to aim" % TRUCK)

    var worst: float = 0.0
    var reported: PackedStringArray = PackedStringArray()
    for pitch: float in PITCHES:
        # The body pitched about its own lateral axis, nodes and frame together, which is what
        # the solver hands over when a vehicle squats or dives.
        var turned: PackedVector3Array = _pitched(truck.nodes, pitch)
        # The frame the solver would hand over for those nodes, which is how the window drives
        # this: `ActorFrame.of` is what `VehicleBuilder` built the lamps against.
        var actor: Transform3D = ActorFrame.of(turned, truck.camera_nodes)
        FlareBuilder.apply_pose(lamps, truck, turned, actor)
        for beam: SpotLight3D in beams:
            var facing: Vector3 = -beam.global_transform.basis.z
            var drop: float = rad_to_deg(asin(clampf(-facing.y, -1.0, 1.0)))
            worst = maxf(worst, absf(drop - (MIN_DROP_DEG + MAX_DROP_DEG) * 0.5))
            if drop < MIN_DROP_DEG or drop > MAX_DROP_DEG:
                return fail(
                    "nosed %+.0f degrees, a beam points %.2f degrees %s the horizon"
                    % [pitch, absf(drop), "below" if drop > 0.0 else "above"]
                    + ", outside the %.1f to %.1f it is aimed at"
                    % [MIN_DROP_DEG, MAX_DROP_DEG],
                    drop
                )
        reported.append("%+.0f deg" % pitch)

    # And it reaches the road: the pattern upside down lights the sky instead.
    FlareBuilder.apply_pose(
        lamps, truck, truck.nodes, ActorFrame.of(truck.nodes, truck.camera_nodes)
    )
    # Behind the vehicle and above it, looking the way it faces: the beam's pool is then the
    # middle of the frame and the vehicle is at the bottom of it.
    var at: Vector3 = Vector3(9.0, 5.0, 0.0)
    harness.camera.look_at_from_position(at, Vector3(-32.0, 0.0, 0.0), Vector3.UP)
    var shot: Dictionary = await harness.capture_shot("beam/aimed", "static", CONVERGE)
    if (shot["error"] as String) != "":
        return fail(shot["error"] as String)
    var near: float = _patch(shot["png"] as String, 0.35, 0.65, 0.55, 0.85)
    if near < MIN_NEAR_ROAD:
        return fail(
            "the road in front of the vehicle reads %.4f with the lamps lit, under the %.2f"
            % [near, MIN_NEAR_ROAD] + " a lit road should be: the beam pattern is upside down",
            near
        )
    return ok(
        "%d forward beams held between %.1f and %.1f degrees below the horizon at %s, and the"
        % [beams.size(), MIN_DROP_DEG, MAX_DROP_DEG, ", ".join(reported)]
        + " road in front reads %.4f" % near,
        near
    )


## The rig's own nodes, pitched about the middle of it.
func _pitched(nodes: PackedVector3Array, degrees: float) -> PackedVector3Array:
    var centre: Vector3 = Vector3.ZERO
    for at: int in nodes.size():
        centre += nodes[at]
    if nodes.size() > 0:
        centre /= float(nodes.size())
    var turn: Basis = Basis(Vector3.BACK, deg_to_rad(degrees))
    var out: PackedVector3Array = PackedVector3Array()
    for at: int in nodes.size():
        out.append(centre + turn * (nodes[at] - centre))
    return out


func _patch(png: String, u0: float, u1: float, v0: float, v1: float) -> float:
    var image: Image = Image.load_from_file(png)
    if image == null:
        return 0.0
    var total: float = 0.0
    var count: int = 0
    for y: int in range(int(image.get_height() * v0), int(image.get_height() * v1), 3):
        for x: int in range(int(image.get_width() * u0), int(image.get_width() * u1), 3):
            var pixel: Color = image.get_pixel(x, y)
            total += pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
            count += 1
    return 0.0 if count == 0 else total / float(count)
