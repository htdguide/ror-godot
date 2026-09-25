extends GateBase
## The hero rig drives itself forward under its own engine, and rolls rather than slides.
##
## The oracle is rolling without slipping: over a run with grip, the distance a vehicle
## travels equals the arc its tyres turned through. The solver measures tread speed about
## each axle and integrates it; the vehicle's own displacement comes from its node positions.
## Neither knows about the other, and their agreement is a physical identity rather than a
## threshold chosen here.
##
## It also checks the two things that were actually wrong. The rig must travel along its own
## forward axis, because a vehicle whose wheels fight each other slews sideways; and the four
## wheels must turn at the same rate, because that is what they do not do when half of them
## are driven backwards.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const SUBSTEP_HZ: float = 10000.0
const SETTLE_SECONDS: float = 1.0
const DRIVE_SECONDS: float = 5.0
## Part throttle. At full throttle this rig breaks traction, which is correct behaviour for
## 11 kNm at the wheels on concrete and would make the rolling comparison meaningless.
const THROTTLE: float = 0.2
## The rig must actually go somewhere, or every ratio below is satisfied by standing still.
const MIN_TRAVEL_M: float = 5.0
## Distance travelled as a share of the arc the tyres turned through. Under 1 because some
## slip is real; a rig that is spinning its wheels falls far below it.
const MIN_ROLLING_RATIO: float = 0.8
## Sideways travel as a share of forward travel. A rig driving straight has some, because a
## soft-body vehicle on part throttle wanders; one whose wheels oppose each other had 65%.
const MAX_LATERAL_SHARE: float = 0.15
## Spread of the four wheels' tread speeds, as a share of the fastest. With the axle nodes
## in file order rather than sorted, this measured 96%.
const MAX_WHEEL_SPREAD: float = 0.25


static func meta() -> Dictionary:
    return {
        "name": "rig_drives_forward",
        "proves": "the rig accelerates under its own engine, travels along its own forward axis, and rolls rather than slides",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "travels at least %.0f m; distance at least %.0f%% of the arc the tyres turned"
            % [MIN_TRAVEL_M, MIN_ROLLING_RATIO * 100.0]
            + " through; lateral travel under %.0f%% of forward; wheel speeds within %.0f%%"
            % [MAX_LATERAL_SHARE * 100.0, MAX_WHEEL_SPREAD * 100.0]
        ),
        "why": (
            "rolling without slipping ties the vehicle's displacement to its wheels'"
            + " rotation, and the two are measured by different parts of the solver, so"
            + " agreement is an identity rather than a number chosen here. The straightness"
            + " and symmetry bounds are the fault this gate was written for: driven with its"
            + " axle nodes in file order the rig drove its left wheels forward and its right"
            + " wheels backward, and travelled 4.70 m with 3.41 m of that sideways."
        ),
        "budget_s": 60.0,
        "needs_gpu": false,
        "milestone": "M1",
    }


func run(_harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var rig: Dictionary = RigBuilder.from_file(mod_dir, TRUCK, 0.02)
    if (rig["error"] as String) != "":
        return fail(rig["error"] as String)
    var truck: TruckParser = rig["truck"] as TruckParser
    var solver: RefCounted = rig["solver"] as RefCounted
    if not solver.has_engine():
        return fail("%s declares no engine: there is nothing to drive it with" % TRUCK)
    if solver.wheel_count() == 0:
        return fail("%s has no wheels registered with the solver" % TRUCK)
    solver.set_ground(0.0, true)

    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    for _i: int in int(SETTLE_SECONDS * 60.0):
        solver.step(dt, chunk)

    var start_frame: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
    var rotation_at_start: PackedFloat32Array = _rotations(solver)
    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(THROTTLE)

    for frame: int in int(DRIVE_SECONDS * 60.0):
        solver.step(dt, chunk)
        if not is_finite(solver.get_node_position(0).length()):
            return fail("the solver diverged %.2f s into the run" % (float(frame) / 60.0))

    var end_frame: Transform3D = ActorFrame.of(solver.get_positions(), truck.camera_nodes)
    var travel: Vector3 = end_frame.origin - start_frame.origin
    # In the frame the rig started in: -Z is where it was pointing, X is across it.
    var forward: float = -travel.dot(start_frame.basis.z)
    var lateral: float = absf(travel.dot(start_frame.basis.x))
    var distance: float = travel.length()
    if forward < MIN_TRAVEL_M:
        return fail(
            "the rig moved %.2f m forward in %.0f s at %.0f%% throttle: it is not driving"
            % [forward, DRIVE_SECONDS, THROTTLE * 100.0],
            forward
        )

    # The arc every driven tyre turned through, averaged. The solver integrates tread speed
    # about the axle; it has no idea where the vehicle went.
    var arc: float = 0.0
    var driven: int = 0
    var slowest: float = INF
    var fastest: float = 0.0
    for wheel: int in solver.wheel_count():
        var turned: float = absf(_rotations(solver)[wheel] - rotation_at_start[wheel])
        var radius: float = truck.wheels[wheel]["tire_radius"] as float
        arc += turned * radius
        driven += 1
        var speed: float = absf(solver.get_wheel_speed(wheel))
        slowest = minf(slowest, speed)
        fastest = maxf(fastest, speed)
    arc /= maxf(float(driven), 1.0)

    var rolling: float = distance / maxf(arc, 0.001)
    if rolling < MIN_ROLLING_RATIO:
        return fail(
            "the rig travelled %.2f m while its tyres turned through %.2f m of arc (%.0f%%):"
            % [distance, arc, rolling * 100.0]
            + " the wheels are slipping, not rolling",
            rolling
        )
    var lateral_share: float = lateral / maxf(forward, 0.001)
    if lateral_share > MAX_LATERAL_SHARE:
        return fail(
            "the rig moved %.2f m forward and %.2f m sideways (%.0f%%): it is not driving"
            % [forward, lateral, lateral_share * 100.0]
            + " along its own axis",
            lateral_share
        )
    var spread: float = (fastest - slowest) / maxf(fastest, 0.001)
    if spread > MAX_WHEEL_SPREAD:
        return fail(
            "the four wheels' tread speeds spread %.0f%% (%.2f to %.2f m/s): they are not"
            % [spread * 100.0, slowest, fastest]
            + " being driven together",
            spread
        )
    return ok(
        (
            "%.2f m forward and %.2f m sideways (%.0f%%) in %.0f s at %.0f%% throttle;"
            + " tyres turned %.2f m of arc (rolling %.0f%%); wheels %.2f-%.2f m/s"
            + " (spread %.0f%%); %.0f rpm in gear %d"
        )
        % [
            forward, lateral, lateral_share * 100.0, DRIVE_SECONDS, THROTTLE * 100.0, arc,
            rolling * 100.0, slowest, fastest, spread * 100.0, solver.engine_rpm(),
            solver.engine_gear(),
        ],
        forward
    )


func _rotations(solver: RefCounted) -> PackedFloat32Array:
    var out: PackedFloat32Array = PackedFloat32Array()
    for wheel: int in solver.wheel_count():
        out.append(solver.get_wheel_rotation(wheel))
    return out
