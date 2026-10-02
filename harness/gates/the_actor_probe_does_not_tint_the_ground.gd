extends GateBase
## The ground inside the vehicle's reflection probe is lit like the ground outside it.
##
## **Reported from the window, twice, before any gate could see it:** a hard-edged rectangle
## around the truck where the scene's colour does not apply. At dusk the whole map goes blue and
## that box stays warm; at night it reads nearly black against a blue road. It follows the
## vehicle, it is axis-aligned with the world rather than with the road, and it survives turning
## the sun and every shadow off — which is what rules out shadows and points at a volume.
##
## The volume is `ActorProbe`'s `ReflectionProbe`. Godot applies a probe to **everything** whose
## geometry falls inside its box, not only to the object it was added for, so a probe sized to the
## vehicle plus a margin also claims the road under it. With `UPDATE_ONCE` the capture is taken
## when the vehicle is built and never again, so the enclosed ground keeps reflecting whatever the
## world looked like at that moment while the sky outside the box moves on.
##
## Measured off the reported screenshot before any code changed: road outside the box sat at
## R-B -25 to -39, road inside it at -7.0 and +9.6. The blue stops at the box edge.
##
## **What this gate asserts is a comparison, not a colour.** It does not say what the road should
## look like — that is the renderer's business and a weather preset's. It says the road a metre
## inside the box and the road a metre outside it must look the same, because nothing physical
## about a vehicle changes the colour of the tarmac in a rectangle around it. That makes the
## oracle an invariant and leaves the art alone.
##
## **The order matters, and getting it wrong made this gate pass over a live bug.** A first
## version built the vehicle and measured under one unchanging light; probe and frame agreed, it
## reported 6.3% and went green while the fault was plainly visible on screen. The fault is not
## that a probe exists, it is that its capture goes *stale*: the window reproduces it by cycling
## the weather with F2, which relights the world and leaves the probe holding the world it was
## built in. So this gate does the same — build under daylight, let the probe take its one
## capture, then relight — because a frozen capture is only wrong once something changes.
##
## The sun and the fill are switched off after the capture, so the only light left is ambient.
## That is deliberate: direct light swamps the difference, which is exactly why the rectangle is
## invisible in bright sun and obvious at dusk, and why measuring a sunlit frame finds nothing.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const PRESET: String = "hero_3q"
const WEATHER: String = "noon_clear"
const CONVERGE: int = 4
## Where the road is sampled, as distances sideways from the vehicle's centre in metres.
##
## **Fixed world positions, not positions derived from the probe's own box.** A first version
## sampled a metre inside and a metre outside the box's face, which tied the measurement to the
## thing under test: shrinking the box moved both probes, and a sweep of box sizes produced
## 64.6%, 257.4% and 217.0% because each run was reading a different piece of road. A gate whose
## ruler moves with the subject measures nothing.
##
## These span from beside the vehicle to well clear of it, all on open road at much the same
## distance from the camera, so fog and falloff land on every sample equally.
const SAMPLES_M: Array[float] = [2.5, 3.5, 4.5, 5.5, 6.5, 7.5]
## The blockout world's ground plane.
const GROUND_Y: float = 0.0
## The stand-in road: one albedo, and rough the way tarmac is.
const ROAD_SIZE_M: float = 64.0
const ROAD_ALBEDO: Color = Color(0.25, 0.25, 0.25)
const ROAD_ROUGHNESS: float = 0.85
## Frames allowed for the probe's one capture before the world is relit.
const CAPTURE_FRAMES: int = 4
## The night this relights to: a blue ambient, which is what makes the stale rectangle obvious in
## the window. Its exact colour does not matter — the gate compares two patches of the same road
## under the same sky, never a patch against a stated colour.
const NIGHT_AMBIENT: Color = Color(0.25, 0.35, 0.7)
const NIGHT_AMBIENT_ENERGY: float = 1.0
## Where the measuring camera stands: high enough and far enough back to hold the road on both
## sides of the probe's edge in one frame.
const CAMERA_HEIGHT_M: float = 9.0
const CAMERA_BACK_M: float = 17.0
## Half the side of the sampled window, in pixels.
const WINDOW_PX: int = 12
## How far apart the two readings may sit, as a share of the outside reading's own magnitude.
## Generous: the fault being caught moved the colour difference by thirty to fifty levels out of
## 255, and a tolerance this wide still catches a tenth of that.
const MAX_DIFFERENCE: float = 0.15


static func meta() -> Dictionary:
    return {
        "name": "the_actor_probe_does_not_tint_the_ground",
        "proves": "the ground just inside a vehicle's reflection probe is lit the same as the ground just outside it",
        "builds_on": ["actor_reflection_probe"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "road sampled from %.1f m to %.1f m beside the vehicle is one colour within %.0f%%"
            % [SAMPLES_M[0], SAMPLES_M[SAMPLES_M.size() - 1], MAX_DIFFERENCE * 100.0]
        ),
        "why": (
            "a reflection probe claims every surface inside its box, not just the vehicle it was"
            + " added for, and `UPDATE_ONCE` freezes what that surface reflects at the moment the"
            + " vehicle was built. Reported from the window as a rectangle around the truck where"
            + " the scene's colour stops applying: measured off that screenshot, road outside the"
            + " box sat at R-B -25 to -39 and road inside it at -7.0 and +9.6."
        ),
        "budget_s": 180.0,
        "needs_gpu": true,
        "milestone": "M2",
    }


