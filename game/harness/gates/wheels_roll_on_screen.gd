extends GateBase
## The drawn wheels roll, and they roll the right way round.
##
## A wheel's drawn geometry is posed by its axle nodes, and an axle node does not rotate, so
## a vehicle can drive across the screen with its wheels standing perfectly still. Spinning
## them needs a separate angle from the solver — and an angle applied with the wrong sign
## looks exactly as busy as one applied with the right sign.
##
## The oracle is rolling without slipping, measured on the drawn geometry: the contact patch
## of a rolling wheel is stationary in the world, and the top of it moves at twice the
## vehicle's speed. So the same tyre vertex, tracked through one revolution, must be slowest
## when it is at the bottom of the wheel and fastest when it is at the top. Reverse the spin
## and those two swap, which is the fault this exists to catch.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const PRESET: String = "hero_3q"
const SUBSTEP_HZ: float = 10000.0
const SETTLE_SECONDS: float = 1.0
const DRIVE_SECONDS: float = 3.0
const THROTTLE: float = 0.2
## The wheels must actually turn, or every comparison below is between two noise figures.
const MIN_REVOLUTIONS: float = 1.0
## Speed at the contact patch as a share of speed at the top of the wheel. Rolling gives
## nearly zero; a wheel spun backwards gives more than one.
const MAX_CONTACT_SHARE: float = 0.35


static func meta() -> Dictionary:
    return {
        "name": "wheels_roll_on_screen",
        "proves": "the drawn wheels turn with the vehicle's motion: the contact patch is the slowest part of the tyre and the top the fastest",
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "wheels turn at least %.0f revolution; drawn speed at the contact patch under"
            % MIN_REVOLUTIONS
            + " %.0f%% of the speed at the top of the same tyre" % (MAX_CONTACT_SHARE * 100.0)
        ),
        "why": (
            "rolling without slipping fixes the contact patch in the world and puts the top"
            + " of the wheel at twice road speed. That ordering reverses if the spin is"
            + " applied backwards, which no still image shows and which is the most likely"
            + " way to get wheel rotation wrong."
        ),
        "budget_s": 120.0,
        "needs_gpu": true,
        "milestone": "M1",
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
    var truck: TruckParser = built["truck"] as TruckParser
    harness.world.add_child(built["root"] as Node3D)
    var rig: Dictionary = RigBuilder.build(truck, 0.02)
    if (rig["error"] as String) != "":
        return fail(rig["error"] as String)
    var solver: RefCounted = rig["solver"] as RefCounted
    solver.set_ground(0.0, true)

    var tyre: MeshInstance3D = _tyre_of(built, 0)
    if tyre == null:
        return fail("the first wheel has no drawn tyre to measure")
    var vertex: Vector3 = _sample_vertex(tyre)
    if vertex == Vector3.ZERO:
        return fail("the tyre mesh has no vertices")

    var dt: float = 1.0 / SUBSTEP_HZ
    var chunk: int = int(SUBSTEP_HZ / 60.0)
    for _i: int in int(SETTLE_SECONDS * 60.0):
        solver.step(dt, chunk)
        _pose(built, truck, solver)
    solver.start_engine()
    solver.set_gear_selector(1)
    solver.set_throttle(THROTTLE)

    var start_rotation: float = solver.get_wheel_rotation(0)
    var previous: Vector3 = tyre.global_transform * vertex
    var contact_speed: float = INF
    var top_speed: float = 0.0
    var contact_height: float = 0.0
    var top_height: float = 0.0
    for _frame: int in int(DRIVE_SECONDS * 60.0):
        solver.step(dt, chunk)
        _pose(built, truck, solver)
        var here: Vector3 = tyre.global_transform * vertex
        var speed: float = here.distance_to(previous) / (1.0 / 60.0)
        previous = here
        # Where the vertex is on the wheel, relative to the axle it turns about.
        var axle: Vector3 = (
            solver.get_node_position(truck.wheels[0]["node1"] as int)
            + solver.get_node_position(truck.wheels[0]["node2"] as int)
        ) * 0.5
        var height: float = here.y - axle.y
        if height < contact_height:
            contact_height = height
            contact_speed = speed
        if height > top_height:
            top_height = height
            top_speed = speed

    var revolutions: float = absf(solver.get_wheel_rotation(0) - start_rotation) / TAU
    if revolutions < MIN_REVOLUTIONS:
        return fail(
            "the wheel turned %.2f revolutions in %.0f s: there is nothing to measure"
            % [revolutions, DRIVE_SECONDS],
            revolutions
        )
    if not is_finite(contact_speed) or top_speed <= 0.0:
        return fail("the tracked tyre vertex never reached the top or bottom of the wheel")
    var share: float = contact_speed / top_speed
    if share > MAX_CONTACT_SHARE:
        return fail(
            "the tyre's contact patch moved at %.2f m/s against %.2f m/s at the top of the"
            % [contact_speed, top_speed]
            + " wheel (%.0f%%): the drawn wheel is not rolling with the vehicle"
            % (share * 100.0),
            share
        )
    return ok(
        (
            "%.1f revolutions in %.0f s: the tracked tyre vertex ran at %.2f m/s %.0f mm"
            + " below the axle and %.2f m/s %.0f mm above it (%.0f%%)"
        )
        % [
            revolutions, DRIVE_SECONDS, contact_speed, absf(contact_height) * 1000.0,
            top_speed, top_height * 1000.0, share * 100.0,
        ],
        share
    )


func _pose(built: Dictionary, truck: TruckParser, solver: RefCounted) -> void:
    var angles: PackedFloat32Array = PackedFloat32Array()
    for wheel: int in solver.wheel_count():
        angles.append(solver.get_wheel_rotation(wheel))
    VehicleBuilder.apply_pose(built, truck, solver.get_positions(), angles)


func _tyre_of(built: Dictionary, index: int) -> MeshInstance3D:
    var wheels: Array[Node3D] = built["wheel_nodes"] as Array[Node3D]
    if index >= wheels.size():
        return null
    return wheels[index].get_node_or_null(^"Tyre") as MeshInstance3D


## A vertex out at the tread, where the rolling difference between the top and the bottom of
## the wheel is largest. The tyre mesh is built in rim-local space, so the furthest vertex
## from the rim's own axis is on the tread band.
func _sample_vertex(tyre: MeshInstance3D) -> Vector3:
    if tyre.mesh == null or tyre.mesh.get_surface_count() == 0:
        return Vector3.ZERO
    var vertices: PackedVector3Array = (
        tyre.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
    )
    var best: Vector3 = Vector3.ZERO
    var furthest: float = -1.0
    for candidate: Vector3 in vertices:
        # Distance from the axle, which in rim-local space is the X axis.
        var radius: float = Vector2(candidate.y, candidate.z).length()
        if radius > furthest:
            furthest = radius
            best = candidate
    return best
