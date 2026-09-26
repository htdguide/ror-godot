extends GateBase
## Driving into the tunnel changes what is lighting the vehicle.
##
## The tunnel exists so that the lighting transition can be tested while moving: outside is one
## directional light plus sky ambient, inside is several local lamps and no sky. This checks
## that the transition is real in both directions — that the sun stops reaching the vehicle
## under the roof, and that the lamps are what is lighting it there.
##
## The frame is measured whole rather than trying to separate the vehicle from its
## surroundings, because inside a tunnel the surroundings are the point: the walls and roof are
## lit by the same lamps and shadowed from the same sun, so their brightness is part of the
## same statement.
##
## The tunnel is a lighting rig and not a structure. The solver collides nodes against the
## terrain and nothing else, so a vehicle drives through the walls; mesh collision is a named
## gap rather than an oversight here.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const PRESET: String = "hero_3q"
const CONVERGE: int = 4
## Under the roof, the sun must be substantially gone.
const MIN_SUN_BLOCKED: float = 0.35
## And the lamps must be a substantial part of what is left.
##
## Not most of it, and the reason is worth recording rather than tuning away: sky ambient in
## Godot is not occluded by geometry without GI, so a vehicle parked under a solid roof still
## receives the whole sky. Measured here, the lamps supply 41% of the light inside the tunnel
## and unoccluded sky supplies the rest. That number is what the GI work in M4 should move, and
## it is the same missing machinery behind a shadowed panel having no bounce light on it.
##
## The bound is set where a tunnel whose lamps had failed entirely — which would read near
## zero — is still caught.
const MIN_LAMP_SHARE: float = 0.25


static func meta() -> Dictionary:
    return {
        "name": "tunnel_lighting_changes",
        "proves": "the tunnel blocks the sun and its lamps light what is inside, so driving through it is a real lighting transition",
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "inside is at least %.0f%% darker than outside with the lamps off; the lamps"
            % (MIN_SUN_BLOCKED * 100.0)
            + " supply at least %.0f%% of the light inside" % (MIN_LAMP_SHARE * 100.0)
        ),
        "why": (
            "a tunnel that does not actually occlude the sun, or whose lamps contribute"
            + " nothing, is scenery rather than a test rig, and every lighting judgement made"
            + " by driving through it would be about the sky instead. Both halves are"
            + " measured so that either failing is distinguishable from the other."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var err: String = harness.setup_for(PRESET)
    if err != "":
        return fail(err)

    var built: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    var vehicle: Node3D = built["root"] as Node3D
    harness.world.add_child(vehicle)
    var tunnel: Node3D = Tunnel.build()
    harness.world.add_child(tunnel)

    # The same view of the vehicle each time, so what changes between captures is the light.
    var bounds: AABB = VehicleBuilder.world_bounds(vehicle)
    var offset: Vector3 = Vector3(0.6, 0.35, 1.0) * bounds.size.length() * 0.9

    var outside: float = await _luma(harness, vehicle, TunnelCfg.CENTRE + Vector3(
        TunnelCfg.LENGTH_M, 0.0, 0.0
    ), offset, "outside")
    var inside: float = await _luma(harness, vehicle, TunnelCfg.CENTRE, offset, "inside")
    _set_lamps(tunnel, false)
    var unlit: float = await _luma(harness, vehicle, TunnelCfg.CENTRE, offset, "inside_dark")
    _set_lamps(tunnel, true)
    if outside <= 0.0:
        return fail("the frame outside the tunnel is black: nothing is lighting the scene")

    # How much of the daylight the roof takes away, measured with the lamps off so that only
    # the occlusion is being read.
    var blocked: float = 1.0 - unlit / outside
    if blocked < MIN_SUN_BLOCKED:
        return fail(
            "with the lamps off, inside the tunnel is %.4f against %.4f outside, only %.0f%%"
            % [unlit, outside, blocked * 100.0]
            + " darker: the roof is not blocking the sky",
            blocked
        )
    var share: float = 1.0 - unlit / maxf(inside, 0.0001)
    if share < MIN_LAMP_SHARE:
        return fail(
            "inside the tunnel is %.4f with the lamps on and %.4f with them off: the lamps"
            % [inside, unlit]
            + " supply only %.0f%% of the light there" % (share * 100.0),
            share
        )
    return ok(
        "outside %.4f, inside %.4f, inside with the lamps off %.4f: the roof removes %.0f%%"
        % [outside, inside, unlit, blocked * 100.0]
        + " of the daylight, the lamps supply %.0f%% of the light inside, and the remaining"
        % (share * 100.0)
        + " %.0f%% is sky ambient the roof does not occlude without GI" % ((1.0 - share) * 100.0),
        blocked
    )


## Mean luminance of the frame with the vehicle at `position`.
func _luma(harness: Node, vehicle: Node3D, position: Vector3, offset: Vector3, tag: String) -> float:
    vehicle.position = position
    harness.camera.look_at_from_position(position + offset, position, Vector3.UP)
    var shot: Dictionary = await harness.capture_shot("tunnel/" + tag, "static", CONVERGE)
    if (shot["error"] as String) != "":
        return 0.0
    var image: Image = Image.load_from_file(shot["png"] as String)
    if image == null:
        return 0.0
    var total: float = 0.0
    # Every eighth pixel in each direction: the measurement is a whole-frame average and
    # sampling it is sixty-four times cheaper without moving the answer.
    var count: int = 0
    for y: int in range(0, image.get_height(), 8):
        for x: int in range(0, image.get_width(), 8):
            total += image.get_pixel(x, y).get_luminance()
            count += 1
    return total / float(maxi(count, 1))


func _set_lamps(tunnel: Node3D, on: bool) -> void:
    for child: Node in tunnel.get_children():
        var light: OmniLight3D = child as OmniLight3D
        if light != null:
            light.visible = on