func run(harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var err: String = harness.setup_for(PRESET, WEATHER)
    if err != "":
        return fail(err)

    var built: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    var root: Node3D = built["root"] as Node3D
    harness.world.add_child(root)

    # A road of one albedo to measure against.
    #
    # The blockout ground is a checkerboard, and sampling it measured the checks: readings along
    # one line alternated between 0.005 and 0.011 purely by which square they landed on, which is
    # larger than the effect being looked for. This plane has a single albedo, so anything that
    # varies across it is light.
    #
    # It keeps a specular response rather than using the matte chart shader, because a reflection
    # probe acts *through* specular — a perfectly rough test surface would be immune to the fault
    # and the gate would pass on every renderer, broken or not.
    var blockout: MeshInstance3D = harness.world.get_node_or_null(^"Ground") as MeshInstance3D
    if blockout != null:
        blockout.visible = false
    harness.world.add_child(_uniform_road())

    var probe: ReflectionProbe = _probe(root)
    if probe == null:
        return fail("the vehicle has no reflection probe, so there is nothing to measure")
    # Daylight first, and enough frames for `UPDATE_ONCE` to take its single capture.
    await harness.advance_frames(CAPTURE_FRAMES, "static", "probe")

    # Then the weather changes under it, the way F2 does in the window: the sun and the fill go
    # out and the ambient becomes a night sky. Everything the renderer lights now should follow —
    # and anything still showing the old world is showing a capture that was never refreshed.
    for child: Node in harness.world.get_children():
        var light: Light3D = child as Light3D
        if light != null:
            light.visible = false
    var holder: WorldEnvironment = (
        harness.world.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
    )
    if holder == null or holder.environment == null:
        return fail("the world has no environment to relight")
    holder.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    holder.environment.ambient_light_sky_contribution = 0.0
    holder.environment.ambient_light_color = NIGHT_AMBIENT
    holder.environment.ambient_light_energy = NIGHT_AMBIENT_ENERGY

    # Two patches of ground at the same depth, one each side of the box's edge, so anything that
    # varies with distance — fog above all — lands on both equally and cancels.
    var centre: Vector3 = probe.global_position
    # The ground plane itself, not the bottom of the vehicle: the lowest thing the truck draws is
    # a wheel sunk below y = 0, and sampling there reads tyre rather than road.
    var at: Array[Vector3] = []
    for offset: float in SAMPLES_M:
        at.append(Vector3(centre.x + offset, GROUND_Y, centre.z))
    # A camera placed for the measurement rather than a shot preset. `hero_3q` frames the vehicle,
    # so both sample points landed off the side of a 1920-wide frame — the ground beside a truck
    # is not what a hero shot is for.
    harness.camera.look_at_from_position(
        centre + Vector3(0.0, CAMERA_HEIGHT_M, CAMERA_BACK_M), centre, Vector3.UP
    )
    await harness.advance_frames(1, "static", "probe")

    var shot: Dictionary = await harness.capture_hdr("probe/ground", "static", CONVERGE)
    if (shot["error"] as String) != "":
        return fail(shot["error"] as String)
    var image: Image = shot["image"] as Image
    if image == null:
        return fail("the capture came back with no image")

    var read: Array[Vector3] = []
    for point: Vector3 in at:
        read.append(PhotoChart.window_rgb(image, harness.camera.unproject_position(point)))
    var farthest: Vector3 = read[read.size() - 1]
    if farthest.length() <= 0.0:
        return fail("the open road photographed black; there is nothing to compare")

    # Compared as colours rather than as brightnesses: the fault takes the sky's blue out of the
    # enclosed road, which a luminance reading would barely show. Every sample is held against
    # the farthest one, which is the piece of road no probe is near.
    var difference: float = 0.0
    var worst_at: float = 0.0
    for index: int in read.size():
        var apart: float = (read[index] - farthest).length() / farthest.length()
        if apart > difference:
            difference = apart
            worst_at = SAMPLES_M[index]
    if difference > MAX_DIFFERENCE:
        return fail(
            (
                "the road is not one colour: %.1f m from the vehicle it reads"
                + " (%.4f, %.4f, %.4f) while open road at %.1f m reads (%.4f, %.4f, %.4f),"
                + " %.1f%% apart. A reflection probe claims every surface inside its box and"
                + " `UPDATE_ONCE` freezes what they reflect, so the road beside the vehicle keeps"
                + " the world it was built in. This is the rectangle reported from the window."
            ) % [
                worst_at, read[0].x, read[0].y, read[0].z,
                SAMPLES_M[SAMPLES_M.size() - 1], farthest.x, farthest.y, farthest.z,
                difference * 100.0
            ],
            difference
        )
    return ok(
        (
            "the road is one colour from %.1f m to %.1f m beside the vehicle after the world"
            + " was relit under a frozen capture: worst sample at %.1f m is %.1f%% from open"
            + " road (%.4f, %.4f, %.4f)"
        ) % [
            SAMPLES_M[0], SAMPLES_M[SAMPLES_M.size() - 1], worst_at, difference * 100.0,
            farthest.x, farthest.y, farthest.z
        ],
        difference
    )


## A large plane of one albedo and a road-like roughness, standing in for the ground.
func _uniform_road() -> MeshInstance3D:
    var plane: PlaneMesh = PlaneMesh.new()
    plane.size = Vector2(ROAD_SIZE_M, ROAD_SIZE_M)
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = ROAD_ALBEDO
    material.roughness = ROAD_ROUGHNESS
    material.metallic = 0.0
    var road: MeshInstance3D = MeshInstance3D.new()
    road.name = "UniformRoad"
    road.mesh = plane
    road.material_override = material
    road.position = Vector3(0.0, GROUND_Y, 0.0)
    return road


func _probe(root: Node3D) -> ReflectionProbe:
    for child: Node in root.get_children():
        var probe: ReflectionProbe = child as ReflectionProbe
        if probe != null:
            return probe
    return null
