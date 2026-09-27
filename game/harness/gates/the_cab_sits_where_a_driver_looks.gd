extends GateBase
## The instruments are on the dashboard and the steering wheel turns on its column.
##
## Two faults a session found by looking, and neither shows up in the gate that checks the
## needles: the dials "flying in the air" in front of the windscreen, and the wheel "not spinning
## around its correct axle". Both are about frames rather than about numbers, which is exactly
## the kind of thing that passes every check written about values.
##
## So this measures where the cluster ends up — on the dashboard, below the eye, in the lower half
## of what the driver sees — and what the wheel actually turns about: its own column, which on
## this mesh is its shortest axis and the axis the rim is perpendicular to.

const MOD_DIR: String = "assets/mods/ChevyS1023"
const TRUCK: String = "S10offroad.truck"
## How far above the dashboard prop's own origin the dials may sit, and how far below the eye.
const MAX_ABOVE_DASH_M: float = 0.25
const MIN_BELOW_EYE_M: float = 0.15
## Where the dials have to land in the driver's view: below the middle of the frame and inside it.
const MIN_SCREEN_FRACTION: float = 0.5
const MAX_SCREEN_FRACTION: float = 0.98
## How far the wheel's turn axis may sit from its column, in degrees.
const MAX_AXIS_OFF_DEG: float = 2.0
## And how much a rim point may leave the plane it turns in, as a share of the rim's radius.
const MAX_PLANE_DRIFT: float = 0.02


static func meta() -> Dictionary:
    return {
        "name": "the_cab_sits_where_a_driver_looks",
        "proves": "the instrument cluster sits on the dashboard and inside the driver's view, and the steering wheel turns about its own column",
        "builds_on": ["cockpit_tracks_the_drivetrain"],
        "oracle": GateBase.ORACLE_INVARIANT,
        "threshold": (
            "dials within %.2f m above the dashboard and %.2f m below the eye, landing in the"
            % [MAX_ABOVE_DASH_M, MIN_BELOW_EYE_M]
            + " lower half of the driver's view, and a wheel axis within %.0f degrees of its"
            % MAX_AXIS_OFF_DEG + " column"
        ),
        "why": (
            "a session reported dials floating in the air and a wheel turning about the wrong"
            + " axis, and the gate that checks the needles' angles passed throughout: it measures"
            + " values, and these are frames. A cluster placed from the driver's eye rather than"
            + " from the dashboard is out by wherever the mod hung its camera."
        ),
        "budget_s": 60.0,
        "needs_gpu": true,
        "milestone": "M1",
    }


func run(harness: Node) -> Dictionary:
    var mod_dir: String = SourceScan.repo_root().path_join(MOD_DIR)
    if not DirAccess.dir_exists_absolute(mod_dir):
        return ok("skipped: hero asset not present at %s" % MOD_DIR, 0)
    var err: String = harness.setup_for("hero_3q")
    if err != "":
        return fail(err)
    var built: Dictionary = VehicleBuilder.build(mod_dir, TRUCK)
    if (built.get("error", "") as String) != "":
        return fail(built["error"] as String)
    var truck: TruckParser = built["truck"] as TruckParser
    var root: Node3D = built["root"] as Node3D
    harness.world.add_child(root)
    var cluster: Node3D = Cockpit.build(root, truck, built)
    if cluster == null:
        return ok("skipped: the rig declares no cab to mount a cluster in", 0)
    await harness.advance_frames(1, "static", "cab")

    var placed: Dictionary = _cluster_is_on_the_dashboard(truck, built, cluster)
    if (placed["error"] as String) != "":
        return fail(placed["error"] as String, placed["value"] as float)
    var seen: Dictionary = _cluster_is_in_view(harness, built, truck, cluster)
    if (seen["error"] as String) != "":
        return fail(seen["error"] as String, seen["value"] as float)
    var column: Dictionary = _wheel_turns_on_its_column()
    if (column["error"] as String) != "":
        return fail(column["error"] as String, column["value"] as float)
    return ok(
        "dials %.3f m above the dashboard and %.3f m below the eye, landing %.0f%% down the"
        % [placed["above"] as float, placed["below"] as float,
           (seen["value"] as float) * 100.0]
        + " driver's view; the wheel turns within %.2f degrees of its column"
        % (column["value"] as float),
        placed["above"]
    )


