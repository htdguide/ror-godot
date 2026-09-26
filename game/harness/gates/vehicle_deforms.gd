extends GateBase
## Drives the whole vehicle from node positions, the way the solver will.
##
## Everything before this checks the vehicle at rest. This checks the entry point that
## matters per frame: hand `apply_pose` a new set of node positions and every part and
## wheel must follow, with suspension travel moving only the wheels it belongs to.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
const PRESET: String = "hero_3q"
## Front axle lift, in metres. Large enough to measure against float noise, small enough
## to be a plausible suspension movement.
const LIFT_M: float = 0.15
const TOLERANCE_M: float = 0.005
## Rear wheels must stay put while the front moves, or the pose is being applied to the
## whole vehicle rather than to the nodes that changed.
const STATIONARY_TOLERANCE_M: float = 0.001


static func meta() -> Dictionary:
    return {
        "name": "vehicle_deforms",
        "proves": "apply_pose drives every part and wheel from node positions, and only the nodes that moved",
        # posing every part from node positions and checking where each lands is the assembly check
        # with the vehicle moving.
        "builds_on": ["vehicle_assembly"],
        "oracle": GateBase.ORACLE_COMPUTED,
        "threshold": (
            "lifted wheels move %.2f m within %.3f m; unlifted wheels move under %.3f m"
            % [LIFT_M, TOLERANCE_M, STATIONARY_TOLERANCE_M]
        ),
        "why": (
            "the solver will call this every frame. A pose that moves the whole vehicle"
            + " looks just as correct in a still image as one that moves the right parts,"
            + " so the check is that unmoved nodes leave their geometry alone."
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

    # Which nodes belong to the front axle, so the check knows what should move.
    var front: PackedInt32Array = PackedInt32Array()
    for index: int in [0, 1]:
        var wheel: Dictionary = truck.wheels[index]
        front.append(wheel["node1"] as int)
        front.append(wheel["node2"] as int)

    var rest_wheels: PackedVector3Array = _wheel_positions(built)
    var lifted: PackedVector3Array = truck.nodes.duplicate()
    for node: int in front:
        lifted[node] = lifted[node] + Vector3(0.0, LIFT_M, 0.0)
    VehicleBuilder.apply_pose(built, truck, lifted)
    await harness.advance_frames(2, "static", "lifted")
    var moved_wheels: PackedVector3Array = _wheel_positions(built)

    var problems: PackedStringArray = PackedStringArray()
    for i: int in mini(rest_wheels.size(), moved_wheels.size()):
        var travelled: Vector3 = moved_wheels[i] - rest_wheels[i]
        var is_front: bool = i < 2
        if is_front and absf(travelled.y - LIFT_M) > TOLERANCE_M:
            problems.append(
                "front wheel %d moved %.3f m vertically, expected %.2f" % [i, travelled.y, LIFT_M]
            )
        elif not is_front and travelled.length() > STATIONARY_TOLERANCE_M:
            problems.append(
                "rear wheel %d moved %.3f m when nothing should have moved it"
                % [i, travelled.length()]
            )
    if problems.size() > 0:
        return fail("; ".join(problems), problems.size())

    # And the body follows too: its geometry must sit where the deformed rig puts it.
    var part: SkinnedFlexbody = (built["parts"] as Array[SkinnedFlexbody])[0]
    var expected: Vector3 = FlexbodyBinder.reference_positions(
        lifted, part.binding, part.triads
    )[0]
    var actual_local: Vector3 = part.rendered_position(0)
    var root_transform: Transform3D = (built["root"] as Node3D).global_transform
    var expected_world: Vector3 = root_transform * (
        ActorFrame.of(lifted, truck.camera_nodes).affine_inverse() * expected
    )
    var body_error: float = (actual_local - expected_world).length()
    if body_error > TOLERANCE_M:
        return fail(
            "body geometry is %.3f m from where the deformed rig puts it" % body_error,
            body_error
        )

    var shot: Dictionary = await harness.capture_shot("vehicle_deforms", "static", 6)
    if shot["error"] != "":
        return fail(shot["error"] as String)
    return ok(
        "front wheels rose %.2f m, rear wheels held, body within %.4f m: %s"
        % [LIFT_M, body_error, shot["png"]],
        body_error
    )


func _wheel_positions(built: Dictionary) -> PackedVector3Array:
    var out: PackedVector3Array = PackedVector3Array()
    for node: Node3D in built["wheel_nodes"] as Array[Node3D]:
        out.append(node.global_position)
    return out