## The cluster is mounted on the dashboard, not hung off the driver's eye.
func _cluster_is_on_the_dashboard(
    truck: TruckParser, built: Dictionary, cluster: Node3D
) -> Dictionary:
    var out: Dictionary = {"error": "", "value": 0.0, "above": 0.0, "below": 0.0}
    var dashboard: Node3D = null
    var props: Array[Node3D] = built.get("prop_nodes", [] as Array[Node3D]) as Array[Node3D]
    for index: int in mini(props.size(), truck.props.size()):
        if (truck.props[index]["mesh"] as String).to_lower().contains("dash"):
            dashboard = props[index]
            break
    if dashboard == null:
        out["error"] = "the rig has no dashboard prop, so there is nothing to mount a cluster on"
        return out
    var eye: Vector3 = (built["rig_to_local"] as Transform3D) * Cockpit.eye_position(truck)
    var above: float = cluster.position.y - dashboard.position.y
    var below: float = eye.y - cluster.position.y
    out["above"] = above
    out["below"] = below
    out["value"] = above
    if above < 0.0 or above > MAX_ABOVE_DASH_M:
        out["error"] = (
            "the cluster sits %.3f m above the dashboard, outside 0 to %.2f m: it is not on it"
            % [above, MAX_ABOVE_DASH_M]
        )
        return out
    if below < MIN_BELOW_EYE_M:
        out["error"] = (
            "the cluster sits %.3f m below the driver's eye, under %.2f: it is in the driver's"
            % [below, MIN_BELOW_EYE_M] + " face"
        )
    return out


## And a driver can see it: from the cab, the dials are below the middle of the frame.
func _cluster_is_in_view(
    harness: Node, built: Dictionary, truck: TruckParser, cluster: Node3D
) -> Dictionary:
    var out: Dictionary = {"error": "", "value": 0.0}
    var eye: Vector3 = (built["rig_to_local"] as Transform3D) * Cockpit.eye_position(truck)
    var root: Node3D = built["root"] as Node3D
    var camera: Camera3D = harness.camera
    # Through the lens the driver's seat actually uses: the cluster's height is chosen as an
    # angle below the sightline, and an angle only becomes a place on the screen once the lens
    # is decided.
    var lens: CameraAttributesPhysical = CameraAttributesPhysical.new()
    lens.frustum_focal_length = CockpitCfg.FOCAL_MM
    camera.attributes = lens
    # Sitting in the driver's seat, looking where the vehicle is going.
    camera.look_at_from_position(
        root.to_global(eye), root.to_global(eye + Vector3(0.0, -0.05, -4.0)), Vector3.UP
    )
    var screen: Vector2 = camera.unproject_position(cluster.global_position)
    var height: float = float(camera.get_viewport().get_visible_rect().size.y)
    var down: float = screen.y / maxf(height, 1.0)
    out["value"] = down
    if down < MIN_SCREEN_FRACTION or down > MAX_SCREEN_FRACTION:
        out["error"] = (
            "the dials land %.0f%% down the driver's view, outside %.0f%% to %.0f%%: they are"
            % [down * 100.0, MIN_SCREEN_FRACTION * 100.0, MAX_SCREEN_FRACTION * 100.0]
            + " not where a driver glances"
        )
    return out


## The wheel turns about its column: the axis of the rotation is the wheel's own short axis, and
## a point on the rim stays in the rim's plane.
func _wheel_turns_on_its_column() -> Dictionary:
    var out: Dictionary = {"error": "", "value": 0.0}
    var rest: Basis = Cockpit.steering_basis(0.0)
    var turned: Basis = Cockpit.steering_basis(90.0)
    var relative: Basis = rest.inverse() * turned
    var axis: Vector3 = relative.get_rotation_quaternion().get_axis().normalized()
    var off: float = rad_to_deg(acos(clampf(absf(axis.dot(Vector3.UP)), -1.0, 1.0)))
    out["value"] = off
    if off > MAX_AXIS_OFF_DEG:
        out["error"] = (
            "the wheel turns about %v, %.1f degrees from its own column: it is spinning on the"
            % [axis, off] + " wrong axis"
        )
        return out
    # And the rim goes round rather than tumbling: a point on it keeps its distance from the
    # column and stays in the plane the rim lies in.
    var rim: Vector3 = Vector3(0.185, 0.0, 0.0)
    var moved: Vector3 = relative * rim
    var drift: float = absf(moved.y) / rim.length()
    if drift > MAX_PLANE_DRIFT:
        out["error"] = (
            "a point on the rim leaves its own plane by %.1f%% of the rim's radius: the wheel is"
            % (drift * 100.0) + " tumbling rather than turning"
        )
    return out
